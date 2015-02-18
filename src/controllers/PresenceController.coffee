_ = require 'underscore'
uuid = require 'uuid'

Controller = require './framework/Controller.coffee'

module.exports = class PresenceController extends Controller

	presences: {}
	_timeout: 1000 * 60 * 10

	@expose: 
		subscribeToPresence: (jids...) ->
			@_getOrSubscribeToPresence jid for jid in jids

			return

		requestPresence: (jids...) ->
			@_getOrSubscribeToPresence jid for jid in jids

			return

		unsubscribeFromPresence: (jids...) ->
			@realtime.debug 'presence', 'unsubscribeFromPresence', jids
			for jid in jids
				@realtime.send new ltx.Element 'presence', from:@realtime.jid.toString(), to:jid, type:'unsubscribe'
				delete @_presences[jid]

			return

		setPresence: (presence) ->
			@realtime.debug 'presence', 'setPresence', presence, @realtime.presence
			if presence is 'offline' then throw Error('Do not set your presence to offline, please use disconnect() instead.')
			unless presence in ['online', 'away', 'busy'] then throw Error('invalid presence '+presence)
			if presence is @realtime.presence then return
			@realtime.presence = presence
			@realtime.debug 'presence', 'lib setPresence', presence

			@_sendPresence()

			return

		#callback will be called when the status change succeeds or fails, with a first argument being an Error with a message and a "code" property with the numeric status code
		setStatus: (status, callback) ->
			status ?= ''
			@realtime.debug 'presence', 'setStatus', status, @realtime.status
			if status is @realtime.status then return
			@realtime.status = status
			@_sendPresence(callback)

			return

		setLocation: (location) ->
			location ?= ''
			@realtime.debug 'presence', 'setLocation', location, @realtime.location
			if location is @realtime.location then return
			@realtime.location = location
			@_sendPresence()

			return

	@exposeEvents: ['presence']

	@stanzas:
		onMePresence: (stanza) -> stanza.is('presence') and stanza.attrs.from is @realtime.jid?.bare().toString()
		onPresence: (stanza) -> stanza.is('presence') and stanza.attrs.from isnt @realtime.jid?.bare().toString() and stanza.attrs.type in [undefined, 'unavailable'] and !stanza.attrs.from.match(/@conference/)
		onPresenceError: (stanza) -> stanza.is('presence') and stanza.attrs.type is "error" and stanza.attrs.to is @realtime.jid?.toString()
		ignore: (stanza) -> stanza.is('presence') and stanza.attrs.from isnt @realtime.jid?.bare().toString() and stanza.attrs.type in ['subscribed', 'unsubscribed']

	extraSubscriptions: []

	constructor: ->
		super
		@extraSubscriptions = []

		@realtime.on 'connect', =>

			@_presences = {}
			@_waitingOnReplies = {}
			@_sendPresenceCallbacks = {}

			unless @active then return

			@realtime.presence = null
			@realtime.status = ''
			@realtime.location = ''
			
			# subscribe to self presence
			@realtime.send new ltx.Element 'presence', id:'mepresence', from:@realtime.jid.toString(), to:@realtime.jid.bare().toString(), type:'subscribe'
			
			for jid in @extraSubscriptions
				@_requestSubscription jid

		focusHandler = => 
			@realtime.debug 'focus', 'presence focused'
			@_focused = true
			if @_focusTid
				clearTimeout @_focusTid
				@_focusTid = null
			setTimeout (=>
				if @_beforeIdlePresence
					@realtime.presence = @_beforeIdlePresence
					@_beforeIdlePresence = null
					@_sendPresence()
			), 500

		if global.window
			$(window).on 'focus', focusHandler
			$(window).on 'mouseover', _.debounce(focusHandler, 5000, true)
			
			$(window).on 'blur', =>
				@realtime.debug 'focus', 'blur'
				@_focused = false
				if @_focusTid then return
				@_focusTid = setTimeout (=>
					if (presence = @realtime.presence) in [undefined, 'offline', 'idle'] then return
					@_beforeIdlePresence = presence
					@realtime.presence = 'idle'
					@_sendPresence()
				), @_timeout

	ignore: ->

	onPresenceError: (stanza) ->

		@_removeWaitingReply stanza.attrs.id

		callback = @_sendPresenceCallbacks[stanza.attrs.id]

		if callback
			errorNode = stanza.getChild "error"
			errorText = errorNode.getChild "text"
			

			error = new Error errorText
			error.code = parseInt errorNode.attrs.code

			@realtime.debug 'presence', 'Send presence failed: #{error.code} - #{errorText}'

			delete @_sendPresenceCallbacks[stanza.attrs.id]
			callback error
		
	onMePresence: (stanza) ->
		if stanza.attrs.type in ['subscribed', 'unsubscribed']
			return

		callback = @_sendPresenceCallbacks[stanza.attrs.id]
		if callback
			callback(null) #null error to indicate success
			delete @_sendPresenceCallbacks[stanza.attrs.id]

		# The goal of these two lines is to save the last seen incoming stanza
		# for processing, and the process it once the server has replied to any
		# presence changes.
		@_postReplyReact = @_reactToStanza.bind @, stanza
		@_removeWaitingReply stanza.attrs.id

	_removeWaitingReply: (id) ->
		if _.has @_waitingOnReplies, id
			timer = @_waitingOnReplies[id]
			if timer
				clearTimeout timer
			delete @_waitingOnReplies[id]

		if 0 is _.size @_waitingOnReplies
			if @_postReplyReact
				func = @_postReplyReact
				@_postReplyReact = null
				func()

	_reactToStanza: (stanza) ->
		if @realtime.disconnected
			return
			
		[presence, status, location] = @_translatePresence stanza
		@realtime.debug 'presence', 'onMePresence', presence, status, stanza.toString()

		if presence isnt @realtime.presence and presence in ['online', 'busy', 'away']
			if @_beforeIdlePresence?
				@_beforeIdlePresence = presence
			else
				@realtime.presence = presence
				changed = true

		unless @realtime.presence
			@realtime.presence = 'online'
			changed = true

		if status isnt @realtime.status
			@realtime.status = status
			changed = true

		if changed
			@realtime.debug 'presence', 'me presence changed', @realtime.presence, @realtime.status
			@_sendPresence()

	onPresence: (stanza) ->
		@realtime.debug 'presence', stanza.attrs.from, stanza.attrs.type
		if stanza.attrs.type in ['subscribed', 'unsubscribed']
			return

		[presence, status, location] = @_translatePresence stanza

		@emit 'presence', @_presences[stanza.attrs.from] = {from:stanza.attrs.from, presence, status, location}
		
	onSubscribe: (stanza) ->
		@realtime.debug 'presence', 'onSubscribe'

	onUnSubscribe: (stanza) ->
		@realtime.debug 'presence', 'onUnSubscribe'

	_translatePresence: (stanza) ->
		show = stanza.getChild('show')?.text() or 'online'
		if stanza.attrs.type is 'unavailable' then show = 'offline'
		status = stanza.getChild('status')?.text() or ''
		location = stanza.getChild('location')?.text() or ''
		presence = switch show
			when 'offline' then 'offline'
			when 'chat' then 'online'
			when 'away' then 'away'
			when 'dnd' then 'busy'
			when 'xa' then 'idle'
			else 'online'

		return [presence, status, location]

	_sendPresence: (callback) ->
		unless @realtime.connected
			
			error = new Error "not connected to the realtime service"
			error.code = 400
			callback error
			return

		callback = _.once callback or ->

		@realtime.debug 'presence', 'controller sending', @realtime.presence, @realtime.status
		presence = switch @realtime.presence
			when 'idle' then 'xa'
			when 'busy' then 'dnd'
			else @realtime.presence
		stanza = new ltx.Element 'presence', from:@realtime.jid.toString(), 'xml:lang':'en'

		if presence is 'offline' then stanza.attrs.type = 'unavailable'
		else if presence isnt 'online' then stanza.c('show').t presence
	
		stanza.c('status').t(@realtime.status)

		stanza.attrs.id = uuid.generate()

		# If a reply from the server has not been seen in a second, then assume
		# that the stanza was lost and remove it and avoid waiting forever
		timer = setTimeout =>
			@_removeWaitingReply stanza.attrs.id
			
			error = new Error("status update timed out")
			error.code = 500
			callback error

			delete @_sendPresenceCallbacks[stanza.attrs.id]
		, 1000
		@_waitingOnReplies[stanza.attrs.id] = timer

		@_sendPresenceCallbacks[stanza.attrs.id] = callback


		@realtime.send stanza
		{presence, status, location} = @realtime
		@emit 'presence', {from:@realtime.jid.bare().toString(), presence, status, location}

	_getOrSubscribeToPresence: (jid) ->
		unless jid then return
		unless @active then return
		if jid.match /@conference/ then return


		@realtime.debug 'presence', 'presence requested for', jid
		if jid is @realtime.jid?.bare().toString()
			@realtime.debug 'presence', 'self presence requested'
			{presence, status, location} = @realtime
			return @emit 'presence', {from:@realtime.jid.bare().toString(), presence, status, location}
		if @_presences[jid]
			return @emit 'presence', _.extend(@_presences[jid], {from:jid})
		else
			@realtime.getRoster (err, roster) =>
				if err then return console?.error err
				unless roster[jid]
					if 0 > _.indexOf @extraSubscriptions, jid
						@extraSubscriptions.push jid
					@_requestSubscription jid

					# else assume the presence will be here shortly.

	_requestSubscription: (jid) ->
		@realtime.send new ltx.Element 'presence', from:@realtime.jid.toString(), to:jid, type:'subscribe'