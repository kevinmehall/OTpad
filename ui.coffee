ot = window.ot
otclient = window.otclient

window.onload =  ->
	myid = '' + Math.floor(Math.random()*1000000)
	
	window.conn = new SocketConn()
	window.doc = new otclient.OTClientDocument(document.location.pathname, conn, myid)
	window.editor = new Editor(document.getElementById("editor"), doc)
	window.itest = new IntegrationTestListener(doc)

class SocketConn
	constructor: ->
		@connected = false
		@socket = new io.Socket(null, {port: 8123})
		@socket.connect()
		@document = false
		
		@socket.on 'connect', =>
			@connected = true
			
		@socket.on 'message', (body) =>
			msg = JSON.parse(body)
			switch msg.type
				when 'change'
					@document.applyChangeDown(ot.deserializeChange(msg.change), msg.acknowlege)
				else
					console.log("error", msg)
			
		@socket.on 'disconnect', =>
			@connected = false
			console.log('disconnect')
		
	register: (doc) ->
		@document = doc
		@socket.send JSON.stringify
			type: 'join'
			docid: @document.id
			uid: @document.uid
			
	send: (change) ->
		@socket.send JSON.stringify
			docid: change.docid
			type: 'change'
			change: change
	
	
class Editor extends otclient.Listener
	constructor: (@div, @doc) ->
		@doc.registerListener(this)
		@div.style.whitespace = 'pre'
		@div.style.position = 'relative'
		@div.setAttribute('tabindex', 0)
		@div.contentEditable = true			
		@caretCollapsePending = false
		
		@div.onkeydown = (event) =>
			if event.keyCode == 8 # backspace
				[a,b] = @caretPosition()
				if a == b
					a-=1
				if a >= 0
					@doc.spliceRange(a, b, [])
			else if event.keyCode == 46 #delete
				[a,b] = @caretPosition()
				if a == b
					b+=1
				if a >= 0 and b < @length()
					@doc.spliceRange(a, b, [])
			else if event.keyCode == 13
				@spliceAtCaret([new ot.OpNewline()])
			else
				return true
			return false
				
		
		@div.onkeypress  = (event) =>
			keycode = event.keyCode || event.which
			if keycode >=37 and keycode <= 40 and not event.shiftKey
				return # fix Firefox
			if keycode >= 32
				@spliceAtCaret([new ot.OpAddString(String.fromCharCode(keycode))])
			return false
				
		@div.onpaste = (event) =>
			console.log(event, event.clipboardData.getData('text/plain'))
			@spliceAtCaret([new ot.OpAddString(event.clipboardData.getData('text/plain'))]) # TODO: handle pasted newlines
			return false
			
		@div.oncut = (event) =>
			setTimeout((=> @spliceAtCaret()), 10) # delay so browser has a chance to copy text to clipboard before it gets removed
			return true
			
		@changeApplied(@doc.state)
			
	caretPosition: ->
		sel = window.getSelection()
		a = @posFromNodeOffset(sel.focusNode, sel.focusOffset)
		b = @posFromNodeOffset(sel.anchorNode, sel.anchorOffset)
		[Math.min(a,b), Math.max(a,b)]
			
	posFromNodeOffset: (node, offset) ->
		if node
			ot_offset = node.ot_offset ? node.parentNode.ot_offset
			return ot_offset + offset
		else
			return undefined
		
	spliceAtCaret: (add) ->
		[a,b] = @caretPosition()
		@doc.spliceRange(a, b, add)
		@caretCollapsePending = true
				
	focus: =>
		@div.focus()
		
	changeApplied: (change) ->
		[caret1Pos, caret2Pos] = @caretPosition()
		caret1Pos = change.offsetPoint(caret1Pos)
		caret2Pos = change.offsetPoint(caret2Pos)
		
		if @caretCollapsePending
			@caretCollapsePending = false
			caret1Pos = caret2Pos
			
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

		for i in @doc.state.operations
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
		range.setStart(caret1Node, caret1Pos - caret1NodeOffs)
		range.setEnd(caret2Node, caret2Pos - caret2NodeOffs)
		sel.removeAllRanges()
		sel.addRange(range)
		
class IntegrationTestListener extends otclient.Listener
	constructor: (@doc) ->
		@doc.registerListener(this)
	
	changeApplied: (change) ->
		msg = JSON.stringify
			type: 'verify'
			fromVersion: change.fromVersion
			toVersion: change.toVersion
			uid: @doc.uid
			hash: hex_md5(@doc.text())
		@doc.conn.socket.send(msg)
		
	simChanges: ->
		if not @testChar
			@testChar = ['.', '#', 'a', 'b', 'c', 'x', 'w', 'r'][Math.floor(Math.random() * 8)]
		a = Math.floor(Math.random() * @doc.length())
		b = Math.floor(Math.random() * @doc.length())
		@doc.spliceRange(Math.min(a,b), Math.max(a,b), [new ot.OpAddString(@testChar)])
		
		time = Math.floor(Math.random() * 500)
		setTimeout((=> @simChanges()), time)
		
