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
			if event.keyCode == 8
				@spliceAtCaret(1, '')
		
		@div.onkeypress  = (event) =>
			keycode = event.keyCode || event.which
			if keycode >=37 and keycode <= 40 and not event.shiftKey
				return # fix Firefox
			if keycode >= 32 or keycode==13
				@spliceAtCaret(0, String.fromCharCode(keycode))
			return false
				
		@div.onpaste = (event) =>
			console.log(event, event.clipboardData.getData('text/plain'))
			@spliceAtCaret(0, event.clipboardData.getData('text/plain'))
			@div.focus()
			
		@div.onbeforepaste = (event) =>
			console.log("obp", event)
			
		@update(@state)
			
	caretPosition: ->
		sel = window.getSelection()
		if sel.focusNode
			ot_offset = sel.focusNode.ot_offset ? sel.focusNode.parentNode.ot_offset
			console.log("cursor is in", sel.focusNode, sel.focusNode.ot_offset, ot_offset)
			return ot_offset + sel.focusOffset
		else
			return undefined
		
	spliceAtCaret: (remove, add) ->
		@splice(@caretPosition(), remove, add)
				
	focus: =>
		@div.focus()
		
		
	applyChange: (change) ->
		if super(change)
			@update(change)
		
		
	update: (change) ->
		oldCaretPos = @caretPosition() || 0
		caretPos = change.offsetPoint(oldCaretPos)
		div = @div
		div.innerHTML = ''
		div.ot_offset = 0
		offset = 0
				
		lineDiv = document.createElement('div')
		div.appendChild(lineDiv)
		caretNode = lineDiv
		caretNodeOffs = 0
		lineDiv.ot_offset = 0
		
		
		for i in @state.operations
			switch i.type
				when 'str'
					s = document.createElement('span')
					d = document.createTextNode(i.addString)
					s.ot_offset=offset
					s.appendChild(d)
					lineDiv.appendChild(s)
					if offset<=caretPos
						caretNode = d
						caretNodeOffs = offset
				when 'newline'
					lineDiv = document.createElement('div')
					div.appendChild(lineDiv)
					lineDiv.ot_offset = offset+1 # because an inserted node should go after the newline
					if offset<caretPos
						caretNode = lineDiv
						caretNodeOffs = offset + 1 # to counteract above
					
			
			offset+=i.length()
			
		
		sel = window.getSelection()
		range = document.createRange()
		range.setStart(caretNode, caretPos - caretNodeOffs)
		range.setEnd(caretNode, caretPos - caretNodeOffs)
		#sel.removeAllRanges()
		sel.addRange(range)
