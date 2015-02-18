
Controller = require './framework/Controller.coffee'

module.exports = class PingController extends Controller

	@stanzas:
		ping: (stanza) -> stanza.is("iq") and stanza.attrs.type is "get" and stanza.getChild("ping", "urn:xmpp:ping")

	ping: (stanza) ->
		@createResult stanza
		@realtime.send stanza

