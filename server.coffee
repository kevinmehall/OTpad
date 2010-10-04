http:	require('http')
io: 	require('./socket.io')
sys:	require('sys')
fs:		require('fs')
url:	require('url')
ot:		require('./operationaltransformation')

server = http.createServer (req, res) ->
	path = url.parse(req.url).pathname
	
	if path.indexOf('.js') == -1
		sys.log("loading page $path")
		path = '/index.html'
		
	
	fs.readFile __dirname + path, (err, data) ->
		if (err)
			sys.log(err)
			res.writeHead(404)
			res.write("404")
			res.end()
		else
			ctype = 'text/javascript'
			if path.indexOf('.js')!=1
				ctype = 'text/html'
			res.writeHead(200, {'Content-Type': ctype})
			res.write(data, 'utf8');
			res.end();


  
clients = []
documents = {}

getDocument: (docid) ->
	if not documents[docid]
		doc = new ot.OTServerEndpoint(docid, null, 'server')
		documents[docid] = doc
		sys.puts("Created document $docid")
	else
		doc = documents[docid]
	return doc

socket = io.listen(server)
 
socket.on 'connection', (client) -> 
	sys.puts('connected')
	
	c = {socket: client}
	clients.push(c)
	
	client.on 'message', (body) ->
		sys.puts(">$body<")
		try
			msg = JSON.parse(body)
			switch msg.type
				when 'change'
					doc = documents[msg.docid]
					doc.handleChange(ot.deserializeChange(msg.change))
				when 'join'
					doc = getDocument(msg.docid)
					c.uid = msg.uid
					c.document = doc
					doc.join(c)
					
		catch error
			sys.puts("Error: ", error.message, error.stack)
	
		
	client.on 'disconnect', ->
		if c.document?
			c.document.leave(c)
		clients.splice(clients.indexOf(c), 1)
		
server.listen(8123)
