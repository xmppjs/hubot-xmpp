Bot = require '../src/xmpp'
Xmpp = require 'node-xmpp'

{Adapter,Robot,EnterMessage,LeaveMessage} = require 'hubot'

assert = require 'assert'

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

  describe '#leaveRoom()', ->
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
      bot.leaveRoom room

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
        userForId: ->
          user =
            id: 1
      logger:
        debug: () ->

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
      stanza.attrs.from = 'room@example.com/bot'
      assert.strictEqual bot.readMessage(stanza), undefined

    it 'should ignore messages from the room', ->
      stanza.attrs.from = 'test@example.com'
      assert.strictEqual bot.readMessage(stanza), undefined

    it 'should ignore messages with no body', ->
      stanza.getChild = () ->
        ''
      assert.strictEqual bot.readMessage(stanza), undefined

    it 'should ignore messages we sent part 2', ->
      stanza.attrs.from = 'test@example.com/bot'
      assert.strictEqual bot.readMessage(stanza), undefined

    it 'should send a message', (done) ->
      bot.receive = (message) ->
        assert.equal message.user.room, 'test@example.com'
        assert.equal message.user.type, 'chat'
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

  describe '#error()', ->
    restoreExit = null

    bot = Bot.use()
    bot.robot =
      logger:
        error: ->

    before () ->
      restoreExit = process.exit
      process.exit = () ->

    after () ->
      process.exit = restoreExit

    it 'should handle ECONNREFUSED', (done) ->
      process.exit = ->
        assert.ok 'exit was called'
        done()
      error =
        code: 'ECONNREFUSED'
      bot.error error

    it 'should handle system-shutdown', (done) ->
      process.exit = ->
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
    robot =
      name: 'bot'
      logger:
        debug: ->

    bot = Bot.use(robot)
    bot.options =
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
      bot.userForId = (id, user) ->
        assert.equal id, 'mark'
        user
      bot.readPresence stanza

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
      stanza =
        attrs:
          type: 'available'
          to: 'bot@example.com'
          from: 'test@example.com/bot'

      bot.readPresence stanza
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

      bot.readPresence stanza

    it 'should call @receive when someone joins', () ->
      bot.heardOwnPresence = true

      bot.receive = (msg) ->
        assert.ok msg instanceof EnterMessage
        assert.equal msg.user.room, 'test@example.com'

      bot.userForId = (id, user) ->
        assert.equal id, 'mark'
        user

      stanza =
        attrs:
          type: 'available'
          to: 'bot@example.com'
          from: 'test@example.com/mark'

      bot.readPresence stanza

    it 'should call @receive when someone leaves', () ->
      bot.receive = (msg) ->
        assert.ok msg instanceof LeaveMessage
        assert.equal msg.user.room, 'test@example.com'

      bot.userForId = (id, user) ->
        assert.equal id, 'mark'
        user

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

    it 'should send messages directly', (done) ->
      envelope =
        user:
          id: 'mark'
          type: 'direct'
        room: 'test@example.com'

      bot.client.send = (msg) ->
        assert.equal msg.parent.attrs.to, 'test@example.com/mark'
        assert.equal msg.parent.attrs.type, 'direct'
        assert.equal msg.getText(), 'testing'
        done()

      bot.send envelope, 'testing'

    it 'should send messages to the room', (done) ->
      envelope =
        user:
          id: 'mark'
          type: 'groupchat'
        room: 'test@example.com'

      bot.client.send = (msg) ->
        assert.equal msg.parent.attrs.to, 'test@example.com'
        assert.equal msg.parent.attrs.type, 'groupchat'
        assert.equal msg.getText(), 'testing'
        done()

      bot.send envelope, 'testing'

    it 'should accept Xmpp.Element objects as messages', (done) ->
      envelope =
        user:
          id: 'mark'
          type: 'groupchat'
        room: 'test@example.com'

      el = new Xmpp.Element('message').c('body')
        .t('testing')

      bot.client.send = (msg) ->
        assert.equal msg.root().attrs.to, 'test@example.com'
        assert.equal msg.root().attrs.type, 'groupchat'
        assert.equal msg.root().getText(), el.root().getText()
        done()

      bot.send envelope, el
