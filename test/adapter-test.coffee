Bot = require '../src/xmpp'
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

  describe '#readMessage()', ->
    stanza = ''
    bot = Bot.use()
    bot.options =
      username: 'bot'
      rooms: ['test@example.com']

    bot.receive = ->
      throw new Error 'bad'

    bot.robot =
      name: 'bot'
      userForId: ->
        user =
          id: 1

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
    user =
      name: 'mark'

    it 'should call send()', (done) ->
      bot.send = (user, message) ->
        assert.equal message, 'mark: one'
        done()
      bot.reply user, 'one'

    it 'should call send() multiple times', (done) ->
      called = 0
      bot.send = (user, message) ->
        called += 1
        done() if called == 2
      bot.reply user, 'one', 'two'

  describe '#topic()', ->
    bot = Bot.use()
    bot.client =
      stub: 'xmpp client'

    user =
      name: 'mark'
      room: 'test@example.com'

    it 'should call @client.send()', (done) ->
      bot.client.send = (message) ->
        assert.equal message.parent.attrs.to, user.room
        assert.equal 'test', message.children[0]
        done()
      bot.topic user, 'test'

    it 'should call @client.send() with newlines', (done) ->
      bot.client.send = (message) ->
        assert.equal "one\ntwo", message.children[0]
        done()
      bot.topic user, 'one', 'two'

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
      bot.read(stanza)

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
      logger:
        debug: ->

    bot = Bot.use(robot)
    bot.options =
      rooms: ['test@example.com']
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
          from: 'mark@example.com/456'
          id: '12345'
      bot.userForId = (id, user) ->
        assert.equal user.name, 'mark'
        user
      bot.readPresence stanza



