var Bot, assert;
Bot = require('../src/xmpp');
assert = require('assert');
describe('XmppBot', function() {
  return describe('#parseRooms()', function() {
    var bot;
    bot = Bot.use();
    return it('should split passwords', function() {
      var result, rooms;
      rooms = ['secretroom:password', 'room'];
      result = bot.parseRooms(rooms);
      assert.equal(result.length, 2);
      assert.equal(result[0].jid, 'secretroom');
      assert.equal(result[0].password, 'password');
      assert.equal(result[1].jid, 'room');
      return assert.equal(result[1].password, '');
    });
  });
});