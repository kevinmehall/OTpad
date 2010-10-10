if console?
	window.log = (a...) -> console.log(a...)
	window.error = (a...) -> console.error(a...)
	window.warn = (a...) -> console.warn(a...)
	window.debug = (a...) -> console.debug(a...)
else
	window.log = window.error = window.warn = debug = ->
