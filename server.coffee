http =	require('http')
io = 	require('./socket.io')
sys =	require('sys')
fs =	require('fs')
url =	require('url')

md5 = require('./md5-min')

ot =	require('./operationaltransformation')
common = require('./servercommon')
servercore = require('./servercore')
[debug, warn, error] = [common.debug, common.warn, common.error]

serveStaticFile = (res, path, contentType, code) ->
	code ?= 200
	fs.readFile __dirname + path, (err, data) ->
		if (err)
			serve404(res, path, err)
		else
			ctype = 'text/javascript'
			if path.indexOf('.js')!=1
				ctype = 'text/html'
			res.writeHead(200, {'Content-Type': ctype})
			res.write(data, 'utf8')
			res.end()
		
serve404 = (res, path, msg) ->
	sys.log("#{path} -  #{msg}")
	res.writeHead(404)
	res.write("404")
	res.end()

server = http.createServer (req, res) ->
	path = url.parse(req.url).pathname
	
	if not checkDocName(path) or path == '/favicon.ico'
		serve404(res, path, "Invalid file")
	else if path.indexOf('.js')  != -1
		serveStaticFile(res, path, 'text/javascript')
	else if path == '/'
		serveStaticFile(res, '/create_pad.html', 'text/html')
	else
		getDocument path, (doc) ->
			if req.method == 'POST'
				if not doc
					createDocument(path)
				# Redirect back to GET version
				res.writeHead(302, {'Location': path})
				res.write("Creating...", 'utf8')
				res.end()
			else if doc
				serveStaticFile(res, '/pad.html', 'text/html')
			else
				serveStaticFile(res, '/create_pad.html', 'text/html', 404)
				


clients = []
documents = {}
FLUSH_TIMEOUT = 10*1000

markDirty = (doc) ->
	if not doc.write_timer
		doc.write_timer = setTimeout(->
			saveDocument(doc)
			doc.write_timer = false
		, FLUSH_TIMEOUT)
		

getDocument = (docid, callback) ->
	if documents[docid]
		callback(documents[docid])
	else
		loadDocument docid, (doc) ->
			if doc
				callback(doc)
			else
				callback(false)
	
persistDir = 'db'

checkDocName = (name) ->
	(/^\/[a-zA-Z0-9-_.]*$/).test(name)

saveDocument = (doc, callback) ->
	if not checkDocName(doc.id)
		return
		
	data = JSON.stringify
		id: doc.id
		state: doc.state
		version: doc.version
		versionCounter: doc.versionCounter

	fs.writeFile persistDir+doc.id, data, ->
		sys.log("Saved #{doc.id}")
		if callback then callback()
	
loadDocument = (docid, callback) ->
	if not checkDocName(docid)
		callback(false)
		return
	fs.readFile persistDir+docid, (err, data) ->
		if err
			console.log("file #{docid}, #{err}")
			callback(false)
		else
			d = JSON.parse(data)
			d.clients = {}
			d.versionHistory = {}
			d.__proto__ = servercore.OTServerDocument.prototype
			ot.deserializeChange(d.state)
			documents[d.id] = d
			sys.log("Loaded #{docid}")
			callback(d)
	
createDocument = (docid) ->		
	doc = new servercore.OTServerDocument(docid)
	#doc.setFromChange(new ot.Change([], docid, 'null', doc.makeVersion()))
	documents[docid] = doc
	debug("Created document #{docid}")
	return doc

socket = io.listen(server)

verifyDB = {}

socket.on 'connection', (client) ->
	c = {socket: client, documents:[], sessionid:client.sessionId}
	clients.push(c)
	
	client.on 'message', (body) ->
		try
			msg = JSON.parse(body)
			switch msg.type
				when 'change'
					doc = documents[msg.docid]
					doc.handleChange(ot.deserializeChange(msg.change), c.sessionid)
					markDirty(doc)
				when 'join'
					getDocument msg.docid, (doc) ->
						c.uid = msg.uid
						c.documents.push(doc.id)
						doc.join(c)
				when 'verify'
					if msg.toVersion of verifyDB
						other = verifyDB[msg.toVersion]
						if msg.hash == other.hash
							#debug("Verify version #{msg.toVersion} OK")
						else
							common.error("Verify failed for #{msg.toVersion}, from #{msg.fromVersion} is #{msg.hash}. Other is from #{other.fromVersion} with #{other.hash}")
					else
						verifyDB[msg.toVersion] = msg
						
					
		catch error
			sys.log("Error: #{error.msg}, #{error.stack}")
	
		
	client.on 'disconnect', ->
		for docid in c.documents
			doc = documents[docid]
			count = doc.leave(c)
			if count == 0
				sys.log("Document #{docid} has no users")
		clients.splice(clients.indexOf(c), 1)
		
server.listen(8123)
debug("Server started")
