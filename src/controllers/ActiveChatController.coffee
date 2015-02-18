
Controller = require './framework/Controller.coffee'

module.exports = class ActiveChatController extends Controller

	@expose:
		setActive: (jid) ->
			unless @active then return
			if not @_actives
				@_updateQueue.push ActiveChatController.expose.setActive.bind @, jid
				return
				
			if @_actives[jid]?.active is true then return
			@realtime.debug 'active', 'setting', jid, 'as active'

			stanza = new ltx.Element('iq', type:'set', to:"pubsub.#{@realtime.jid.domain}", from:@realtime.jid.toString(), id:'activeChatsSet')
			stanza.c('pubsub', xmlns:'http://jabber.org/protocol/pubsub')
			.c('publish', node:'orgspan:activeChats')
			.c('item', id:jid, type:(if jid.match(/@conference/) then 'room' else 'person'))

			@realtime.send stanza


		setInactive: (jid) ->
			unless @active then return
			if not @_actives
				@_updateQueue.push ActiveChatController.expose.setInactive.bind @, jid
				return

			if @_actives[jid]?.active is false then return
			@realtime.debug 'active', 'setting', jid, 'as inactive'

			stanza = new ltx.Element('iq', type:'set', to:"pubsub.#{@realtime.jid.domain}", from:@realtime.jid.toString(), id:'activeChatsSet')
			stanza.c('pubsub', xmlns:'http://jabber.org/protocol/pubsub')
			.c('retract', node:'orgspan:activeChats')
			.c('item', id:jid, type:(if jid.match(/@conference/) then 'room' else 'person'))

			@realtime.send stanza

		getActiveChats: (callback) ->
			@realtime.debug 'active', 'getActiveChats called', @active
			if @_actives then return callback null, @_actives
			unless @active
				@active = true
				@realtime.features['orgspan:activeChats'] = true
				@_sendRequest()

			@realtime.debug 'active', 'waiting for _actives'
			@once 'actives', =>
				@realtime.debug 'active', 'returning _actives'
				callback null, @_actives


	@exposeEvents: ['activeChat']

	@stanzas:
		ignoredResult: (stanza) -> stanza.is('iq') and stanza.attrs.type is 'result' and stanza.attrs.id in ['activeChatsSet', 'activeChatsSub']
		activeChatsResult: (stanza) -> stanza.is('iq') and stanza.attrs.type is 'result' and stanza.getChildByAttr('node', "orgspan:activeChats", null, true)? and stanza.attrs.id isnt 'activeChatsSub'
		activeMessage: (stanza) -> stanza.is('message') and stanza.getChild('event', "http://jabber.org/protocol/pubsub#event")?.getChild('items')?.attrs.node is "orgspan:activeChats"

	constructor: ->
		super
		@_actives = null
		@_updateQueue = null
		@_updateQueue = []
		@realtime.on 'rosterItem', ({type}) => @emit type
		@realtime.on 'disconnect', => @onDisconnect()
		@realtime.on 'connect', => @onConnect()

	ignoredResult: ->

	onConnect: ->
		@realtime.debug 'guest', 'ActiveChatController is active?', @active
		unless @active then return
		@_sendRequest()

	onDisconnect: ->
		@_actives = null
		@_updateQueue = []

	activeChatsResult: (stanza) ->
		items = stanza.getChildByAttr('node', "orgspan:activeChats", null, true)
		@realtime.debug 'active', 'got activeChats result', items.toString()
		oldActives = @_actives or {}
		@_actives = {}
		for child in items.getChildren('item')
			jid = child.attrs.id
			active = true
			type = child.attrs.type
			@_actives[child.attrs.id] = {active, type}
			@emit 'activeChat', {jid, active, type}
		for jid, obj of oldActives
			unless @_actives[jid]
				active = false
				type = obj.type
				@emit 'activeChat', {jid, active, type}

		work = @_updateQueue
		@_updateQueue = []
		work.forEach (update) ->
			update()

		@emit 'actives'

	activeMessage: (stanza) ->
		@realtime.debug 'active', 'activeMessage', stanza.toString()
		items = stanza.getChild('event', "http://jabber.org/protocol/pubsub#event")?.getChild('items')
		for child in items.children
			unless child.name in ['item', 'retract'] then continue
			{id, type} = child.attrs
			if child.is 'item'
				active = true
			else if child.is 'retract'
				active = false
			@realtime.debug 'active', 'set', {id, active, type}, child.toString()
			@_actives[child.attrs.id] = {active, type}
			@emit 'activeChat', {jid:id, active, type}


	_sendRequest: ->
		@realtime.debug 'active', 'active _sendRequest', discovered:@realtime.discovered
		unless @realtime.connected then return @realtime.once 'connected', => @_sendRequest()

		if @realtime.features['orgspan:actives'] and !@realtime.discovered then return
		@realtime.getRoster =>
			@realtime.getGroups =>
				@realtime.debug 'active', 'sending activeChats request'
				iq = new ltx.Element 'iq', type:'set', from:@realtime.jid.toString(), to:"pubsub.#{@realtime.jid.domain}", id:'activeChatsSub'
				iq.c('pubsub', xmlns:'http://jabber.org/protocol/pubsub')
				.c('subscribe', node:'orgspan:activeChats', jid:@realtime.jid.toString())
				@realtime.send iq

				iq = new ltx.Element 'iq', from:@realtime.jid.toString(), type:'get'
				iq.c('pubsub', xmlns:'http://jabber.org/protocol/pubsub')
				.c 'items', node:'orgspan:activeChats'
				@realtime.send iq








