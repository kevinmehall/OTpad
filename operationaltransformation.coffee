
if window?
	exports = window
else
	exports = module.exports = {}

warn: (msg) ->
	if console
		console.warning(msg)

class Operation

class OpRetain extends Operation
	constructor: (count) ->
		if count == 0
			warn("Useless retain")
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
		
class OpNewline extends Operation
	constructor: ->
		@type: 'newline'
		@inserts: 1
		@removes: 0
		
	length: -> @inserts
	merged: -> this
	split: -> [false, this]
	
		
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
			
class OpAddCaret extends Operation
	constructor: (uid) ->
		@uid = uid
		@inserts: 1
		@removes: 0
		@type = 'caret'
		
	length: -> 1
	merged: -> this
	split: -> [false, this]
	
opMap: {
	'add': OpAdd
	'caret': OpAddCaret
	'remove': OpRemove
	'retain': OpRetain
	'newline': OpNewline
}

type: (o) ->
	if o
		return o.type
	else
		return false
	
split: (first, second) ->
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
	if type(first) == 'add' or type(first) == 'caret' or type(first) == 'newline'
		return [first, new OpRetain(first.length())]
	
	if type(second) == 'add' or type(second) == 'caret' or type(second) == 'newline'
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
	constructor: (operations, docid, fromVersion, toVersion) ->
		@operations: operations
		@fromVersion: fromVersion
		@toVersion: toVersion
		@docid: docid

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
		
		return [new Change(aprime, @docid, @toVersion, ), new Change(bprime, @docid, other.toVersion, )]
			
		

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
				
		return new Change(outops, @docid, @fromVersion, other.toVersion)

exports.deserializeChange: (c)->
	c.__proto__ = Change.prototype
	for i in c.operations
		i.__proto__ = opMap[i.type].prototype
	return c

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
	constructor: (id, conn, uid) ->
		@id: id
		@uid: uid
		@version: '0'
		@versionHistory: {}
		@conn = conn
		
		if @conn
			@conn.register(this)
		
	applyChange: (change) ->
		if change.docid? and change.docid != @id
			throw new Error("Tried to merge against wrong document")
		if change.toVersion == @version
			return
		if change.fromVersion != @version
			throw new Error("Tried to merge out of order (at $@version, revision from $change.fromVersion to $change.toVersion)")
		@setFromChange(@state.merge(change))
		
	setFromChange: (state) ->
		first = not @state?
		@state = state
		@version = state.toVersion
		@versionHistory[@version] = state
		@update()
		if first
			#initial load
			@applyChangeUp(new Change([new OpAddCaret(@uid),new OpRetain(@length())], @id, @version, @makeVersion()))

	text: () ->
		((if i.addString then i.addString else '') for i in @state.operations).join('')
		
	applyChangeUp: (change) ->
		@applyChange(change)
		if @conn
			@conn.send(change)
		
	applyChangeDown: (change) ->
		@applyChange(change)
		
	makeVersion: ->
		''+(parseInt(@version, 10) + 1)
		
	findMyCaret: ->
		offset = 0
		for i in @state.operations
			if i.type == 'caret' and i.uid == @uid
				return offset
			else
				offset += i.inserts
	
	length: ->
		offset = 0
		for i in @state.operations
			offset += i.inserts
		return offset
	
	spliceAtCaret: (remove, add) ->
		offset = @findMyCaret()
		
		l = [new OpRetain(offset-remove)]
		if remove
			l.push(new OpRemove(remove))
		if add
			if add == '\r'
				l.push(new OpNewline())
			else
				l.push(new OpAdd(add))		
		l.push(new OpRetain(@length() - offset))
				
		change = new Change(l, @id, @version, @makeVersion())
		
		@applyChangeUp(change)
		
	moveCaretTo: (newpos) ->
		pos = @findMyCaret()
		
		l = []
		
		if newpos < pos
			l.push(new OpRetain(newpos))
			l.push(new OpAddCaret(@uid))
			l.push(new OpRetain(pos-newpos))
			l.push(new OpRemove(1))
			l.push(new OpRetain(@length() - pos))
		else
			l.push(new OpRetain(pos))
			l.push(new OpRemove(1))
			l.push(new OpRetain(newpos - pos))
			l.push(new OpAddCaret(@uid))
			l.push(new OpRetain(@length() - newpos))
			
		change = new Change(l, @id, @version, @makeVersion())
		@applyChangeUp(change)
		
	moveCaretBy: (offset) ->
		pos = @findMyCaret()+offset
		if pos < 0
			pos = 0
		l = @length()
		if pos>l
			pos = l
		@moveCaretTo(pos)
		
	update: () -> false
		
		
			

exports.OpRetain = OpRetain
exports.OpAdd = OpAdd
exports.OpAddCaret = OpAddCaret
exports.OpRemove = OpRemove
exports.Document = Document
exports.Change = Change
exports.DummyConn = DummyConn

