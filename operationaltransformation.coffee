
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
	# Retain operation inserts [count] characters from previous version of the document
	
	constructor: (count) ->
		if count == 0
			warn("Useless retain")
		@type: 'retain'
		@count: count
		
	length: -> @count
	cursorDelta: -> @count
	
	movesOldCursor: -> @count
	movesNewCursor: -> @count
		
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
	# AddString operation inserts a string
	
	constructor: (addString) ->
		@type: 'str'
		@addString: addString
		
	length: -> @addString.length
	cursorDelta: -> @addString.length
	
	movesOldCursor: -> 0
	movesNewCursor: -> @addString.length
		
	split: (offset) ->
		a = @addString.slice(0, offset)
		b = @addString.slice(offset)
		a = if a then new OpAddString(a) else false
		b = if b then new OpAddString(b) else false
		return [a, b]
		
class OpNewline extends OpAdd
	# Newline operation inserts a line break
	
	constructor: ->
		@type: 'newline'
		@addString = '\n'
		
	length: -> 1
	cursorDelta: -> 1
	
	movesOldCursor: -> 0
	movesNewCursor: -> 1
	
	merged: -> this
	split: -> [false, this]
	
		
class OpRemove extends Operation
	# Remove operation skips over [n] characters from previous version so they are not included

	constructor: (n) ->
		@type: 'remove'
		@removes: n
		
	length: -> @removes
	cursorDelta: -> -1*@removes
	
	movesOldCursor: -> @removes
	movesNewCursor: -> 0
	
	merged: -> false
	
	split: (offset) ->
		if offset >= @length()
			[this, false]
		else if offset == 0
			[false, this]
		else
			[new OpRemove(offset), new OpRemove(@inserts-offset)]
			
	
opMap: {
	'str': OpAddString
	'remove': OpRemove
	'retain': OpRetain
	'newline': OpNewline
}

coalesceOps: (l) ->
	# Run through a list of operations, and mash together neighboring operations
	# of the same type.
	
	prevop = null
	out = []
	
	for i in l
		if prevop and i.type == prevop.type
			if i.type == 'str' #TODO: formatting must be the same
				prevop = new OpAddString(prevop.addString + i.addString)
				continue
			else if i.type == 'retain'
				prevop = new OpRetain(prevop.count + i.count)
				continue
			else if i.type == 'remove'
				prevop = new OpRemove(prevop.removes + i.removes)
				continue
		if prevop then out.push(prevop)
		prevop = i
	if prevop then out.push(prevop)
	return out
		

split: (first, second) ->
	# Takes two operations and splits them so they can be matched against each 
	# other by Change.transform. Returns a nested array. ret[0] is the two 
	# pieces of the first operation, ret[1] is the two pieces of the second.
	# Operations that add to the document are never paired against anything, 
	# as there is no matching operation from the other document
	 
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
	# transforms two operations against each other. Assumes that the two
	# operations have already been split and are the same length.
	# Takes an operation from A and B each and returns an
	# operation for A' and B'
	# Returning a false operation means no operation is inserted
	
	# keep the insert, add retain in opposing document because everything
	# must be shifted due to the addition
	# only one change can exist (as enforced by skip) because there are 
	# no corresponding characters on the opposing change, so we must insert the
	# retain and not replace anything here
	if first and first.isAdd()
		if second then error()
		return [first, new OpRetain(first.length())]
	if second and second.isAdd()
		if first then error()
		return [new OpRetain(second.length()), second]
		
	# both take same changes from parent version, so leave retains alone
	if first.type == 'retain' and second.type == 'retain'
		return [first, second]
		
	# both remove the same thing, so it doesn't need to be removed again
	if first.type == 'remove' and second.type == 'remove'
		return [false, false]
		
	# the characters no longer exist, so don't retain them any more
	if first.type == 'remove' and second.type == 'retain'
		return [first, false]	
	if first.type == 'retain' and second.type == 'remove'
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
		
		# aop and bop are the operations pending processing. 
		# when set to false, the next operation is pulled from the list
		aop = false
		bop = false
		
		while a.length and b.length
			if not aop
				aop = a.shift()
			if not bop
				bop = b.shift()
				
			parts = split(aop, bop)
						
			transformed = transform(parts[0][0], parts[1][0])
			
			# add the transformed operations (if they exist) to the output
			if transformed[0]
				aprime.push(transformed[0])			
			if transformed[1]
				bprime.push(transformed[1])
				
			# the leftover parts of the split operations become the next pending operations
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
		
		return [new Change(bprime, @docid, @toVersion, other.toVersion+'m'), new Change(aprime, @docid, other.toVersion, other.toVersion+'m')]
		
	isNoOp: ->
		for i in @operations
			if i.type!=retain
				return false
		return true
			
	merge: (other) ->
		outops = []
		baseops = op for op in @operations
		
		go: (offset, output) ->
			i = 0
			while i<offset and baseops.length
				op = baseops.shift()
				i += op.cursorDelta()
				outops.push(op) if output
			if i>offset and op
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
				
		return new Change(coalesceOps(outops.concat(baseops)), @docid, @fromVersion, other.toVersion)
		
	offsetPoint: (p) ->
		oldoffset = 0
		delta = 0
		for i in @operations
			o = i.movesOldCursor()
			if oldoffset + o > p
				break
			oldoffset += o
			delta += i.movesNewCursor() - o
		return p + delta
			

exports.deserializeChange: (c)->
	c.__proto__ = Change.prototype
	for i in c.operations
		i.__proto__ = opMap[i.type].prototype
	return c

						
class OTDocument
	constructor: (id) ->
		@id: id
		@version: 'null'
		@versionHistory: {}
		@setFromChange(new Change([], @id, 'null', 'null'))
		
	applyChange: (change) ->
		if change.docid? and change.docid != @id
			throw new Error("Tried to merge against wrong document")
		if change.toVersion == @version
			return false
		if change.fromVersion != @version
			throw new Error("Tried to merge out of order (at $@version, revision from $change.fromVersion to $change.toVersion)")
		@setFromChange(@state.merge(change))
		return true
		
	setFromChange: (state) ->
		@state = state
		@version = state.toVersion
		@versionHistory[@version] = state

	text: () ->
		((if i.addString then i.addString else '') for i in @state.operations).join('')
	
	length: ->
		offset = 0
		for i in @state.operations
			offset += i.length()
		return offset
		
	changesFromTo: (from, to) ->
		sys:require('sys')
		sys.puts("from $from to $to")
		change = @versionHistory[from]
		merged = false
		while change and change.toVersion != to
			sys.puts(sys.inspect(change))
			change = @versionHistory[change.toVersion]
			if merged
				merged = merged.merge(change)
			else
				merged = changed
		return merged
		
	
class OTUserEndpoint extends OTDocument
	constructor: (id, conn, uid) ->
		super(id)
		@conn = conn
		@uid = uid
		@firstChange = true
		
		if @conn
			@conn.register(this)
			
	makeVersion: ->
		"$@uid-${new Date().getTime()}-${Math.round(Math.random()*100000)}"
		
	applyChangeUp: (change) ->
		@applyChange(change)
		if @conn
			@conn.send(change)
		
	applyChangeDown: (change) ->
		@applyChange(change)
		
	splice: (offset, remove, add) ->
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
		
	spliceRange: (start, end, insert) ->
		l = [new OpRetain(start)]
		
		if end != start
			l.push(new OpRemove(end-start))
		if insert
			l = l.concat(insert)
		
		l.push(new OpRetain(@length() - end))
		change = new Change(l, @id, @version, @makeVersion())
		@applyChangeUp(change)
		

		
	update: () -> false
		
class OTServerEndpoint extends OTDocument
	constructor: (docid) ->
		super(docid)
		@clients = {}
		
	makeVersion: ->
		"server-${new Date().getTime()}-${Math.round(Math.random()*100000)}"
		
	join: (client) ->
		@clients[client.uid] = client
		client.socket.send JSON.stringify {
			type: 'change'
			docId: @id
			change: @state
		}
		
	handleChange: (change, fromUid) ->
		unmerged = @changesFromTo(change.fromVersion, @version)
		
		if not unmerged
			up = change
			down = false
		else
			[up, down] = unmerged.transform(change, unmerged)
			
			
		sys: require('sys')
		sys.puts("change: ${sys.inspect(change)}, up: ${sys.inspect(up)}, down: ${sys.inspect(down)}")
		
		@applyChange(up)
		
		msg = JSON.stringify {
				type: 'change'
				docId: @id
				change: up
			}
			
		for i of @clients
			if i != fromUid # don't send back to author
				@clients[i].socket.send(msg)
			else if down
				@clients[i].socket.send JSON.stringify {
					type: 'change'
					docId: @id
					change:down
				}
				
		#TODO: OT
		
	leave: (client) ->
		delete @clients[client.uid]
			
		
			

exports.OpRetain = OpRetain
exports.OpAddString = OpAddString
exports.OpRemove = OpRemove
exports.OpNewline = OpNewline
exports.OTDocument = OTDocument
exports.OTUserEndpoint = OTUserEndpoint
exports.OTServerEndpoint = OTServerEndpoint
exports.Change = Change

