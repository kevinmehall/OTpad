http =	require('http')
io = 	require('./socket.io')
sys =	require('sys')
fs =	require('fs')
url =	require('url')

ot =	require('./operationaltransformation')
common = require('./servercommon')
[debug, warn, error] = [common.debug, common.warn, common.error]

server = http.createServer (req, res) ->
	path = url.parse(req.url).pathname
	
	error = (err) ->
		sys.log("#{path} -  #{err}")
		res.writeHead(404)
		res.write("404")
		res.end()
	
	if not checkDocName(path) or path == '/favicon.ico'
		error("Invalid file")
		return
	
	if path.indexOf('.js') == -1
		sys.log("Serving page #{path}")
		path = '/index.html'
				
	fs.readFile __dirname + path, (err, data) ->
		if (err)
			error(err)
		else
			ctype = 'text/javascript'
			if path.indexOf('.js')!=1
				ctype = 'text/html'
			res.writeHead(200, {'Content-Type': ctype})
			res.write(data, 'utf8')
			res.end()

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
				callback(createDocument(docid))
	
persistDir = 'db'

checkDocName = (name) -> (/^\/[a-zA-Z0-9-_.]+$/).test(name)

saveDocument = (doc, callback) ->
	if not checkDocName(doc.id)
		return
		
	data = JSON.stringify
		id: doc.id
		state: doc.state
		version: doc.version

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
			d.__proto__ = ot.OTServerEndpoint.prototype
			ot.deserializeChange(d.state)
			documents[d.id] = d
			sys.log("Loaded #{docid}")
			callback(d)
	
createDocument = (docid) ->		
	doc = new ot.OTServerEndpoint(docid)
	#doc.setFromChange(new ot.Change([], docid, 'null', doc.makeVersion()))
	documents[docid] = doc
	debug("Created document #{docid}")
	return doc

socket = io.listen(server)

socket.on 'connection', (client) ->
	c = {socket: client, documents:[]}
	clients.push(c)
	
	client.on 'message', (body) ->
		try
			msg = JSON.parse(body)
			switch msg.type
				when 'change'
					doc = documents[msg.docid]
					doc.handleChange(ot.deserializeChange(msg.change), c.uid)
					markDirty(doc)
				when 'join'
					getDocument msg.docid, (doc) ->
						c.uid = msg.uid
						c.documents.push(doc.id)
						doc.join(c)
					
		catch error
			sys.log("Error: #{error.msg}, #{error.stack}")
	
		
	client.on 'disconnect', ->
		for docid in c.documents
			doc = documents[docid]
			doc.leave(c)
			if not doc.clients.length
				sys.log("Document #{docid} has no users")
		clients.splice(clients.indexOf(c), 1)
		
server.listen(8123)
debug("Server started")
