if window?
	exports = window.otclient = {}
else
	exports = module.exports = {}

if require?
	common = require('./servercommon')
	ot = require('./operationaltransformation')
	[debug, warn, error] = [common.debug, common.warn, common.error]
else
	[debug, warn, error] = [window.debug, window.warn, window.error]
	ot = window.ot

exports.OTClientDocument = class OTClientDocument extends ot.OTDocument
	constructor: (id, conn, uid) ->
		super(id)
		@listeners = []
		@conn = conn
		@uid = uid
		@versionCounter = 1
		@conn.register(this)
		
	connected: ->
		@conn.join()
		@pendingChanges = false
		@needsAck = false
		@receivedFirstChange = false
		
	reconnect: ->
		@resetState()
		@conn.reconnect()
				
	registerListener: (listener) ->
		@listeners.push(listener)
		
	unregisterListener: (listener) ->
		idx = @listeners.indexOf(listener)
		if idx != -1
			@listeners.splice(idx, 1)
		
	makeVersion: ->
		@versionCounter += 1
		"#{@uid}-#{@versionCounter}"
		
	applyChange: (change) ->
		if not @receivedFirstChange
			@receivedFirstChange = yes
			l.connected() for l in @listeners
		if super(change)
			l.changeApplied(change) for l in @listeners
		
	applyChangeUp: (change) ->
		@applyChange(change)
		
		if @needsAck
			#debug("queuing change", change)
			if not @pendingChanges
				@pendingChanges = change
			else
				@pendingChanges = @pendingChanges.merge(change)
		else
			@conn.send(change)
			@needsAck = change.toVersion
		
	applyChangeDown: (change, ack) ->
		if ack
			if ack != @needsAck
				error("Received ack for version #{ack}, expected #{@needsAck}")
			@needsAck = false
			if @pendingChanges
				[up, down] = change.transform(@pendingChanges, @makeVersion()+'t')
				#debug("received ack, sent pending changes (xform)", @pendingChanges, up, down)
				@applyChange(down)
				@applyChangeUp(up)
				@pendingChanges = false
			else
				#debug("received ack, no pending changes", change, ack)
				@applyChange(change)
		else
			if @needsAck
				#debug("received change, no ack, ignoring", change)
			else
				@applyChange(change)
		
	spliceRange: (start, end, insert) ->
		l = []
		
		if start > 0
			l.push(new ot.OpRetain(start))
		if end != start
			l.push(new ot.OpRemove(end-start))
		if insert
			l = l.concat(insert)
		change = new ot.Change(l, @id, @version, @makeVersion())
		@applyChangeUp(change)
		
	disconnected: ->
		l.disconnected() for l in @listeners
			
exports.Listener = class Listener
	changeApplied: -> false
	connected: -> false
	disconnected: -> false
	connecting: -> false
	
exports.SocketIOConnection = class SocketIOConnection
	constructor: (port) ->
		@connected = false
		@socket = new io.Socket(null, {port: port})
		@socket.connect()
		@document = false
		
		@socket.on 'connect', =>
			@connected = true
			if @document
				@document.connected()
			
		@socket.on 'message', (body) =>
			msg = JSON.parse(body)
			switch msg.type
				when 'change'
					@document.applyChangeDown(ot.deserializeChange(msg.change), msg.acknowlege)
				else
					console.log("error", msg)
			
		@socket.on 'disconnect', =>
			@connected = false
			@document.disconnected()
	
	reconnect: ->
		@socket.connect()
		
	register: (doc) ->
		@document = doc
		if @connected
			@document.connected()
			
	join: ->
		@socket.send JSON.stringify
			type: 'join'
			docid: @document.id
			uid: @document.uid

	send: (change) ->
		@socket.send JSON.stringify
			docid: change.docid
			type: 'change'
			change: change
