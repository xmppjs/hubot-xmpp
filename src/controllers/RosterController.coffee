
Controller = require './framework/Controller.coffee'

module.exports = class RosterController extends Controller

	@expose:
		getRoster: (callback) ->
			@realtime.debug 'roster', 'getRoster called', @active
			if @roster then return callback null, @roster
			unless @active
				@active = true
				@_sendRequest()

			@realtime.debug 'roster', 'waiting for roster'
			@once 'roster', =>
				@realtime.debug 'roster', 'returning roster'
				callback null, @roster

		addToRoster: (jid, callback) ->
			console.error 'not implemented'
			callback 'not implemented'
		
		removeFromRoster: (jid, callback) ->
			console.error 'not implemented'
			callback 'not implemented'

	@exposeEvents: ['rosterItem']

	@stanzas:
		rosterResult: (stanza) -> stanza.is('iq') and stanza.getChild('query', "jabber:iq:roster")? and stanza.attrs.type is 'result'
		rosterUpdate: (stanza) -> stanza.is('iq') and stanza.getChild('query', "jabber:iq:roster")? and stanza.attrs.type is 'set'
	
	constructor: ->
		super

		@roster = null
		@setMaxListeners(0)

		@realtime.on 'disconnect', => 
			@roster = null
			@requested = false
		@realtime.on 'connect', =>
			if @active then @_sendRequest()

			

	rosterResult: (stanza) ->
		@realtime.debug 'roster', 'message', stanza.toString()
		@roster = {}
		query = stanza.getChild('query', "jabber:iq:roster")
		for item in query.getChildren 'item'
			{jid, name} = item.attrs

			@roster[jid] = {name, jid}

			@emit 'rosterItem', {name, jid, section:'favorites', type:'person', event:'add'}

		@emit 'roster'

	rosterUpdate: (stanza) ->
		@realtime.debug 'roster', 'message', stanza.toString()
		@roster = {}
		query = stanza.getChild('query', "jabber:iq:roster")
		for item in query.getChildren 'item'
			{jid, name, subscription} = item.attrs

			if subscription in ['to', 'both']
				@roster[jid] = {name, jid}
				@emit 'rosterItem', {name, jid, section:'favorites', type:'person', event:'add'}

			else if subscription in ['remove', 'none']
				delete @roster[jid]
				@emit 'rosterItem', {name, jid, section:'favorites', type:'person', event:'remove'}

	_sendRequest: ->
		unless @realtime.connected then return @realtime.once 'connected', => @_sendRequest()
		if @realtime.features['orgspan:roster'] and !@realtime.discovered then return
		iq = new ltx.Element 'iq', type:'get', from:@realtime.jid.toString()
		iq.c 'query', xmlns:'jabber:iq:roster'
		@realtime.send iq



