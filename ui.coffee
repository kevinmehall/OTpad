window.bespinPositionToCharOffset: (str, position) ->
	lines = str.split('\n')
	
	chars = 0
	for i in lines.slice(0, position.row)
		chars += i.length + 1

	return chars+position.col
	
window.bespinRangeToOffsetLength: (str, range) ->
	start = bespinPositionToCharOffset(str, range.start)
	end = bespinPositionToCharOffset(str, range.end)
	return [start, end-start]
	
window.charOffsetToBespinPosition: (editor, offset) ->
	lines = editor.value.split('\n')
	
	chars = offset
	line = 0
	for i in lines
		if chars <= i.length
			return {row: line, col: chars}
		chars -= i.length + 1
		line += 1
		
window.offsetLengthToBespinRange: (editor, offset, length) ->
	return {
		start: charOffsetToBespinPosition(editor, offset)
		end: charOffsetToBespinPosition(editor, offset+length)
	}
	
window.onBespinLoad: ->
	
	window.editor = document.getElementById("editor").bespin.editor
	
	editor.prevtext = editor.value
	
	editor.textChanged.add (oldRange, newRange, newValue)->
		[offset, remove] = bespinRangeToOffsetLength(editor.prevtext, oldRange)
		
		editor.prevtext = editor.value
		
		l = [new OpRetain(offset)]
		
		if remove
			l.push(new OpRemove(remove))
			
		if newValue
			l.push(new OpAdd(newValue))
		
		console.log(l)
		
		return undefined
