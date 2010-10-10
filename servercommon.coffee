sys = require('sys')

green = "\033[0;32m"
red = "\033[0;31m"
yellow = "\033[0;33m"
blue = "\033[0;34m"
normal = "\033[m"


log = (level, color, args...) ->
	a = for i in args
		if typeof i == 'string' then i else sys.inspect(i)
	a = a.join('')
	
	sys.log("#{color}#{level}#{normal}: #{a}")
	
exports = module.exports = {}
exports.error = (args...) -> log("ERROR", red, args...)
exports.warn = (args...) ->  log("WARNING", yellow, args...)
exports.debug = (args...) -> log("DEBUG", blue, args...)
