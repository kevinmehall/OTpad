window.onload: ->
	window.editor = document.getElementById("editor")
	
	myid = '' + Math.floor(Math.random()*1000000)
	
	window.conn = new SocketConn()
	window.doc = new EditorDocument('testdoc', conn, myid, editor)

class SocketConn
	constructor: ->
		@socket = new io.Socket(null, {port: 8123})
		@socket.connect()
		@socket.on 'connect', =>
			console.log('connect')
			
		@socket.on 'message', (body) =>
			msg = JSON.parse(body)
			switch msg.type
				when 'change'
					@send(msg.change, yes)
				when 'state'
					console.log('received state')
					for doc in @documents
						doc.setFromChange(deserializeChange(msg.state))
				else
					console.log("error", msg)
			
		@socket.on 'disconnect', =>
			console.log('disconnect')
			
		@documents = []
		
	register: (doc) ->
		@documents.push(doc)
		@socket.send JSON.stringify {
			type: 'join'
			docid: doc.id
			uid: doc.uid
		}
		
	send: (change, fromserver) ->
		if not fromserver
			@socket.send JSON.stringify {
				docid: change.docid
				type: 'change'
				change: change
			}
		
		for doc in @documents
			doc.applyChangeDown(deserializeChange(change))
	
	
class EditorDocument extends Document
	constructor: (id, conn, uid, div) ->
		super(id, conn, uid)
		@div = div
		@div.style.whitespace = 'pre'
		@div.style.position = 'relative'
		@div.setAttribute('tabindex', 0)
		
		@div.onclick = @focus
		
		@div.onkeyup = (event) =>
			if event.keyCode == 8
				@spliceAtCaret(1, '')
			else if event.keyCode == 37
				@moveCaretBy(-1)
			else if event.keyCode == 39
				@moveCaretBy(1)
			else
				return true
			event.preventDefault()
			
		
		@div.onkeypress  = (event) =>
			keycode = event.keyCode || event.which
			if keycode >= 32 or keycode==13
				@spliceAtCaret(0, String.fromCharCode(keycode))
		
	focus: =>
		@div.focus()
		
		
	applyChange: (change) ->
		super(change)
		@update()
		
		
	update: ->
		div = @div
		div.innerHTML = ''
		
		mkSpan: (text) ->
			s = document.createElement('span')
			s.style.whiteSpace = 'pre'
			d = document.createTextNode(text)
			s.appendChild(d)
			div.appendChild(s)
			
		mkBr:  ->
			s = document.createElement('br')
			div.appendChild(s)
		
		mkCaret: (uid) =>
			caret = document.createElement('span')
			if uid == @uid
				caret.setAttribute('class', 'mycaret')
			else
				caret.setAttribute('class', 'caret')
			div.appendChild(caret)
			
		for i in @state.operations
			switch i.type
				when 'add'
					mkSpan(i.addString)	
				when 'caret'
					mkCaret(i.uid)
				when 'newline'
					mkBr()
			
