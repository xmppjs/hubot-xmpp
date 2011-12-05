Bot = require '../src/xmpp'
assert = require 'assert'

describe 'XmppBot', () ->
  describe '#parseRooms()', () ->
    bot = Bot.use()

    it 'should split passwords', () ->
      rooms = ['secretroom:password', 'room']
      result = bot.parseRooms rooms

      assert.equal result.length, 2
      assert.equal result[0].jid, 'secretroom'
      assert.equal result[0].password, 'password'

      assert.equal result[1].jid, 'room'
      assert.equal result[1].password, ''

  describe '#readMessage()', () ->
    stanza = ''
    bot = Bot.use()
    bot.options =
      username: 'bot'
      rooms: ['test@example.com']

    bot.receive = () ->
      throw new Error 'bad'

    bot.robot =
      name: 'bot'
      userForId: () ->
        user =
          id: 1

    # start with a valid message
    beforeEach () ->
      stanza =
        attrs:
          type: 'chat'
          from: 'test@example.com/ernie'
        getChild: () ->
          body = 
            getText: () ->
              'message text'

    it 'should refuse types', () ->
      stanza.attrs.type = 'other'
      assert.strictEqual bot.readMessage(stanza), undefined

    it 'should ignore messages from self', () ->
      bot.options.username = 'bot'
      stanza.attrs.from = 'room@example.com/bot'
      assert.strictEqual bot.readMessage(stanza), undefined

    it 'should ignore messages from the room', () ->
      stanza.attrs.from = 'test@example.com'
      assert.strictEqual bot.readMessage(stanza), undefined

    it 'should ignore messages with no body', () ->
      stanza.getChild = () ->
        ''
      assert.strictEqual bot.readMessage(stanza), undefined

    it 'should ignore messages we sent part 2', () ->
      stanza.attrs.from = 'test@example.com/bot'
      assert.strictEqual bot.readMessage(stanza), undefined

    it 'should send a message', (done) ->
      bot.receive = (message) ->
        assert.equal message.user.room, 'test@example.com'
        assert.equal message.user.type, 'chat'
        assert.equal message.text, 'message text'
        done()
      bot.readMessage stanza

  describe '#reply()', () ->
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


