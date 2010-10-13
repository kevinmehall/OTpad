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

exports.OTServerDocument = class OTServerDocument extends ot.OTDocument
	constructor: (docid) ->
		super(docid)
		@clients = {}
		@versionCounter = 1
		
	makeVersion: ->
		@versionCounter += 1
		"server-#{@versionCounter}"
		
	join: (client) ->
		@clients[client.uid] = client
		client.socket.send JSON.stringify
			type: 'change'
			docId: @id
			change: @state
		
	handleChange: (change, fromUid) ->
		unmerged = @changesFromTo(change.fromVersion, @version)
		
		[up, down] = unmerged.transform(change, @makeVersion()+'t')
		
		#debug("handleChange: ", change, " unmerged:", unmerged, " up: ", up, " down: ", down)
		
		@applyChange(up)
		
		msg = JSON.stringify
				type: 'change'
				docId: @id
				change: up
			
		for i of @clients
			if i != fromUid # don't send back to author
				@clients[i].socket.send(msg)
			else
				@clients[i].socket.send JSON.stringify
					type: 'change'
					docId: @id
					change:down
					acknowlege: change.toVersion
		
	leave: (client) ->
		delete @clients[client.uid]
