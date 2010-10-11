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
		@pendingChanges = false
		@needsAck = false
		
		if @conn
			@conn.register(this)
			
	registerListener: (listener) ->
		@listeners.push(listener)
		
	unregisterListener: (listener) ->
		idx = @listeners.indexOf(listener)
		if idx != -1
			@listeners.splice(idx, 1)
		
	makeVersion: ->
		"#{@uid}-#{new Date().getTime()}-#{Math.round(Math.random()*100000)}"
		
	applyChange: (change) ->
		if super(change)
			l.changeApplied(change) for l in @listeners
		
	applyChangeUp: (change) ->
		@applyChange(change)
		
		if @needsAck
			debug("queuing change", change)
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
				[down, up] = @pendingChanges.transform(change)
				debug("received ack, sent pending changes", @pendingChanges, up, down)
				@applyChange(down)
				@applyChangeUp(up)
				@pendingChanges = false
			else
				debug("received ack, no pending changes", change, ack)
				@applyChange(change)
		else
			if @needsAck
				debug("received change, no ack, ignoring", change)
			else
				@applyChange(change)
		
	spliceRange: (start, end, insert) ->
		l = [new ot.OpRetain(start)]
		
		if end != start
			l.push(new ot.OpRemove(end-start))
		if insert
			l = l.concat(insert)
		
		l.push(new ot.OpRetain(@length() - end))
		change = new ot.Change(l, @id, @version, @makeVersion())
		@applyChangeUp(change)
		
exports.Listener = class Listener
	changeApplied: -> false
