
Controller = require './framework/Controller.coffee'

module.exports = class DiscoveryController extends Controller

	@stanzas:
		discovery: (stanza) -> stanza.is("iq") and stanza.attrs.type is 'get' and stanza.getChild("query")?.toString().match(/(disco#info|disco#items)/)
		set: (stanza) -> stanza.is("iq") and stanza.attrs.type is 'set'

	constructor: ->
		super
		@realtime.on 'disconnect', =>
			@realtime.discovered = false

	discovery: (stanza) ->
		@realtime.debug 'disco', 'discovery', stanza.toString(), @realtime?.jid?.toString()
		@createResult stanza
		query = stanza.getChild 'query'
		for feature, active of @realtime.features
			if !active then continue
			query.c 'feature', var: feature

		@realtime.discovered = true
		@realtime.send stanza


	set: (stanza) ->
		###
		silently ignore for now. As of right now the only feature I know of that this is used for is file transfers. 
		Presumably I'll support this on the web at some point but for the moment ignore it because adium at least broadcasts the transfer to
		multiple clients instead of sending to only one directly, which is rude frankly.
		####