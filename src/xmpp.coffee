{Adapter,Robot,TextMessage,EnterMessage,LeaveMessage} = require 'hubot'

Xmpp = require 'node-xmpp'
util = require 'util'

class XmppBot extends Adapter

  constructor: ( robot ) ->
    @robot = robot

    # Flag to log a warning message about group chat configuration only once
    @anonymousGroupChatWarningLogged = false

    # Store the room JID to private JID map.
    # Key is the room JID, value is the private JID
    @roomToPrivateJID = {}

  run: ->
    options =
      username: process.env.HUBOT_XMPP_USERNAME
      password: '********'
      host: process.env.HUBOT_XMPP_HOST
      port: process.env.HUBOT_XMPP_PORT
      rooms: @parseRooms process.env.HUBOT_XMPP_ROOMS.split(',')
      # ms interval to send whitespace to xmpp server
      keepaliveInterval: 30000
      legacySSL: process.env.HUBOT_XMPP_LEGACYSSL
      preferredSaslMechanism: process.env.HUBOT_XMPP_PREFERRED_SASL_MECHANISM
      disallowTLS: process.env.HUBOT_XMPP_DISALLOW_TLS

    @robot.logger.info util.inspect(options)
    options.password = process.env.HUBOT_XMPP_PASSWORD

    @client = new Xmpp.Client
      reconnect: true
      jid: options.username
      password: options.password
      host: options.host
      port: options.port
      legacySSL: options.legacySSL
      preferredSaslMechanism: options.preferredSaslMechanism
      disallowTLS: options.disallowTLS

    @client.on 'error', @.error
    @client.on 'online', @.online
    @client.on 'stanza', @.read
    @client.on 'offline', @.offline

    @options = options
    @connected = false

  error: (error) =>
    if error.code == "ECONNREFUSED"
      @robot.logger.error "Connection refused, exiting"
      setTimeout () ->
        process.exit(1)
      , 1500
    else if error.children?[0]?.name == "system-shutdown"
      @robot.logger.error "Server shutdown detected, exiting"
      setTimeout () ->
        process.exit(1)
      , 1500
    else
      @robot.logger.error error.toString()
      console.log util.inspect(error.children?[0]?.name, { showHidden: true, depth: 1 })

  online: =>
    @robot.logger.info 'Hubot XMPP client online'

    presence = new Xmpp.Element 'presence'
    presence.c('nick', xmlns: 'http://jabber.org/protocol/nick').t(@robot.name)
    @client.send presence
    @robot.logger.info 'Hubot XMPP sent initial presence'

    @joinRoom room for room in @options.rooms

    # send raw whitespace for keepalive
    @keepaliveInterval = setInterval =>
      @client.send ' '
    , @options.keepaliveInterval

    @emit if @connected then 'reconnected' else 'connected'
    @connected = true

  parseRooms: (items) ->
    rooms = []
    for room in items
      index = room.indexOf(':')
      rooms.push
        jid:      room.slice(0, if index > 0 then index else room.length)
        password: if index > 0 then room.slice(index+1) else false
    return rooms

  # XMPP Joining a room - http://xmpp.org/extensions/xep-0045.html#enter-muc
  joinRoom: (room) ->

    @client.send do =>
      @robot.logger.debug "Joining #{room.jid}/#{@robot.name}"

      # prevent the server from confusing us with old messages
      # and it seems that servers don't reliably support maxchars
      # or zero values
      el = new Xmpp.Element('presence', to: "#{room.jid}/#{@robot.name}")
      x = el.c('x', xmlns: 'http://jabber.org/protocol/muc')
      x.c('history', seconds: 1 )

      if (room.password)
        x.c('password').t(room.password)
      return x

  # XMPP Leaving a room - http://xmpp.org/extensions/xep-0045.html#exit
  leaveRoom: (room) ->
    # messageFromRoom check for joined rooms so remvove it from the list
    for joined, index in @options.rooms
      if joined.jid == room.jid
        @options.rooms.splice index, 1

    @client.send do =>
      @robot.logger.debug "Leaving #{room.jid}/#{@robot.name}"

      return new Xmpp.Element('presence',
        to: "#{room.jid}/#{@robot.name}",
        type: 'unavailable')

  read: (stanza) =>
    if stanza.attrs.type is 'error'
      @robot.logger.error '[xmpp error]' + stanza
      return

    switch stanza.name
      when 'message'
        @readMessage stanza
      when 'presence'
        @readPresence stanza
      when 'iq'
        @readIq stanza

  readIq: (stanza) =>
    @robot.logger.debug "[received iq] #{stanza}"

    # Some servers use iq pings to make sure the client is still functional.
    # We need to reply or we'll get kicked out of rooms we've joined.
    if (stanza.attrs.type == 'get' && stanza.children[0].name == 'ping')
      pong = new Xmpp.Element('iq',
        to: stanza.attrs.from
        from: stanza.attrs.to
        type: 'result'
        id: stanza.attrs.id)

      @robot.logger.debug "[sending pong] #{pong}"
      @client.send pong

  readMessage: (stanza) =>
    # ignore non-messages
    return if stanza.attrs.type not in ['groupchat', 'direct', 'chat']
    return if stanza.attrs.from is undefined

    # ignore empty bodies (i.e., topic changes -- maybe watch these someday)
    body = stanza.getChild 'body'
    return unless body

    from = stanza.attrs.from
    message = body.getText()

    if stanza.attrs.type == 'groupchat'
      # Everything before the / is the room name in groupchat JID
      [room, user] = from.split '/'

      # ignore our own messages in rooms or messaged without user part
      return if user is undefined or user == "" or user == @robot.name

      # Convert the room JID to private JID if we have one
      privateChatJID = @roomToPrivateJID[from]

    else
      # Not sure how to get the user's alias. Use the username.
      # The resource is not the user's alias but the unique client
      # ID which is often the machine name
      [user] = from.split '@'
      # Not from a room
      room = undefined
      # Also store the private JID so we can use it in the send method
      privateChatJID = from

    # note that 'user' isn't a full JID in case of group chat,
    # just the local user part
    # FIXME Not sure it's a good idea to use the groupchat JID resource part
    # as two users could have the same resource in two different rooms.
    # I leave it as-is for backward compatiblity. A better idea would
    # be to use the full groupchat JID.
    user = @robot.brain.userForId user
    user.type = stanza.attrs.type
    user.room = room
    user.privateChatJID = privateChatJID if privateChatJID

    @robot.logger.debug "Received message: #{message} in room: #{user.room}, from: #{user.name}. Private chat JID is #{user.privateChatJID}"

    @receive new TextMessage(user, message)

  readPresence: (stanza) =>
    fromJID = new Xmpp.JID(stanza.attrs.from)

    # xmpp doesn't add types for standard available mesages
    # note that upon joining a room, server will send available
    # presences for all members
    # http://xmpp.org/rfcs/rfc3921.html#rfc.section.2.2.1
    stanza.attrs.type ?= 'available'

    switch stanza.attrs.type
      when 'subscribe'
        @robot.logger.debug "#{stanza.attrs.from} subscribed to me"

        @client.send new Xmpp.Element('presence',
            from: stanza.attrs.to
            to:   stanza.attrs.from
            id:   stanza.attrs.id
            type: 'subscribed'
        )
      when 'probe'
        @robot.logger.debug "#{stanza.attrs.from} probed me"

        @client.send new Xmpp.Element('presence',
            from: stanza.attrs.to
            to:   stanza.attrs.from
            id:   stanza.attrs.id
        )
      when 'available'
        # If the presence is from us, track that.
        if fromJID.resource == @robot.name
          @heardOwnPresence = true
          return

        # ignore presence messages that sometimes get broadcast
        # Group chat jid are of the form
        # room_name@conference.hostname/Room specific id
        room = fromJID.bare().toString()
        return if not @messageFromRoom room

        # Try to resolve the private JID
        privateChatJID = @resolvePrivateJID(stanza)

        # Keep the room JID to private JID map in this class as there
        # is an initialization race condition between the presence messages
        # and the brain initial load.
        # See https://github.com/github/hubot/issues/619
        @roomToPrivateJID[fromJID.toString()] = privateChatJID?.toString()
        @robot.logger.debug "Available received from #{fromJID.toString()} in room #{room} and private chat jid is #{privateChatJID?.toString()}"

        # Use the resource part from the room jid as this
        # is more likelly the user's name
        user = @robot.brain.userForId(fromJID.resource,
          room: room,
          jid: fromJID.toString(),
          privateChatJID: privateChatJID?.toString())

        # Xmpp sends presence for every person in a room, when join it
        # Only after we've heard our own presence should we respond to
        # presence messages.
        @receive new EnterMessage user unless not @heardOwnPresence

      when 'unavailable'
        [room, user] = stanza.attrs.from.split '/'

        # ignore presence messages that sometimes get broadcast
        return if not @messageFromRoom room

        # ignore our own messages in rooms
        return if user == @options.username

        @robot.logger.debug "Unavailable received from #{user} in room #{room}"

        user = @robot.brain.userForId user, room: room
        @receive new LeaveMessage(user)

  # Accept a stanza from a group chat
  # return privateJID (instanceof Xmpp.JID) or the
  # http://jabber.org/protocol/muc#user extension was not provided
  resolvePrivateJID: ( stanza ) ->
    jid = new Xmpp.JID(stanza.attrs.from)

    # room presence in group chat uses a jid which is not the real user jid
    # To send private message to a user seen in a groupchat,
    # you need to get the real jid. If the groupchat is configured to do so,
    # the real jid is also sent as an extension
    # http://xmpp.org/extensions/xep-0045.html#enter-nonanon
    privateJID = stanza.getChild('x', 'http://jabber.org/protocol/muc#user')?.getChild?('item')?.attrs?.jid

    unless privateJID
      unless @anonymousGroupChatWarningLogged
        @robot.logger.warning "Could not get private JID from group chat. Make sure the server is configured to broadcast real jid for groupchat (see http://xmpp.org/extensions/xep-0045.html#enter-nonanon)"
        @anonymousGroupChatWarningLogged = true
      return null

    return new Xmpp.JID(privateJID)

  # Checks that the room parameter is a room the bot is in.
  messageFromRoom: (room) ->
    for joined in @options.rooms
      return true if joined.jid.toUpperCase() == room.toUpperCase()
    return false

  send: (envelope, messages...) ->
    for msg in messages
      @robot.logger.debug "Sending to #{envelope.room}: #{msg}"

      to = envelope.room
      if envelope.user?.type in ['direct', 'chat']
        to = envelope.user.privateChatJID ? "#{envelope.room}/#{envelope.user.name}"

      params =
        # Send a real private chat if we know the real private JID,
        # else, send to the groupchat JID but in private mode
        # Note that if the original message was not a group chat
        # message, envelope.user.privateChatJID will be
        # set to the JID from that private message
        to: to
        type: envelope.user?.type or 'groupchat'

      # Xmpp.Element type
      if msg.attrs?
        message = msg.root()
        message.attrs.to ?= params.to
        message.attrs.type ?= params.type
      else
        message = new Xmpp.Element('message', params).
                  c('body').t(msg)

      @client.send message

  reply: (envelope, messages...) ->
    for msg in messages
      # Xmpp.Element?
      if msg.attrs?
        @send envelope, msg
      else
        @send envelope, "#{envelope.user.name}: #{msg}"

  topic: (envelope, strings...) ->
    string = strings.join "\n"

    message = new Xmpp.Element('message',
                to: envelope.room
                type: envelope.user.type
              ).
              c('subject').t(string)

    @client.send message

  offline: =>
    @robot.logger.debug "Received offline event"
    clearInterval(@keepaliveInterval)

exports.use = (robot) ->
  new XmppBot robot

