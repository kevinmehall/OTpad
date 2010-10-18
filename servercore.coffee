if window?
	exports = window.otserver = {}
else
	exports = module.exports = {}

if require?
	common = require('./servercommon')
	ot = require('./operationaltransformation')
	[debug, warn, error] = [common.debug, common.warn, common.error]
else
	[debug, warn, error] = [window.debug, window.warn, window.error]
	
chooseColor = (usedColors) -> 
	counts = {}
	for i in ot.COLORS
		counts[i] = 0
	for i in usedColors
		if counts[i]?
			counts[i] += 1
	for color of counts
		if counts[color] == 0
			return color
	return ot.COLORS[0]
		

exports.OTServerDocument = class OTServerDocument extends ot.OTDocument
	constructor: (docid) ->
		super(docid)
		@users = {}
		@clients = {}
		@clientCount = 0
		@versionCounter = 1
		
	makeVersion: ->
		@versionCounter += 1
		"server-#{@versionCounter}"
	
	join: (client) ->
		@clientCount += 1
		@clients[client.sessionid] = client
		if @users[client.uid]
			@users[client.uid].active += 1
		else
			@users[client.uid] = 
				active: 1
				name: '<unnamed>'
				color: chooseColor((@users[uid].color for uid of @users))
		@userChanged(client.uid, client.sessionid)
		client.socket.send JSON.stringify
			type: 'users'
			users: @users
		client.socket.send JSON.stringify
			type: 'change'
			docId: @id
			change: @state
		
	handleChange: (change, fromSession) ->
		unmerged = @changesFromTo(change.fromVersion, @version)
		
		[up, down] = unmerged.transform(change, @makeVersion()+'t')
		
		#debug("handleChange: ", change, " unmerged:", unmerged, " up: ", up, " down: ", down)
		
		@applyChange(up)
		
		msg = JSON.stringify
				type: 'change'
				docId: @id
				change: up
			
		for i of @clients
			if i != fromSession # don't send back to author
				@clients[i].socket.send(msg)
			else
				@clients[i].socket.send JSON.stringify
					type: 'change'
					docId: @id
					change:down
					acknowlege: change.toVersion
					
	userChanged: (uid, sessionid) ->
		data = {}
		data[uid] = @users[uid]
		msg = JSON.stringify
			type: 'users'
			users: data
			
		for i of @clients
			if i != sessionid
				@clients[i].socket.send(msg)
	
	leave: (client) ->
		delete @clients[client.sessionid]
		@clientCount -= 1
		@users[client.uid].active -= 1
		@userChanged(client.uid)
