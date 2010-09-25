window.onload: ->
	window.editor = document.getElementById("editor")
	window.editor2 = document.getElementById("editor2")
	
	state = new Change([new OpAddCaret('1'), new OpAddCaret('2')], '0', '0')
	window.conn = new DummyConn()
	window.doc = new EditorDocument('testdoc', conn, '1', state, editor)
	window.doc2 = new EditorDocument('testdoc', conn, '2', state, editor2)
	
	
class EditorDocument extends Document
	constructor: (id, conn, uid, state, div) ->
		super(id, conn, uid, state)
		@div = div
		@div.style.whitespace = 'pre'
		@div.style.position = 'relative'
		@div.setAttribute('tabindex', 0)
				
		@update()
		
		@div.onclick = @focus
		
		@div.onkeyup = (event) =>
			if event.keyCode == 8
				@spliceAtCaret(1, '')
			else if event.keyCode == 37
				@moveCaretBy(-1)
			else if event.keyCode == 39
				@moveCaretBy(1)
		
		@div.onkeypress  = (event) =>
				@spliceAtCaret(0, String.fromCharCode(event.keyCode))
		
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
			s.innerText = text
			div.appendChild(s)
		
		mkCaret: (uid) ->
			caret = document.createElement('span')
			caret.setAttribute('class', 'caret')
			div.appendChild(caret)
			
		for i in @state.operations
			if i.type == 'add'
				mkSpan(i.addString)	
			else if i.type == 'caret'
				mkCaret(i.uid)
			
