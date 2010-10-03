
if window?
	exports = window
else
	exports = module.exports = {}

warn: (msg) ->
	true
	#if console
	#	console.warning(msg)

class Operation
	isAdd: -> undefined

class OpRetain extends Operation
	constructor: (count) ->
		if count == 0
			warn("Useless retain")
		@type: 'retain'
		@count: count
		
	length: -> @count
	cursorDelta: -> @count
		
	split: (offset) ->
		if offset >= @count
			[this, false]
		else if offset == 0
			[false, this]
		else
			[new OpRetain(offset), new OpRetain(@count-offset)]
		
	merged: -> false

class OpAdd extends Operation
	isAdd: -> true
	merged: -> return this

class OpAddString extends OpAdd
	constructor: (addString) ->
		@type: 'str'
		@addString: addString
		
	length: -> @addString.length
	cursorDelta: -> @addString.length
		
	split: (offset) ->
		a = @addString.slice(0, offset)
		b = @addString.slice(offset)
		a = if a then new OpAddString(a) else false
		b = if b then new OpAddString(b) else false
		return [a, b]
		
class OpNewline extends OpAdd
	constructor: ->
		@type: 'newline'
		@addString = '\n'
		
	length: -> 1
	cursorDelta: -> 1
	merged: -> this
	split: -> [false, this]
	
		
class OpRemove extends Operation
	constructor: (n) ->
		@type: 'remove'
		@removes: n
		
	length: -> @removes
	cursorDelta: -> -1*@removes
	
	merged: -> false
	
	split: (offset) ->
		if offset >= @length()
			[this, false]
		else if offset == 0
			[false, this]
		else
			[new OpRemove(offset), new OpRemove(@inserts-offset)]
			
class OpAddCaret extends OpAdd
	constructor: (uid) ->
		@uid = uid
		@type = 'caret'
		@addString = "|"
		
	length: -> 1
	cursorDelta: -> 1
	merged: -> this
	split: -> [false, this]
	
opMap: {
	'str': OpAddString
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
	   if first.isAdd()
			   return [
					   [first,false],
					   [false,second]
			   ]
	   else if second.isAdd()
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
	if first and first.isAdd()
		if second then error()
		return [first, new OpRetain(first.length())]
	
	if second and second.isAdd()
		if first then error()
		return [new OpRetain(second.length()), second]
		
	if type(first) == 'retain' and type(second) == 'retain'
		return [first, second]
		
	if type(first) == 'remove' and type(second) == 'remove'
		return [false, false]
		
	if type(first) == 'remove' and type(second) == 'retain'
		return [first, false]
		
	if type(first) == 'retain' and type(second) == 'remove'
		return [false, second]
		
	error('fell off end')
		
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
						
			transformed = transform(parts[0][0], parts[1][0])
			
			if transformed[0]
				aprime.push(transformed[0])
			
			if transformed[1]
				bprime.push(transformed[1])
				
			aop = parts[0][1]
			bop = parts[1][1]
				
		while a.length or aop
			if not aop
				aop = a.shift()
			aprime.push(aop)
			aop = false
			
		while b.length or bop
			if not bop
				bop = b.shift()
			bprime.push(bop)
			bop = false
		
		return [new Change(bprime, @docid, @toVersion, 'merged'), new Change(aprime, @docid, other.toVersion, 'merged')]
			
		

	merge: (other) ->
		outops = []
		baseops = op for op in @operations
		
		go: (offset, output) ->
			i = 0
			while i<offset and baseops.length
				op = baseops.shift()
				i += op.cursorDelta()
				outops.push(op) if output
			if i>offset
				outops.pop() if output
				i -= op.cursorDelta()
				[a, b] = op.split(offset-i)
				outops.push(a) if output
				baseops.unshift(b)
		
		for operation in other.operations
			if operation.type == 'retain'
				go(operation.count, yes)
			else
				m: operation.merged()
				outops.push(m) if m
				go(operation.removes, no)
				
		return new Change(outops.concat(baseops), @docid, @fromVersion, other.toVersion)

exports.deserializeChange: (c)->
	c.__proto__ = Change.prototype
	for i in c.operations
		i.__proto__ = opMap[i.type].prototype
	return c

						
class OTDocument
	constructor: (id) ->
		@id: id
		@version: '0'
		@versionHistory: {}
		
	applyChange: (change) ->
		if change.docid? and change.docid != @id
			throw new Error("Tried to merge against wrong document")
		if change.toVersion == @version
			return
		if change.fromVersion != @version
			throw new Error("Tried to merge out of order (at $@version, revision from $change.fromVersion to $change.toVersion)")
		@setFromChange(@state.merge(change))
		
	setFromChange: (state) ->
		@state = state
		@version = state.toVersion
		@versionHistory[@version] = state

	text: () ->
		((if i.addString then i.addString else '') for i in @state.operations).join('')
	
	length: ->
		offset = 0
		for i in @state.operations
			offset += i.inserts
		return offset			
				
	makeVersion: ->
		''+(parseInt(@version, 10) + 1)
	
	
class OTUserEndpoint extends OTDocument
	constructor: (id, conn, uid) ->
		super(id)
		@conn = conn
		@uid = uid
		
		if @conn
			@conn.register(this)
		
		
	setFromChange: (change) ->
		first = not @state?
		super(change)
		@update()
		if first
			#initial load
			@applyChangeUp(new Change([new OpAddCaret(@uid),new OpRetain(@length())], @id, @version, @makeVersion()))
	
	applyChangeUp: (change) ->
		@applyChange(change)
		if @conn
			@conn.send(change)
		
	applyChangeDown: (change) ->
		@applyChange(change)
				
	findMyCaret: ->
		offset = 0
		for i in @state.operations
			if i.type == 'caret' and i.uid == @uid
				return offset
			else
				offset += i.inserts
	
	spliceAtCaret: (remove, add) ->
		offset = @findMyCaret()
		
		l = [new OpRetain(offset-remove)]
		if remove
			l.push(new OpRemove(remove))
		if add
			if add == '\r'
				l.push(new OpNewline())
			else
				l.push(new OpAddString(add))		
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
exports.OpAddString = OpAddString
exports.OpAddCaret = OpAddCaret
exports.OpRemove = OpRemove
exports.OTDocument = OTDocument
exports.OTUserEndpoint = OTUserEndpoint
exports.Change = Change

