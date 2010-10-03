sys: require('sys')
ot: require('./operationaltransformation')

fails = 0
passes = 0

green = "\033[0;32m"
red = "\033[0;31m"
normal = "\033[m"

check: (msg, v1, v2) ->
	if v1 == v2
		sys.puts("${green}PASS${normal}: $msg")
		passes += 1
	else
		sys.puts("${red}FAIL${normal}: $msg")
		sys.puts("\tgot: $v1")
		sys.puts("\texp: $v2")
		fails += 1

doc: new ot.Document('testdoc', false, 'tester')

doc.setFromChange(new ot.Change([new ot.OpAdd('qwerty')], 'testdoc', '0', '1'))
check("Initial state", doc.text(), 'qwerty')

doc.applyChangeDown(new ot.Change([new ot.OpRetain(2), new ot.OpAdd('a'), new ot.OpRemove(1), new ot.OpRetain(4)], 'testdoc', doc.version, doc.makeVersion()))
check("Merge revision (1)", doc.text(), 'qaerty')

doc.applyChange(new ot.Change([new ot.OpRetain(4), new ot.OpAdd('NewEnd'), new ot.OpRemove(3)], 'testdoc', doc.version, doc.makeVersion()))
check("Merge revision (2)", doc.text(), 'qaeNewEnd')

doc.applyChange(new ot.Change([new ot.OpRetain(7), new ot.OpAdd("ZZZ"), new ot.OpRetain(3)], 'testdoc', doc.version, doc.makeVersion))
check("Merge revision (3)", doc.text(), 'qaeNewZZZEnd')

c1: new ot.Change([new ot.OpRetain(1), new ot.OpAdd('a')], 'testdoc', 4, 5)
c2: new ot.Change([new ot.OpAdd('b'), new ot.OpRetain(1), new ot.OpAdd('z')], 'testdoc', 5, 6)

[a, b] = c1.transform(c2)
#sys.puts(sys.inspect([a.operations, b.operations]))

c = if fails then red else green
sys.puts("${c}DONE${normal}: $passes passed, $fails failed")
