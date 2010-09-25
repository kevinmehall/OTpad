
exports = window if window?

class Operation


class OpRetain extends Operation
	constructor: (count) ->
#		if count == 0
#			throw new Exception("Useless retain")
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
	#sys.puts("splitting ${sys.inspect(first)} against ${sys.inspect(second)}")
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
	#sys.puts("transforming ${sys.inspect(first)} against ${sys.inspect(second)}")
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
	constructor: (operations, fromVersion, toVersion) ->
		@operations: operations
		@fromVersion: fromVersion
		@toVersion: toVersion

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
			#sys.puts("parts: ${sys.inspect(parts)}")
			
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
		
		return [new Change(aprime, @toVersion, ), new Change(bprime, other.toVersion, )]
			
		

	merge: (other) ->
		outops = []
		baseops = op for op in @operations
		
		go: (offset, output) ->
			i = 0
			while i<offset and baseops.length
				op = baseops.shift()
				#sys.puts("popped ${sys.inspect(op)}")
				i += op.inserts-op.removes
				outops.push(op) if output
			if i>offset
				outops.pop() if output
				i -= op.inserts - op.removes
				[a, b] = op.split(offset-i)
				#sys.puts("split, ${offset-i}, ${sys.inspect a} ${sys.inspect b}")
				outops.push(a) if output
				baseops.unshift(b)
		
		for operation in other.operations
			if operation.type == 'retain'
				go(operation.inserts, yes)
			else
				m: operation.merged()
				outops.push(m) if m
				go(operation.removes, no)
				
		return new Change(outops, @fromVersion, other.toVersion)

class DummyConn
	constructor: ->
		@documents = []
		
	register: (doc) ->
		@documents.push(doc)
		
	send: (change) ->
		console.log('send', change)
		for doc in @documents
			doc.applyChangeDown(change)
		
				
			
class Document
	constructor: (id, conn) ->
		@id: id
		@text: ''
		@version: '0'
		@versionHistory: {}
		@conn = conn
		@conn.register(this)
		
	applyChange: (change) ->
		if change.docid? and change.docid != @id
			throw new Error("Tried to merge against wrong document")
		if change.toVersion == @version
			return
		if change.fromVersion != @version
			throw new Error("Tried to merge out of order")
		@setFromChange(@state().merge(change))
		
	state: -> 
		new Change([new OpAdd(@text)], '0', @version)
		
	setFromChange: (state) ->
		@text = (i.addString for i in state.operations).join('')
		@version = state.toVersion
		@versionHistory[@version] = state
		
	applyChangeUp: (change) ->
		@applyChange(change)
		@conn.send(change)
		console.log(@text)
		
	applyChangeDown: (change) ->
		console.log 'applychangedown', change, @version
		@applyChange(change)
		
	makeVersion: ->
		parseInt(@version, 10) + 1
		
		
			

exports.OpRetain = OpRetain
exports.OpAdd = OpAdd
exports.OpRemove = OpRemove
exports.Document = Document
exports.Change = Change
exports.DummyConn = DummyConn

