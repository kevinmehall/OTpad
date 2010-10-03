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
					doc.applyChangeDown(ot.deserializeChange(msg.change))
					for i in clients
						i.socket.send(JSON.stringify(msg))
				when 'join'
					if not documents[msg.docid]
						doc = new ot.OTUserEndpoint(msg.docid, null, 'server')
						doc.state = new ot.Change([], msg.docid, '0', '0')
						documents[msg.docid] = doc
						sys.puts("Created document $msg.docid")
					else
						doc = documents[msg.docid]
					c.socket.send JSON.stringify {
						type: 'state'
						state: doc.state
					}
					
		catch error
			sys.puts("Error: ", error)
	
		
	client.on 'disconnect', ->
		clients.splice(clients.indexOf(c), 1)
		
server.listen(8123)
