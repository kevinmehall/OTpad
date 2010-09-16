

class Operation


class OpRetain extends Operation
	constructor: (count) ->
		if count == 0
			throw new Exception("Useless retain")
		@type: 'retain'
		@inserts: count
		@removes: 0
		
	length: -> @inserts
		
	split: (offset) ->
		if offset >= @length()
			[this, false]
		else if offset == 0
			[false, this]
		else
			[new OpRetain(offset), new OpRetain(@inserts-offset)]
		
	merged: -> false

class OpAdd extends Operation
	constructor: (addString) ->
		@type: 'add'
		@inserts: addString.length
		@removes: 0
		@addString: addString
		
	length: -> @inserts
		
	merged: ->
		return new OpAdd(@addString)
		
	split: (offset) ->
		return [new OpAdd(@addString.slice(0, offset)), new OpAdd(@addString.slice(offset))] 
		
class OpRemove extends Operation
	constructor: (n) ->
		@type: 'remove'
		@inserts: 0
		@removes: n
		
	length: -> removes
	
	merged: -> false
	
	split: (offset) ->
		if offset >= @length()
			[this, false]
		else if offset == 0
			[false, this]
		else
			[new OpRemove(offset), new OpRemove(@inserts-offset)]

type: (o) ->
	if o
		return o.type
	else
		return false
	
split: (first, second) ->
	sys.puts("splitting ${sys.inspect(first)} against ${sys.inspect(second)}")
	if first.type == 'add'
		return [
			[first,false],
			[false,second]
		]
	else if second.type == 'add'
		return [
			[false,first],
			[second,false]
		]
	else
		return [
			first.split(second.length())
			second.split(first.length())
		]
		
transform: (first, second) ->
	sys.puts("transforming ${sys.inspect(first)} against ${sys.inspect(second)}")
	if type(first) == 'add'
		return [first, new OpRetain(first.length())]
	
	if type(second) == 'add'
		return [new OpRetain(second.length()), second]
		
	if type(first) == 'retain' and type(second) == 'retain'
		return [first, second]
		
	if type(first) == 'remove' and type(second) == 'remove'
		return [false, false]
		
	if type(first) == 'remove' and type(second) == 'retain'
		return [first, false]
		
	if type(first) == 'retain' and type(second) == 'remove'
		return [false, second]
		
	return [false, false]
				
	

class Change
	constructor: (operations) ->
		@operations: operations

	transform: (other) ->
		a = i for i in @operations
		b = i for i in other.operations
		aprime = []
		bprime = []
		
		aop = false
		bop = false
		
		while a.length and b.length
			if not aop
				aop = a.shift()
			if not bop
				bop = b.shift()
				
			parts = split(aop, bop)
			sys.puts("parts: ${sys.inspect(parts)}")
			
			aop = parts[0][1]
			bop = parts[1][1]
			
			transformed = transform(parts[0][0], parts[1][0])
			
			if transformed[0]
				aprime.push(transformed[0])
			
			if transformed[1]
				bprime.push(transformed[1])
				
		while a.length
			if not aop
				aop = a.shift()
			aprime.push(aop)
			aop = false
			
		while b.length
			if not bop
				bop = b.shift()
			bprime.push(bop)
			bop = false
		
		return [new Change(aprime), new Change(bprime)]
			
		

	merge: (other) ->
		sys.puts("merge ${sys.inspect(this)}, ${sys.inspect(other)}")
		outops = []
		baseops = op for op in @operations
		
		go: (offset, output) ->
			i = 0
			while i<offset
				op = baseops.shift()
				sys.puts("popped ${sys.inspect(op)}")
				i += op.inserts-op.removes
				outops.push(op) if output
			if i>offset
				outops.pop() if output
				i -= op.inserts - op.removes
				[a, b] = op.split(offset-i)
				sys.puts("split, ${offset-i}, ${sys.inspect a} ${sys.inspect b}")
				outops.push(a) if output
				baseops.unshift(b)
		
		for operation in other.operations
			if operation.type == 'retain'
				go(operation.inserts, yes)
			else
				m: operation.merged()
				outops.push(m) if m
				go(operation.removes, no)
				
		return new Change(outops)
				
			
class Document
	applyChange: (change) ->
		@state = @state.merge(change)
		
	setText: (text) -> 
		@state = new Change([new OpAdd(text)])
		
	getText: ->
		(i.addString for i in @state.operations).join('')
		
	normalize: ->
		@setText(@getText())
			
			
sys: require('sys')
doc: new Document()
doc.setText('qwerty')
doc.applyChange(new Change([new OpRetain(1), new OpAdd('a'), new OpRemove(1), new OpRetain(4)]))
sys.puts("text: '${doc.getText()}'")
doc.applyChange(new Change([new OpRetain(3), new OpAdd('NewEnd'), new OpRemove(3)]))
doc.applyChange(new Change([new OpRetain(6), new OpAdd("ZZZ"), new OpRetain(3)]))
sys.puts(sys.inspect(doc.state))
sys.puts("text: '${doc.getText()}'")

c1: new Change([new OpRetain(1), new OpAdd('a')])
c2: new Change([new OpAdd('b'), new OpRetain(1), new OpAdd('z')])

[a, b] = c1.transform(c2)
sys.puts(sys.inspect([a.operations, b.operations]))


