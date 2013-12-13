{Adapter,Robot,TextMessage,EnterMessage,LeaveMessage} = require 'hubot'

Xmpp    = require 'node-xmpp'
util    = require 'util'

class XmppBot extends Adapter
  
  # Flag to log a warning message about group chat configuration only once
  anonymousGroupChatWarningLogged = false
  
  run: ->
    options =
      username: process.env.HUBOT_XMPP_USERNAME
      password: '********'
      host: process.env.HUBOT_XMPP_HOST
      port: process.env.HUBOT_XMPP_PORT
      rooms:    @parseRooms process.env.HUBOT_XMPP_ROOMS.split(',')
      keepaliveInterval: 30000 # ms interval to send whitespace to xmpp server
      legacySSL: process.env.HUBOT_XMPP_LEGACYSSL
      preferredSaslMechanism: process.env.HUBOT_XMPP_PREFERRED_SASL_MECHANISM

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

    @client.send new Xmpp.Element('presence')
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

      el = new Xmpp.Element('presence', to: "#{room.jid}/#{@robot.name}" )
      x = el.c('x', xmlns: 'http://jabber.org/protocol/muc' )
      x.c('history', seconds: 1 ) # prevent the server from confusing us with old messages
                                  # and it seems that servers don't reliably support maxchars
                                  # or zero values
      if (room.password) then x.c('password').t(room.password)
      return x

  # XMPP Leaving a room - http://xmpp.org/extensions/xep-0045.html#exit
  leaveRoom: (room) ->
    @client.send do =>
      @robot.logger.debug "Leaving #{room.jid}/#{@robot.name}"

      return new Xmpp.Element('presence', to: "#{room.jid}/#{@robot.name}", type: 'unavailable' )

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

    # Some servers use iq pings to make sure the client is still functional.  We need
    # to reply or we'll get kicked out of rooms we've joined.
    if (stanza.attrs.type == 'get' && stanza.children[0].name == 'ping')
      pong = new Xmpp.Element('iq',
        to: stanza.attrs.from
        from: stanza.attrs.to
        type: 'result'
        id: stanza.attrs.id
      )

      @robot.logger.debug "[sending pong] #{pong}"
      @client.send pong

  readMessage: (stanza) =>
    # ignore non-messages
    return if stanza.attrs.type not in ['groupchat', 'direct', 'chat']

    # ignore empty bodies (i.e., topic changes -- maybe watch these someday)
    body = stanza.getChild 'body'
    return unless body

    message = body.getText()
    
    if stanza.attrs.type == 'groupchat'
      [room, from] = resolvePrivateJID(stanza)?
      # Fallback to the groupchat jif if the real jid was not sent
      from = new Xmpp.JID(stanza.attrs.from) unless from
    else
      from = new Xmpp.JID(stanza.attrs.from)
      
    @robot.logger.debug "Received message: #{message} in room: #{room}, from: #{jid.toString()}"

    # ignore our own messages in rooms
    # Try with username (if private chat or groupchat jid was resolved to real one) of fallback on the resource of group chat jid
    return if from is undefined or from.username == @options.username or from.resource == @robot.name

    # note that 'from' in groupchat is not the real users jid. Use privateChatJid in user to send private message
    user = @robot.brain.userForId from
    user.type = stanza.attrs.type
    user.room = room

    @receive new TextMessage(user, message)

  readPresence: (stanza) =>
    jid = new Xmpp.JID(stanza.attrs.from)
    bareJid = jid.bare().toString()

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
        [room, privateChatJid] = resolvePrivateJID(stanza)?
        return unless room
          
        # If the presence is from us, track that.
        # Xmpp sends presence for every person in a room, when join it
        # Only after we've heard our own presence should we respond to
        # presence messages.
        if from.user == @options.username
          @heardOwnPresence = true
          return
        return unless @heardOwnPresence

        @robot.logger.debug "Available received from #{jid.toString()} in room #{room} and is actually #{from.toString()}"

        user = @robot.brain.userForId jid.toString(), room: room, privateChatJid: from.toString()
        @receive new EnterMessage user

      when 'unavailable'
        [room, privateChatJid] = resolvePrivateJID(stanza)?
        return unless room

        # ignore presence messages that sometimes get broadcast
        return if not @messageFromRoom room

        # ignore our own messages in rooms
        return if from == @options.username

        @robot.logger.debug "Unavailable received from #{jid.toString()} in room #{room} and is actually #{from.toString()}"

        user = @robot.brain.userForId jid.toString(), room: room, privateChatJid: from.toString()
        @receive new LeaveMessage(user)

  # Accept a stanza from a group chat
  # return [String: roomname, Xmpp.JID: privateJID] or null if not from a groupchat
  resolvePrivateJID: ( stanza ) ->
    jid = new Xmpp.JID(stanza.attrs.from)
    
    # Group chat jid are of the form room_name@conference.hostname/Room specific id
    room = jid.bare().toString()
    
    # ignore presence messages that sometimes get broadcast
    return null if not @messageFromRoom room
    
    # room presence in group chat uses a jid which is not the real user jid
    # To send private message to a user seen in a groupchat, you need to get the real jid
    # If the groupchat is configured to do so, the real jid is also sent as an extension
    # http://xmpp.org/extensions/xep-0045.html#enter-nonanon
    privateJID = stanza.getChild('x', 'http://jabber.org/protocol/muc#user')?.getChild('item')?.attrs?.jid
    
    unless privateJID
      unless anonymousGroupChatWarningLogged
        @robot.logger.warn "Could not get private JID from group chat. Make sure the server is configured to bradcast real jid for groupchat (see http://xmpp.org/extensions/xep-0045.html#enter-nonanon)"
        anonymousGroupChatWarningLogged = true
      return null
    
    return [room, new Xmpp.JID(privateJID)]
        
  # Checks that the room parameter is a room the bot is in.
  messageFromRoom: (room) ->
    for joined in @options.rooms
      return true if joined.jid == room
    return false

  send: (envelope, messages...) ->
    for msg in messages
      @robot.logger.debug "Sending to #{envelope.room}: #{msg}"

      params =
        # TODO @MacKeeper Use the brain to send a real private chat message
        to: if envelope.user?.type in ['direct', 'chat'] then "#{envelope.room}/#{envelope.user.id}" else envelope.room
        type: envelope.user?.type or 'groupchat'

      if msg.attrs? # Xmpp.Element type
        message = msg.root()
        message.attrs.to ?= params.to
        message.attrs.type ?= params.type
      else
        message = new Xmpp.Element('message', params).
                  c('body').t(msg)

      @client.send message

  reply: (envelope, messages...) ->
    for msg in messages
      if msg.attrs? #Xmpp.Element
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

