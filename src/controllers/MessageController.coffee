
Controller = require './framework/Controller.coffee'

module.exports = class MessageController extends Controller

	@exposeEvents: ['message', 'chatState']

	@expose:
		_clearMessages: (jid) ->
			delete @_messages[jid]

		sendChatState: (to, state) ->
			if state.match /@/
				[to, state] = [state, to]

			@realtime.debug 'chatstates', 'sending', state, to
			stanza = new ltx.Element 'message', to:to, from:@realtime.jid, type:(if to.match(/@conference/) then 'groupchat' else 'chat')
			stanza.c(state, xmlns:'http://jabber.org/protocol/chatstates')
			@realtime.send stanza

		sendMessage: (to, body, callback) ->
			callback ?= (err) => if err then throw err
			unless body?.trim().length then return callback new Error('body cannot be empty')
			unless to?.toString().match(/@/) then return callback new Error('to must be a full jid')

			@realtime.debug 'message', 'sending', to, body

			id = uuid.generate()
			message = {
				id, 
				from: @realtime.jid.bare().toString(), 
				to, 
				body: body, 
				time: new Date(), 
				pending: true
			}
			@emit 'message', message
			@_messages[to]?[id] = {id, from:@realtime.jid.bare().toString(), body:formatted, links, time:new Date(), raw:body}
		
			type = (if to.match(/@conference/) then 'groupchat' else 'chat')
			stanza = new ltx.Element 'message', to:to, from:@realtime.jid, type:type, oid:id
			stanza.c('body').t(body)
			stanza.c('active', xmlns:'http://jabber.org/protocol/chatstates')
			
			@_pending[id] = true
			
			@realtime.send stanza

			@once "carbon:#{id}", (err)-> 
				delete message.pending
				if err
					message.err = err
					callback err, message
				else
					return callback null, message 
				
			id

		getMessages: (options, callback) ->
			unless callback then throw new Error 'missing callback'
			if typeof options is 'string'
				options = {jid:options}

			{jid, before, after} = options
			if before
				if !(before instanceof Date) then before = new Date before
				unless before.getTime() is before.getTime() then return callback new Error('invalid date')
			if after
				if !(after instanceof Date) then after = new Date after
				unless after.getTime() is after.getTime() then return callback new Error('invalid date')

			unless jid then return callback new Error "missing jid"
			
			cb = (messages) ->
				return callback null, _.chain(messages).values().sortBy((m) -> m.time).value()
			
			if not before and not after and @_messages[jid]?
				return cb @_messages[jid]

			stanza = new ltx.Element 'iq', type:'get', id:Realtime.uuid.generate(), from:@realtime.jid.toString()
			retrieve = stanza.c 'messages', 
				xmlns: 'orgspan:history'
				with: jid
				limit: options.limit || 100
			if before then retrieve.attrs.end = before.toISOString()
			if after then retrieve.attrs.start = after.toISOString()

			if navigator.userAgent?.match /MSIE 8.0/
				retrieve.attrs.limit = 10

			@realtime.send stanza

			@once 'history:'+stanza.attrs.id, cb

		getRecents: (opts, callback) -> # {jid, type, id, time, participants}
			@realtime.debug 'recent', 'getRecents', opts, callback
			if typeof opts is 'function'
				callback = opts
				opts = {}

			# if @recents then return callback @recents

			stanza = new ltx.Element 'iq', type:'get', id:Realtime.uuid.generate(), from:@realtime.jid.toString()
			retrieve = stanza.c 'chats', xmlns:'orgspan:history', end:new Date().toISOString()
			if opts.jid then retrieve.attrs.with = opts.jid
			if opts.before then retrieve.attrs.end = before
			if opts.after then retrieve.attrs.start = after
			retrieve.attrs.limit = opts.limit or 20

			@realtime.send stanza

			cb = (chats) ->
				return callback null, _.chain(chats).values().sortBy((m) -> m.time).value()

			@once 'history:'+stanza.attrs.id, cb

	@stanzas:
		handleChatstate: (stanza) -> stanza.is('message') and stanza.getChildByAttr('xmlns', 'http://jabber.org/protocol/chatstates', null, true)?
		handleMessage: (stanza) -> stanza.is('message') and stanza.getChild('body')?.text() and stanza.attrs.type isnt 'error' and !stanza.getChild('x', 'jabber:x:conference')?.attrs.jid?
		handleMessageHistory: (stanza) -> stanza.is('iq') and stanza.getChild('messages', 'orgspan:history')?
		handleChatHistory: (stanza) -> stanza.is('iq') and stanza.getChild('chats', 'orgspan:history')?

	constructor: ->
		super
		@_pending = {}
		@realtime.on 'connect', =>
			@_messages = {}

	handleChatHistory: (stanza) ->
		@realtime.debug 'recent', stanza
		ret = []
		for chat in stanza.getChild('chats')?.getChildren('chat') or []
			ret.push c = {
				with:chat.attrs.with
				type:chat.attrs.type
				id:chat.attrs.id
				time:new Date(chat.attrs.utc)
				subject:chat.attrs.subject, participants:[]
				unread:chat.attrs.unread or false
			}
			for p in chat.getChildren('participant')
				c.participants.push p.text()

		@emit 'history:'+stanza.attrs.id, ret

	handleMessage: (stanza) ->
		@realtime.debug 'message', 'message', stanza.toString()
		type = stanza.attrs.type
		if type is 'chat'
			from = new JID(stanza.attrs.from).bare().toString()
			to = new JID(stanza.attrs.to).bare().toString()
			key = from
			key = if from is @realtime.jid.bare().toString() then to else from # carbons
		else if type is 'groupchat'
			from = new JID(stanza.attrs.ofrom).bare().toString()
			to = new JID(stanza.attrs.from).bare().toString()
			key = to

		messageType = stanza.getChild('type')?.text()
		
		body = stanza.getChild 'body'
		if body?.text().match /^\?OTR/
			toJid = new JID stanza.attrs.to
			if to.resource
				stanza.attrs.from = @realtime.jid
				staza.attrs.to = stanza.attrs.from
				body.text "?OTR The Recipient cannot handle OTR messages."
				stanza.attrs.type = 'error'
				return @realtime.send stanza
			else return

		id = stanza.attrs.id

		if @_messages[key]?[id] then return @realtime.debug 'message', 'double message', stanza.toString()

		# [CORE-1810] Setting ID to the OID if the message is from the current
		#							participant. This prevents the message from being duplicated
		#							in the case of a reconnect.
		#
		id = if from is @realtime.jid.bare().toString() and stanza.attrs.oid then stanza.attrs.oid else stanza.attrs.id

		body = stanza.getChild('body')?.text()
		# raw = _.str.escapeHTML(raw)

		if not stanza.attrs.utc then @realtime.debug 'message', 'message without timestamp', stanza.toString()

		# if we havent already gotten history for this key then don't add this message until that has happened.
		message = {id, from, to, body, time:new Date(stanza.attrs.utc or Date.now()), type:messageType}
		@_messages[key]?[id] = message

		if @_pending[stanza.attrs.oid]
			delete @_pending[stanza.attrs.oid]
			@emit "carbon:#{stanza.attrs.oid}"
			return

		@realtime.debug 'message', 'emit', message
		@emit 'message', message

	handleChatstate: (stanza) ->
		state = stanza.getChildByAttr('xmlns', 'http://jabber.org/protocol/chatstates')
		@realtime.debug 'chatstate', 'received', stanza.attrs.from, state.name
		if stanza.attrs.from is @realtime.jid.bare().toString() then return
		if stanza.attrs.from.match /@conference/
			from = stanza.attrs.ofrom
			room = stanza.attrs.from.split('/')[0]
		else from = stanza.attrs.from
		@emit 'chatState', {from, room, state:state.name}

	handleMessageHistory: (stanza) ->
		history = stanza.getChild 'messages'
		@realtime.debug 'archive', 'historyResult', stanza.attrs.id
		unless history then return

		@_messages[history.attrs.with] ?= {}
		_messages = {}

		myjid = @realtime.jid.bare().toString()
		for child in history.children
			@realtime.debug 'archive', 'child', child.toString()
			if not child.attrs.utc then @realtime.debug 'message', 'message without timestamp', child.toString()

			# [CORE-1810] Setting ID to the OID if the message is from the current
			#             participant. This prevents the message from being duplicated
			#             in the case of a reconnect.
			#
			# TODO: instead of changing the ID here, we should emit the ID correctly on send
			id = if child.attrs.from == myjid and child.attrs.oid then child.attrs.oid else child.attrs.id

			body = child.getChild('body').text()

			message = 
				id:    id
				from:  child.attrs.from
				to:    child.attrs.to
				body:  body
				time:  new Date(child.attrs.utc)

			_messages[id] = message
			unless history.attrs.start or history.attrs.end then @_messages[history.attrs.with][id] = message
				

		return @emit 'history:'+stanza.attrs.id, _messages















