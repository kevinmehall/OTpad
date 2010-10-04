window.onload: ->
	window.editor = document.getElementById("editor")
	
	myid = '' + Math.floor(Math.random()*1000000)
	
	window.conn = new SocketConn()
	window.doc = new EditorDocument(document.location.pathname, conn, myid, editor)

class SocketConn
	constructor: ->
		@connected = false
		
		@socket = new io.Socket(null, {port: 8123})
		@socket.connect()
		@socket.on 'connect', =>
			@connected = true
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
			@connected = false
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
	
	
class EditorDocument extends OTUserEndpoint
	constructor: (id, conn, uid, div) ->
		super(id, conn, uid)
		@div = div
		@div.style.whitespace = 'pre'
		@div.style.position = 'relative'
		@div.setAttribute('tabindex', 0)
		
		@div.onclick: (e) =>
			@focus()
			if e.target.nodeName.toLowerCase() == 'span'
				charWidth=e.target.offsetWidth/e.target.innerHTML.length
				x = e.offsetX - e.target.offsetLeft
				pos = Math.round(x/charWidth) + e.target.ot_offset
				if pos > @findMyCaret()
					pos -= 1
				@moveCaretTo( pos )
			
		
		@div.onkeydown = (event) =>
			if event.keyCode == 8
				@spliceAtCaret(1, '')
			else if event.keyCode == 37
				@moveCaretBy(-1)
			else if event.keyCode == 39
				@moveCaretBy(1)

		
		@div.onkeypress  = (event) =>
			keycode = event.keyCode || event.which
			if keycode >=37 and keycode <= 40 and not event.shiftKey
				return # fix Firefox
			if keycode >= 32 or keycode==13
				@spliceAtCaret(0, String.fromCharCode(keycode))
				
		@div.onpaste = (event) =>
			console.log(event, event.clipboardData.getData('text/plain'))
			@spliceAtCaret(0, event.clipboardData.getData('text/plain'))
				
		
	focus: =>
		@div.focus()
		
		
	applyChange: (change) ->
		super(change)
		@update()
		
		
	update: ->
		div = @div
		div.innerHTML = ''
		offset = 0
		
		mkSpan: (text) ->
			s = document.createElement('span')
			s.style.whiteSpace = 'pre'
			d = document.createTextNode(text)
			s.ot_offset=offset
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
				when 'str'
					mkSpan(i.addString)	
				when 'caret'
					mkCaret(i.uid)
				when 'newline'
					mkBr()
			offset+=i.length()
			
