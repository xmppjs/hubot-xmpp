{EventEmitter} = require 'events'

module.exports = class Controller extends EventEmitter

	@stanzas: {}
	@exposeEvents: []
	@expose: {}

	constructor: (@realtime) ->
		@setMaxListeners(0)


	createResult: (stanza) ->
		stanza.attrs.to = stanza.attrs.from
		stanza.attrs.from = @realtime.jid.toString()
		stanza.attrs.type = 'result'
