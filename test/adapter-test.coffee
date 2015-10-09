Bot = require '../src/xmpp'
XmppClient = require 'node-xmpp-client'
ltx = XmppClient.ltx

{Adapter,Robot,EnterMessage,LeaveMessage,TextMessage} = require 'hubot'

assert = require 'assert'
sinon  = require 'sinon'

describe 'XmppBot', ->
  describe '#parseRooms()', ->
    bot = Bot.use()

    it 'should split passwords', ->
      rooms = ['secretroom:password', 'room']
      result = bot.parseRooms rooms

      assert.equal result.length, 2
      assert.equal result[0].jid, 'secretroom'
      assert.equal result[0].password, 'password'

      assert.equal result[1].jid, 'room'
      assert.equal result[1].password, ''

  describe '#joinRoom()', ->
    bot = Bot.use()

    bot.client =
      stub: 'xmpp client'

    bot.robot =
      name: 'bot'
      logger:
        debug: () ->
    room =
      jid: 'test@example.com'
      password: false

    it 'should call @client.send()', (done) ->
      bot.client.send = (message) ->
        done()
      bot.joinRoom room

    it 'should call @client.send() with the appropriate protocol message', (done) ->
      bot.client.send = (message) ->
        assert.equal message.name, 'x'
        assert.equal message.attrs.xmlns, 'http://jabber.org/protocol/muc'
        assert.ok message.parent
        assert.equal message.parent.name, 'presence'
        assert.equal message.parent.attrs.to, "#{room.jid}/#{bot.robot.name}"
        assert.equal message.parent.attrs.type, undefined
        assert.equal message.children.length, 1
        assert.equal message.children[0].name, 'history'
        assert.equal message.children[0].attrs.seconds, 1
        done()
      bot.joinRoom room

    describe 'and the room requires a password', ->
      protectedRoom =
        jid: 'test@example.com'
        password: 'password'

      it 'should call @client.send() with the password', (done) ->
        bot.client.send = (message) ->
          assert.equal message.name, 'x'
          assert.equal message.children.length, 2
          assert.equal message.children[1].name, 'password'
          assert.equal message.children[1].children[0], protectedRoom.password
          done()
        bot.joinRoom protectedRoom

  describe '#ping()', ->
    bot = Bot.use()
    bot.client =
      stub: 'xmpp client'

    room =
      jid: 'test@example.com'
      password: false

    beforeEach ->
      bot.options =
        rooms: [room]
      bot.robot =
        name: 'bot'
        logger:
          debug: () ->

    it 'should call @client.send() with a proper ping element', (done) ->
      bot.client.send = (message) ->
        assert.equal message.name, 'iq'
        assert.equal message.attrs.type, 'get'
        done()
      bot.ping()

  describe '#leaveRoom()', ->
    bot = Bot.use()
    bot.client =
      stub: 'xmpp client'

    room =
      jid: 'test@example.com'
      password: false

    beforeEach ->
      bot.options =
        rooms: [room]
      bot.robot =
        name: 'bot'
        logger:
          debug: () ->

    it 'should call @client.send()', (done) ->
      bot.client.send = (message) ->
        done()
      bot.leaveRoom room
      assert.deepEqual [], bot.options.rooms

    it 'should call @client.send() with a presence element', (done) ->
      bot.client.send = (message) ->
        assert.equal message.name, 'presence'
        done()
      bot.leaveRoom room

    it 'should call @client.send() with the room and bot name', (done) ->
      bot.client.send = (message) ->
        assert.equal message.attrs.to, "#{room.jid}/#{bot.robot.name}"
        done()
      bot.leaveRoom room

    it 'should call @client.send() with type unavailable', (done) ->
      bot.client.send = (message) ->
        assert.equal message.attrs.type, 'unavailable'
        done()
      bot.leaveRoom room

  describe '#readIq', ->
    stanza = ''
    bot = Bot.use()
    bot.client =
      stub: 'xmpp client'
    bot.client.send = ->
      throw new Error "shouldn't have called send."

    bot.robot =
      name: 'bot'
      userForId: ->
        user =
          id: 1
      logger:
        debug: () ->

    beforeEach ->
      stanza =
        attrs:
          type: 'get'
          from: 'test@example.com/ernie'
          to:   'user@example.com/element84'
          id:   '1234'
        children: [ { name: 'query' }]

    it 'should ignore non-ping iqs', ->
      assert.strictEqual bot.readIq(stanza), undefined

    it 'should reply to ping iqs with a pong result', (done) ->
      stanza.children = [ { name: 'ping' } ]
      bot.client.send = (pong) ->
        assert.equal pong.name, 'iq'
        assert.equal pong.attrs.to, stanza.attrs.from
        assert.equal pong.attrs.from, stanza.attrs.to
        assert.equal pong.attrs.id, stanza.attrs.id
        assert.equal pong.attrs.type, 'result'
        done()
      bot.readIq stanza

    it 'should parse room query iqs for users in the room', (done) ->
      stanza.attrs.id = 'get_users_in_room_8139nj32ma'
      stanza.attrs.from = 'test@example.com'
      userItems = [
        { attrs: {name: 'mark'} },
        { attrs: {name: 'anup'} }
      ]
      stanza.children = [ {children: userItems} ]
      bot.on "completedRequest#{stanza.attrs.id}", (usersInRoom) ->
        assert.deepEqual usersInRoom, (item.attrs.name for item in userItems)
        done()
      bot.readIq stanza

  describe '#readMessage()', ->
    stanza = ''
    bot = Bot.use()
    bot.options =
      username: 'bot'
      rooms: [ {jid:'test@example.com', password: false} ]

    bot.receive = ->
      throw new Error 'bad'

    bot.robot =
      name: 'bot'
      brain:
        userForId: (id, options)->
          user = {}
          user['name'] = id
          for k of (options or {})
            user[k] = options[k]
          return user
      logger:
        debug: () ->
        warning: () ->

    # start with a valid message
    beforeEach ->
      stanza =
        attrs:
          type: 'chat'
          from: 'test@example.com/ernie'
        getChild: ->
          body =
            getText: ->
              'message text'

    it 'should refuse types', ->
      stanza.attrs.type = 'other'
      assert.strictEqual bot.readMessage(stanza), undefined

    it 'should ignore messages from self', ->
      bot.options.username = 'bot'
      # Only need to ignore message from self in groupchat
      stanza.attrs.type = 'groupchat'
      stanza.attrs.from = 'room@example.com/bot'
      assert.strictEqual bot.readMessage(stanza), undefined

    it 'should ignore messages from the room', ->
      stanza.attrs.type = 'groupchat'
      stanza.attrs.from = 'test@example.com'
      assert.strictEqual bot.readMessage(stanza), undefined

    it 'should ignore messages with no body', ->
      stanza.getChild = () ->
        ''
      assert.strictEqual bot.readMessage(stanza), undefined

    it 'should ignore messages we sent part 2', ->
      stanza.attrs.type = 'groupchat'
      stanza.attrs.from = 'test@example.com/bot'
      assert.strictEqual bot.readMessage(stanza), undefined

    it 'should send a message for private message', (done) ->
      bot.receive = (message) ->
        assert.equal message.user.type, 'chat'
        assert.equal message.user.name, 'test'
        assert.equal message.user.privateChatJID, 'test@example.com/ernie'
        assert.equal message.user.room, undefined
        assert.equal message.text, 'message text'
        done()
      bot.readMessage stanza

    it 'should send a message (with bot name prefix added) for private message', (done) ->
      bot.options.pmAddPrefix = true
      bot.receive = (message) ->
        assert.equal message.user.type, 'chat'
        assert.equal message.user.name, 'test'
        assert.equal message.user.privateChatJID, 'test@example.com/ernie'
        assert.equal message.user.room, undefined
        assert.equal message.text, 'bot message text'
        done()
      bot.readMessage stanza

    it 'should send a message (with bot name prefix) for private message (with bot name prefix)', (done) ->
      stanza.getChild = () ->
          body =
            getText: ->
              'bot message text'
      bot.options.pmAddPrefix = true
      bot.receive = (message) ->
        assert.equal message.user.type, 'chat'
        assert.equal message.user.name, 'test'
        assert.equal message.user.privateChatJID, 'test@example.com/ernie'
        assert.equal message.user.room, undefined
        assert.equal message.text, 'bot message text'
        done()
      bot.readMessage stanza

    it 'should send a message (with alias prefix) for private message (with alias prefix)', (done) ->
      process.env.HUBOT_ALIAS = ':'
      stanza.getChild = () ->
          body =
            getText: ->
              ':message text'
      bot.options.pmAddPrefix = true
      bot.receive = (message) ->
        assert.equal message.user.type, 'chat'
        assert.equal message.user.name, 'test'
        assert.equal message.user.privateChatJID, 'test@example.com/ernie'
        assert.equal message.user.room, undefined
        assert.equal message.text, ':message text'
        done()
      bot.readMessage stanza

    it 'should send a message for groupchat', (done) ->
      stanza.attrs.type = 'groupchat'
      bot.receive = (message) ->
        assert.equal message.user.type, 'groupchat'
        assert.equal message.user.name, 'ernie'
        assert.equal message.user.room, 'test@example.com'
        assert.equal message.text, 'message text'
        done()
      bot.readMessage stanza

  describe '#reply()', ->
    bot = Bot.use()
    envelope =
      user:
        name: 'mark'

    it 'should call send()', (done) ->
      bot.send = (envelope, message) ->
        assert.equal message, 'mark: one'
        done()
      bot.reply envelope, 'one'

    it 'should call send() multiple times', (done) ->
      called = 0
      bot.send = (envelope, message) ->
        called += 1
        done() if called == 2
      bot.reply envelope, 'one', 'two'

  describe '#topic()', ->
    bot = Bot.use()
    bot.client =
      stub: 'xmpp client'

    envelope =
      user:
        name: 'mark'
      room: 'test@example.com'

    it 'should call @client.send()', (done) ->
      bot.client.send = (message) ->
        assert.equal message.parent.attrs.to, envelope.room
        assert.equal 'test', message.children[0]
        done()
      bot.topic envelope, 'test'

    it 'should call @client.send() with newlines', (done) ->
      bot.client.send = (message) ->
        assert.equal "one\ntwo", message.children[0]
        done()
      bot.topic envelope, 'one', 'two'

  describe '#getUsersInRoom()', ->
    bot = Bot.use()

    bot.client =
      stub: 'xmpp client'

    bot.robot =
      name: 'bot'
      logger:
        debug: () ->

    bot.options =
      username: 'bot@example.com'

    room =
      jid: 'test@example.com'
      password: false

    it 'should call @client.send()', (done) ->
      bot.client.send = (message) ->
        assert.equal message.attrs.from, bot.options.username
        assert.equal (message.attrs.id.startsWith 'get_users_in_room'), true
        assert.equal message.attrs.to, room.jid
        assert.equal message.attrs.type, 'get'
        assert.equal message.children[0].name, 'query'
        assert.equal message.children[0].attrs.xmlns, 'http://jabber.org/protocol/disco#items'
        done()
      bot.getUsersInRoom room, () ->

    it 'should call callback on receiving users', (done) ->
      users  = ['mark', 'anup']
      requestId = 'get_users_in_room_8139nj32ma'
      bot.client.send = () ->
      callback = (usersInRoom) ->
        assert.deepEqual usersInRoom, users
        done()
      bot.getUsersInRoom room, callback, requestId
      bot.emit "completedRequest#{requestId}", users

  describe '#sendInvite()', ->
    bot = Bot.use()

    bot.client =
      stub: 'xmpp client'

    bot.robot =
      name: 'bot'
      logger:
        debug: () ->

    room =
      jid: 'test@example.com'
      password: false
    invitee = 'anup@example.com'
    reason = 'Inviting to test'

    it 'should call @client.send()', (done) ->
      bot.client.send = (message) ->
        assert.equal message.attrs.to, invitee
        assert.equal message.children[0].attrs.jid, room.jid
        assert.equal message.children[0].attrs.reason, reason
        done()
      bot.sendInvite room, invitee, reason

  describe '#error()', ->
    bot = Bot.use()
    bot.robot =
      logger:
        error: ->

    before () ->
      bot.robot =
        logger:
          error: ->

    it 'should handle ECONNREFUSED', (done) ->
      bot.robot.logger.error = ->
        assert.ok 'error logging happened.'
        done()
      error =
        code: 'ECONNREFUSED'
      bot.error error

    it 'should handle system-shutdown', (done) ->
      bot.robot.logger.error = ->
        assert.ok 'exit was called'
        done()
      error =
        children: [ {name: 'system-shutdown'} ]
      bot.error error

  describe '#read()', ->
    bot = Bot.use()
    bot.robot =
      logger:
        error: ->

    it 'should log errors', (done) ->
      bot.robot.logger.error = (message) ->
        text = String(message)
        assert.ok(text.indexOf('xmpp error') > 0)
        assert.ok(text.indexOf('fail') > 0)
        done()
      stanza =
        attrs:
          type: 'error'
        toString: ->
          'fail'
      bot.read stanza

    it 'should delegate to readMessage', (done) ->
      stanza =
        attrs:
          type: 'chat'
        name: 'message'
      bot.readMessage = (arg) ->
        assert.equal arg.name, stanza.name
        done()
      bot.read stanza

    it 'should delegate to readPresence', (done) ->
      stanza =
        attrs:
          type: 'chat'
        name: 'presence'
      bot.readPresence = (arg) ->
        assert.equal arg.name, stanza.name
        done()
      bot.read stanza

  describe '#readPresence()', ->
    robot = null
    bot = null
    beforeEach () ->
      robot =
        name: 'bot'
        logger:
          debug: ->
        brain:
          userForId: (id, options)->
            user = {}
            user['name'] = id
            for k of (options or {})
              user[k] = options[k]
            return user
      bot = Bot.use(robot)
      bot.options =
        username: 'bot'
        rooms: [ {jid: 'test@example.com', password: false} ]
      bot.client =
        send: ->

    it 'should handle subscribe types', (done) ->
      stanza =
        attrs:
          type: 'subscribe'
          to: 'bot@example.com'
          from: 'room@example.com/mark'
          id: '12345'
      bot.client.send = (el) ->
        assert.equal el.attrs.from, stanza.attrs.to
        assert.equal el.attrs.to, stanza.attrs.from
        assert.equal el.attrs.type, 'subscribed'
        done()
      bot.readPresence stanza

    it 'should handle probe types', (done) ->
      stanza =
        attrs:
          type: 'probe'
          to: 'bot@example.com'
          from: 'room@example.com/mark'
          id: '12345'
      bot.client.send = (el) ->
        assert.equal el.attrs.from, stanza.attrs.to
        assert.equal el.attrs.to, stanza.attrs.from
        assert.equal el.attrs.type, undefined
        done()
      bot.readPresence stanza

    it 'should do nothing on missing item in available type', () ->
      stanza =
        attrs:
          type: 'available'
          to: 'bot@example.com'
          from: 'room@example.com/mark'
          id: '12345'
      tmp_userForId = robot.brain.userForId
      robot.brain.userForId = (id, user) ->
        assert.equal id, 'mark'
        user
      bot.readPresence stanza
      robot.brain.userForId = tmp_userForId

    it 'should not trigger @recieve for presences coming from a room the bot is not in', () ->
      bot.receive = (msg) ->
        throw new Error('should not get here')

      stanza =
        attrs:
          type: 'available'
          to: 'bot@example.com'
          from: 'room@example.com/mark'
          id: '12345'
      bot.readPresence stanza

    it 'should set @heardOwnPresence when the bot presence is received', () ->
      stanza1 =
        attrs:
          type: 'available'
          to: 'bot@example.com'
          from: 'test@example.com/bot'
        getChild: ->
          stub =
            getChild: ->
              stub =
                attrs:
                  jid: 'bot@example.com'

      stanza2 =
        attrs:
          type: 'available'
          to: 'bot@example.com'
          from: 'test@example.com/2578936351142164331380805'
        getChild: ->
          stub =
            getText: ->
              stub = 'bot'

      bot.readPresence stanza1
      assert.ok bot.heardOwnPresence
      bot.heardOwnPresence = false
      bot.readPresence stanza2
      assert.ok bot.heardOwnPresence

    # Don't trigger enter messages in a room, until we get our
    # own enter message.
    it 'should not send event if we have not heard our own presence', () ->
      bot.heardOwnPresence = false
      bot.receive = (msg) ->
        throw new Error('Should not send a message yet')

      stanza =
        attrs:
          type: 'available'
          to: 'bot@example.com'
          from: 'test@example.com/mark'
        getChild: ->
          x =
            getChild: ->
              {} =
                attrs:
                  jid: 'bot@example.com'

      bot.readPresence stanza

    it 'should call @receive when someone joins', () ->
      bot.heardOwnPresence = true

      bot.receive = (msg) ->
        assert.ok msg instanceof EnterMessage
        assert.equal msg.user.name, 'mark'
        assert.equal msg.user.room, 'test@example.com'
        assert.equal msg.user.privateChatJID, 'mark@example.com/mark'

      stanza =
        attrs:
          type: 'available'
          to: 'bot@example.com'
          from: 'test@example.com/mark'
        getChild: ->
          x =
            getChild: ->
              {} =
                attrs:
                  jid: 'mark@example.com/mark'

      bot.readPresence stanza

    it 'should call @receive when someone leaves', () ->
      bot.receive = (msg) ->
        assert.ok msg instanceof LeaveMessage
        assert.equal msg.user.room, 'test@example.com'

      stanza =
        attrs:
          type: 'unavailable'
          to: 'bot@example.com'
          from: 'test@example.com/mark'

      bot.readPresence stanza

  describe '#send()', () ->
    bot = Bot.use()
    bot.options =
      username: 'bot'
      rooms: [ {jid:'test@example.com', password: false} ]

    bot.client =
      send: ->

    bot.robot =
      logger:
        debug: ->

    it 'should use type groupchat if type is undefined', (done) ->
      envelope =
        user:
          id: 'mark'
        room: 'test@example.com'

      bot.client.send = (msg) ->
        assert.equal msg.parent.attrs.to, 'test@example.com'
        assert.equal msg.parent.attrs.type, 'groupchat'
        assert.equal msg.getText(), 'testing'
        done()

      bot.send envelope, 'testing'

    it 'should send messages directly when message was private', (done) ->
      envelope =
        user:
          id: 'mark'
          type: 'direct'
          privateChatJID: 'mark@example.com'
        room: null

      bot.client.send = (msg) ->
        assert.equal msg.parent.attrs.to, 'mark@example.com'
        assert.equal msg.parent.attrs.type, 'direct'
        assert.equal msg.getText(), 'testing'
        done()

      bot.send envelope, 'testing'

    it 'should send messages directly when message was from groupchat and real JID was provided', (done) ->
      envelope =
        user:
          id: 'room@example.com/mark'
          type: 'direct'
          privateChatJID: 'mark@example.com'
        room: 'room@example.com'

      bot.client.send = (msg) ->
        assert.equal msg.parent.attrs.to, 'mark@example.com'
        assert.equal msg.parent.attrs.type, 'direct'
        assert.equal msg.getText(), 'testing'
        done()

      bot.send envelope, 'testing'

    it 'should send a message to private room JID when message was from groupchat and real JID was not provided', (done) ->
      envelope =
        user:
          name: 'mark'
          room: 'room@example.com'
          type: 'direct'
        room: 'room@example.com'

      bot.client.send = (msg) ->
        assert.equal msg.parent.attrs.to, 'room@example.com/mark'
        assert.equal msg.parent.attrs.type, 'direct'
        assert.equal msg.getText(), 'testing'
        done()

      bot.send envelope, 'testing'

    it 'should send messages to the room', (done) ->
      envelope =
        user:
          name: 'mark'
          type: 'groupchat'
        room: 'test@example.com'

      bot.client.send = (msg) ->
        assert.equal msg.parent.attrs.to, 'test@example.com'
        assert.equal msg.parent.attrs.type, 'groupchat'
        assert.equal msg.getText(), 'testing'
        done()

      bot.send envelope, 'testing'

    it 'should accept ltx.Element objects as messages', (done) ->
      envelope =
        user:
          name: 'mark'
          type: 'groupchat'
        room: 'test@example.com'

      el = new ltx.Element('message').c('body')
        .t('testing')

      bot.client.send = (msg) ->
        assert.equal msg.root().attrs.to, 'test@example.com'
        assert.equal msg.root().attrs.type, 'groupchat'
        assert.equal msg.root().getText(), el.root().getText()
        done()

      bot.send envelope, el

    it 'should send XHTML messages to the room', (done) ->
      envelope =
        user:
          name: 'mark'
          type: 'groupchat'
        room: 'test@example.com'

      bot.client.send = (msg) ->
        assert.equal msg.root().attrs.to, 'test@example.com'
        assert.equal msg.root().attrs.type, 'groupchat'
        assert.equal msg.root().children[0].getText(), "<p><span style='color: #0000ff;'>testing</span></p>"
        assert.equal msg.parent.parent.name, 'html'
        assert.equal msg.parent.parent.attrs.xmlns, 'http://jabber.org/protocol/xhtml-im'
        assert.equal msg.parent.name, 'body'
        assert.equal msg.parent.attrs.xmlns, 'http://www.w3.org/1999/xhtml'
        assert.equal msg.name, 'p'
        assert.equal msg.children[0].name, 'span'
        assert.equal msg.children[0].attrs.style, 'color: #0000ff;'
        assert.equal msg.children[0].getText(), 'testing'

        done()

      bot.send envelope, "<p><span style='color: #0000ff;'>testing</span></p>"

  describe '#online', () ->
    bot = null
    beforeEach () ->
      bot = Bot.use()
      bot.options =
        username: 'mybot@example.com'
        rooms: [ {jid:'test@example.com', password: false} ]

      bot.client =
        connection:
          socket:
            setTimeout: () ->
            setKeepAlive: () ->
        send: ->

      bot.robot =
        name: 'bert'
        logger:
          debug: () ->
          info: () ->

    it 'should emit connected event', (done) ->
      callCount = 0
      bot.on 'connected', () ->
        assert.equal callCount, expected.length, 'Call count is wrong'
        done()

      expected = [
        (msg) ->
          root = msg.tree()
          assert.equal 'presence', msg.name, 'Element name is incorrect'
          nick = root.getChild 'nick'
          assert.equal 'bert', nick.getText()
        ,
        (msg) ->
          root = msg.tree()
          assert.equal 'presence', root.name, 'Element name is incorrect'
          assert.equal "test@example.com/bert", root.attrs.to, 'Msg sent to wrong room'
      ]

      bot.client.send = (msg) ->
        expected[callCount](msg) if expected[callCount]
        callCount++

      bot.online()

    it 'should emit reconnected when connected', (done) ->
      bot.connected = true

      bot.on 'reconnected', () ->
        assert.ok bot.connected
        done()

      bot.online()

  describe 'privateChatJID', ->
    bot = null
    beforeEach () ->
      bot = Bot.use()

      bot.heardOwnPresence = true

      bot.options =
        username: 'bot'
        rooms: [ {jid:'test@example.com', password: false} ]

      bot.client =
        send: ->

      bot.robot =
        name: 'bot'
        on: () ->
        brain:
          userForId: (id, options)->
            user = {}
            user['name'] = id
            for k of (options or {})
              user[k] = options[k]
            return user
        logger:
          debug: () ->
          warning: () ->
          info: () ->

    it 'should add private jid to user when presence contains http://jabber.org/protocol/muc#user', (done) ->
      # Send presence stanza with real jid sub element
      bot.receive = (msg) ->
        return
      stanza =
        attrs:
          type: 'available'
          to: 'bot@example.com'
          from: 'test@example.com/mark'
        getChild: ->
          stub =
            getChild: ->
              stub =
                attrs:
                  jid: 'mark@example.com/mark'
      bot.readPresence stanza

      # Send a groupchat message and check that the private JID was retreived
      stanza =
        attrs:
          type: 'groupchat'
          from: 'test@example.com/mark'
        getChild: ->
          body =
            getText: ->
              'message text'
      bot.receive = (msg) ->
        assert.ok msg instanceof TextMessage
        assert.equal msg.user.name, 'mark'
        assert.equal msg.user.room, 'test@example.com'
        assert.equal msg.user.privateChatJID, 'mark@example.com/mark'
        done()
      bot.readMessage stanza

    it 'should not fail when presence does not contain http://jabber.org/protocol/muc#user', (done) ->
      # Send presence stanza without real jid subelement
      bot.receive = (msg) ->
        return
      stanza =
        attrs:
          type: 'available'
          to: 'bot@example.com'
          from: 'test@example.com/mark'
        getChild: ->
          undefined
      bot.readPresence stanza

      # Send a groupchat message and check that the private JID is undefined but message is sent through
      stanza =
        attrs:
          type: 'groupchat'
          from: 'test@example.com/mark'
        getChild: ->
          body =
            getText: ->
              'message text'
      bot.receive = (msg) ->
        assert.ok msg instanceof TextMessage
        assert.equal msg.user.name, 'mark'
        assert.equal msg.user.room, 'test@example.com'
        assert.equal msg.user.privateChatJID, undefined
        done()
      bot.readMessage stanza

  describe '#configClient', ->
    bot = null
    clock = null
    options =
      keepaliveInterval: 30000

    beforeEach () ->
      clock = sinon.useFakeTimers()
      bot = Bot.use()
      bot.client =
        connection:
          socket: {}
        on: ->
        send: ->

    afterEach () ->
      clock.restore()

    it 'should set timeouts', () ->
      bot.client.connection.socket.setTimeout = (val) ->
        assert.equal 0, val, 'Should be 0'
      bot.ping = sinon.stub()

      bot.configClient(options)

      clock.tick(options.keepaliveInterval)
      assert(bot.ping.called)

    it 'should set event listeners', () ->
      bot.client.connection.socket.setTimeout = ->

      onCalls = []
      bot.client.on = (event, cb) ->
        onCalls.push(event)
      bot.configClient(options)

      expected = ['error', 'online', 'offline', 'stanza', 'end']
      assert.deepEqual onCalls, expected

  describe '#reconnect', () ->
    bot = clock = mock = null

    beforeEach () ->
      bot = Bot.use()
      bot.robot =
        logger:
          error: sinon.stub()
      bot.client =
        removeListener: ->
      clock = sinon.useFakeTimers()

    afterEach () ->
      clock.restore()
      mock.restore() if mock

    it 'should attempt a reconnect and increment retry count', (done) ->
      bot.makeClient = () ->
        assert.ok true, 'Attempted to make a new client'
        done()

      assert.equal 0, bot.reconnectTryCount
      bot.reconnect()
      assert.equal 1, bot.reconnectTryCount, 'No time elapsed'
      clock.tick 5001

    it 'should exit after 5 tries', () ->
      mock = sinon.mock(process)
      mock.expects('exit').once()

      bot.reconnectTryCount = 5
      bot.reconnect()

      mock.verify()
      assert.ok bot.robot.logger.error.called
