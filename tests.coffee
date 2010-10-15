sys = require('sys')
ot = require('./operationaltransformation')

fails = 0
passes = 0

green = "\033[0;32m"
red = "\033[0;31m"
normal = "\033[m"

check = (msg, v1, v2) ->
	if v1 == v2
		sys.puts("#{green}PASS#{normal}: #{msg}")
		passes += 1
	else
		sys.puts("#{red}FAIL#{normal}: #{msg}")
		sys.puts("\tgot: #{v1}")
		sys.puts("\texp: #{v2}")
		fails += 1


v = 0
makeVersion = ->
	v++

doc = new ot.OTDocument('testdoc')

doc.setFromChange(new ot.Change([new ot.OpAddString('qwerty')], 'testdoc', '0', '1'))
check("Initial state", doc.text(), 'qwerty')

doc.applyChange(new ot.Change([new ot.OpRetain(1), new ot.OpAddString('a'), new ot.OpRemove(1), new ot.OpRetain(4)], 'testdoc', doc.version, makeVersion()))
check("Merge revision (1)", doc.text(), 'qaerty')

doc.applyChange(new ot.Change([new ot.OpRetain(3), new ot.OpAddString('NewEnd'), new ot.OpRemove(3)], 'testdoc', doc.version, makeVersion()))
check("Merge revision (2)", doc.text(), 'qaeNewEnd')

doc.applyChange(new ot.Change([new ot.OpRetain(6), new ot.OpAddString("ZZZ"), new ot.OpRetain(3)], 'testdoc', doc.version, makeVersion()))
check("Merge revision (3)", doc.text(), 'qaeNewZZZEnd')

ops = [new ot.OpRetain(3), new ot.OpRemove(1)]
c1 = new ot.Change(ops, 'testdoc', doc.version, makeVersion())
c2 = new ot.Change(ops, 'testdoc', c1.toVersion, makeVersion())
c3 = new ot.Change(ops, 'testdoc', c2.toVersion, makeVersion())
doc.applyChange(c1.merge(c2).merge(c3))
check("Merged removes", doc.text(), "qaeZZZEnd")



doc1 = new ot.OTDocument('a')
doc2 = new ot.OTDocument('a')
state = new ot.Change([new ot.OpAddString('z')], 'a', '0', '1')
doc1.setFromChange(state)
doc2.setFromChange(state)


c1 = new ot.Change([new ot.OpRetain(1), new ot.OpAddString('a')], 'a', '1', '2')
c2 = new ot.Change([new ot.OpAddString('b'), new ot.OpRetain(1), new ot.OpAddString('c')], 'a', '1', '3')

doc1.applyChange(c1)
doc2.applyChange(c2)

[a, b] = c1.transform(c2)

doc1.applyChange(a)
doc2.applyChange(b)

check("Transform (1)", doc1.text(), "bzac")
check("Transform (2)", doc2.text(), "bzac")



change = new ot.Change([new ot.OpRetain(5), new ot.OpAddString('12'), new ot.OpRetain(3), new ot.OpAddString('a'), new ot.OpRetain(5)])
check("OffsetPoint (0)", change.offsetPoint(0), 0)
check("OffsetPoint (5)", change.offsetPoint(5), 7)
check("OffsetPoint (9)", change.offsetPoint(9), 12)

c = if fails then red else green
sys.puts("#{c}DONE#{normal}: #{passes} passed, #{fails} failed")
