
Controller = require './framework/Controller.coffee'

module.exports = class GroupController extends Controller

	@exposeEvents: ['rosterItem']

	@expose:
		getGroups: (callback) ->
			@realtime.debug 'groups', 'getGroups called'
			if @groups then return callback null, @groups
			unless @active
				@active = true
				@_sendRequest()
			else
				@realtime.debug 'groups', 'waiting for groups'
				@once 'groups', =>
					@realtime.debug 'groups', 'returning groups', @groups
					callback null, @groups
	@stanzas:
		ignoredResult: (stanza) -> stanza.is('iq') and stanza.attrs.type is 'result' and stanza.attrs.id in ['focusSet', 'focusSub']
		groupsResult: (stanza) -> stanza.is('iq') and stanza.getChildByAttr('node', "orgspan:groups", null, true)? and stanza.attrs.type is 'result'
		groupMessage: (stanza) -> stanza.is('message') and stanza.getChild('event', "http://jabber.org/protocol/pubsub#event")?.getChild('items')?.attrs.node is "orgspan:groups"

	constructor: ->
		super

		@realtime.on 'disconnect', => @groups = null
		@realtime.on 'connect', =>
			unless @active then return
			@_sendRequest()

	ignoredResult: (stanza) ->

	groupsResult: (stanza) ->
		@groups = {}
		@realtime.debug 'group', 'groupsResult', stanza.toString()
		items = stanza.getChildByAttr('node', "orgspan:groups", null, true)
		for item in items.getChildren('item')
			item = item.getChild('group')
			{name, jid} = item.attrs
			@groups[item.attrs.jid] = item.attrs

			if item.attrs.autojoin then _.throttle(@realtime.joinRoom(item.attrs.jid), 1000)

			@emit 'rosterItem', {name, jid, section:'groups', type:'room', event:'add'}

		@emit 'groups'

	groupMessage: (stanza) ->
		@realtime.debug 'group', 'groupsMessage', stanza.toString()
		items = stanza.getChildByAttr('node', "orgspan:groups", null, true)
		for child in items.children
			unless child.name in ['item', 'retract'] then continue
			if child.name is 'item'
				item = child.getChild('group')
				{name, jid} = item.attrs
				@groups[item.attrs.jid] = {name:item.attrs.name, jid:item.attrs.jid}

				_.throttle(@realtime.joinRoom(item.attrs.jid), 1000)

				@emit 'rosterItem', {name, jid, section:'groups', type:'room', event:'add'}
			else
				@realtime.debug 'group', 'removing group', child.attrs.id
				jid = child.attrs.id+"@conference."+@realtime.jid.domain
				group = @groups[jid]
				unless group
					return
				delete @groups[jid]
				@emit 'rosterItem', {name:group, jid, section:'groups', type:'room', event:'remove'}


		@emit 'groups'

	_sendRequest: ->
		unless @realtime.connected then return @realtime.once 'connected', => @_sendRequest()
		if @realtime.features['orgspan:groups'] and !@realtime.discovered then return
		@realtime.debug 'group', 'sending group subscription'
		iq = new ltx.Element 'iq', type:'set', from:@realtime.jid.toString(), to:"pubsub.#{@realtime.jid.domain}", id:'groupSub'
		iq.c('pubsub', xmlns:'http://jabber.org/protocol/pubsub')
		.c('subscribe', node:'orgspan:groups', jid:@realtime.jid.toString())
		@realtime.send iq

		@realtime.debug 'group', 'sending group request'
		iq = new ltx.Element 'iq', from:@realtime.jid.toString(), type:'get'
		iq.c('pubsub', xmlns:'http://jabber.org/protocol/pubsub').c('items', node:'orgspan:groups')
		@realtime.send iq










