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
			
		@socket.on 'message', (body) =>
			msg = JSON.parse(body)
			switch msg.type
				when 'change'
					@send(msg.change, yes)
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
		@div.contentEditable = true			
		
		@div.onkeydown = (event) =>
			if event.keyCode == 8 # backspace
				[a,b] = @caretPosition()
				if a == b
					a-=1
				if a >= 0
					@spliceRange(a, b, [])
			else if event.keyCode == 13
				@spliceAtCaret([new OpNewline()])
			else
				return true
			return false
				
		
		@div.onkeypress  = (event) =>
			keycode = event.keyCode || event.which
			if keycode >=37 and keycode <= 40 and not event.shiftKey
				return # fix Firefox
			if keycode >= 32
				@spliceAtCaret([new OpAddString(String.fromCharCode(keycode))])
			return false
				
		@div.onpaste = (event) =>
			console.log(event, event.clipboardData.getData('text/plain'))
			@spliceAtCaret([new OpAddString(event.clipboardData.getData('text/plain'))]) # TODO: handle pasted newlines
			@div.focus()
			
		@div.onbeforepaste = (event) =>
			console.log("obp", event)
			
		@update(@state)
			
	caretPosition: ->
		sel = window.getSelection()
		a = @posFromNodeOffset(sel.focusNode, sel.focusOffset)
		b = @posFromNodeOffset(sel.anchorNode, sel.anchorOffset)
		console.log('cursor is', a, b)
		[Math.min(a,b), Math.max(a,b)]
			
	posFromNodeOffset: (node, offset) ->
		if node
			ot_offset = node.ot_offset ? node.parentNode.ot_offset
			return ot_offset + offset
		else
			return undefined
		
	spliceAtCaret: (add) ->
		[a,b] = @caretPosition()
		@spliceRange(a, b, add)
				
	focus: =>
		@div.focus()
		
		
	applyChange: (change) ->
		if super(change)
			@update(change)
		
		
	update: (change) ->
		[caret1Pos, caret2Pos] = @caretPosition()
		caret1Pos = change.offsetPoint(caret1Pos)
		caret2Pos = change.offsetPoint(caret2Pos)
		
		div = @div
		div.innerHTML = ''
		div.ot_offset = 0
		offset = 0
				
		lineDiv = document.createElement('div')
		div.appendChild(lineDiv)
		lineDiv.ot_offset = 0
		
		caret1Node = lineDiv
		caret1NodeOffs = 0
		caret2Node = lineDiv
		caret2NodeOffs = 0

		for i in @state.operations
			switch i.type
				when 'str'
					s = document.createElement('span')
					d = document.createTextNode(i.addString)
					s.ot_offset=offset
					s.appendChild(d)
					lineDiv.appendChild(s)
					if offset<=caret1Pos
						caret1Node = d
						caret1NodeOffs = offset
					if offset<=caret2Pos
						caret2Node = d
						caret2NodeOffs = offset	
				when 'newline'
					lineDiv = document.createElement('div')
					div.appendChild(lineDiv)
					lineDiv.ot_offset = offset+1 # because an inserted node should go after the newline
					if offset<caret1Pos
						caret1Node = lineDiv
						caret1NodeOffs = offset+1
					if offset<caret2Pos
						caret2Node = lineDiv
						caret2NodeOffs = offset+1
			offset+=i.length()
			
		sel = window.getSelection()
		range = document.createRange()
		console.log(caret1Node, caret1Pos - caret1NodeOffs)
		range.setStart(caret1Node, caret1Pos - caret1NodeOffs)
		range.setEnd(caret2Node, caret2Pos - caret2NodeOffs)
		sel.removeAllRanges()
		sel.addRange(range)
