ot = window.ot
otclient = window.otclient

exports = window.otui = {}
[debug, warn, error] = [window.debug, window.warn, window.error]

exports.Editor = class Editor extends otclient.Listener
	constructor: (@doc, @div, @ideallyEditable) ->
		@doc.registerListener(this)
		@div.style.whitespace = 'pre'
		@div.style.position = 'relative'	
		@caretCollapsePending = false
		
		@div.style.backgroundColor = '#ddd'
		@editable = false
		
		@div.onkeydown = (event) =>
			if not @editable then return
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
				if a >= 0 and b < @doc.length()
					@doc.spliceRange(a, b, [])
			else if event.keyCode == 13
				@spliceAtCaret([new ot.OpNewline()])
			else
				return true
			return false
						
		@div.onkeypress  = (event) =>
			if not @editable then return
			keycode = event.keyCode || event.which
			if keycode >=37 and keycode <= 40 and not event.shiftKey
				return # fix Firefox
			if keycode >= 32
				@spliceAtCaret([new ot.OpAddString(String.fromCharCode(keycode), @doc.uid)])
			return false
				
		@div.onpaste = (event) =>
			if not @editable then return
			console.log(event, event.clipboardData.getData('text/plain'))
			@spliceAtCaret([new ot.OpAddString(event.clipboardData.getData('text/plain'), @doc.uid)]) # TODO: handle pasted newlines
			return false
			
		@div.oncut = (event) =>
			if not @editable then return
			setTimeout((=> @spliceAtCaret()), 10) # delay so browser has a chance to copy text to clipboard before it gets removed
			return true
			
		@div.ot_offset = 0
			
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
	
	usersUpdated: ->
		@changeAppled()
	
	changeApplied: (change) ->
		[caret1Pos, caret2Pos] = @caretPosition()
		
		if change
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
					
					if @doc.users[i.uid]
						debug(i.uid, @doc.users)
						s.style.backgroundColor = @doc.users[i.uid].color
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
			
		try
			sel = window.getSelection()
			range = document.createRange()
			range.setStart(caret1Node, caret1Pos - caret1NodeOffs)
			range.setEnd(caret2Node, caret2Pos - caret2NodeOffs)
			sel.removeAllRanges()
			sel.addRange(range)
		catch e
			error("Error setting selection:", e) 
		
	makeEditable: ->
		@div.contentEditable = true
		@editable = true
	
	makeStatic: ->
		@div.contentEditable = false
		@editable = false
		
	connected: ->
		if @ideallyEditable
			@makeEditable()
		@div.style.backgroundColor = '#fff'
	
	disconnected: ->
		if @ideallyEditable
			@makeStatic()
		@div.style.backgroundColor = '#ddd'
		
	
		
exports.IntegrationTestListener = class IntegrationTestListener extends otclient.Listener
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
		@doc.spliceRange(Math.min(a,b), Math.min(a,b), [new ot.OpAddString(@testChar, @doc.uid)])
		
		time = Math.floor(Math.random() * 500)
		if @doc.conn.connected
			setTimeout((=> @simChanges()), time)
		
