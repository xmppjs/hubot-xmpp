/*
 * decaffeinate suggestions:
 * DS101: Remove unnecessary use of Array.from
 * DS102: Remove unnecessary code created because of implicit returns
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const Bot = require('../src/xmpp');
const {Element} = require('node-xmpp-client');

const {Adapter,Robot,EnterMessage,LeaveMessage} = require('hubot');

const assert = require('assert');
const sinon  = require('sinon');
const uuid = require('uuid');

describe('XmppBot', function() {
  describe('#parseRooms()', function() {
    const bot = Bot.use();

    return it('should split passwords', function() {
      const rooms = ['secretroom:password', 'room'];
      const result = bot.parseRooms(rooms);

      assert.equal(result.length, 2);
      assert.equal(result[0].jid, 'secretroom');
      assert.equal(result[0].password, 'password');

      assert.equal(result[1].jid, 'room');
      return assert.equal(result[1].password, '');
    });
  });

  describe('#joinRoom()', function() {
    const bot = Bot.use();

    bot.client =
      {stub: 'xmpp client'};

    bot.robot = {
      name: 'bot',
      logger: {
        debug() {}
      }
    };
    const room = {
      jid: 'test@example.com',
      password: false
    };

    it('should call @client.send()', function(done) {
      bot.client.send = message => done();
      return bot.joinRoom(room);
    });

    it('should call @client.send() with the appropriate protocol message', function(done) {
      bot.client.send = function(message) {
        assert.equal(message.name, 'x');
        assert.equal(message.attrs.xmlns, 'http://jabber.org/protocol/muc');
        assert.ok(message.parent);
        assert.equal(message.parent.name, 'presence');
        assert.equal(message.parent.attrs.to, `${room.jid}/${bot.robot.name}`);
        assert.equal(message.parent.attrs.type, undefined);
        assert.equal(message.children.length, 1);
        assert.equal(message.children[0].name, 'history');
        assert.equal(message.children[0].attrs.seconds, 1);
        return done();
      };
      return bot.joinRoom(room);
    });

    return describe('and the room requires a password', function() {
      const protectedRoom = {
        jid: 'test@example.com',
        password: 'password'
      };

      return it('should call @client.send() with the password', function(done) {
        bot.client.send = function(message) {
          assert.equal(message.name, 'x');
          assert.equal(message.children.length, 2);
          assert.equal(message.children[1].name, 'password');
          assert.equal(message.children[1].children[0], protectedRoom.password);
          return done();
        };
        return bot.joinRoom(protectedRoom);
      });
    });
  });

  describe('#ping()', function() {
    const bot = Bot.use();
    bot.client =
      {stub: 'xmpp client'};

    const room = {
      jid: 'test@example.com',
      password: false
    };

    beforeEach(function() {
      bot.options =
        {rooms: [room]};
      return bot.robot = {
        name: 'bot',
        logger: {
          debug() {}
        }
      };
    });

    return it('should call @client.send() with a proper ping element', function(done) {
      bot.client.send = function(message) {
        assert.equal(message.name, 'iq');
        assert.equal(message.attrs.type, 'get');
        return done();
      };
      return bot.ping();
    });
  });

  describe('#leaveRoom()', function() {
    const bot = Bot.use();
    bot.client =
      {stub: 'xmpp client'};

    const room = {
      jid: 'test@example.com',
      password: false
    };

    beforeEach(function() {
      bot.options =
        {rooms: [room]};
      return bot.robot = {
        name: 'bot',
        logger: {
          debug() {}
        }
      };
    });

    it('should call @client.send()', function(done) {
      bot.client.send = message => done();
      bot.leaveRoom(room);
      return assert.deepEqual([], bot.options.rooms);
    });

    it('should call @client.send() with a presence element', function(done) {
      bot.client.send = function(message) {
        assert.equal(message.name, 'presence');
        return done();
      };
      return bot.leaveRoom(room);
    });

    it('should call @client.send() with the room and bot name', function(done) {
      bot.client.send = function(message) {
        assert.equal(message.attrs.to, `${room.jid}/${bot.robot.name}`);
        return done();
      };
      return bot.leaveRoom(room);
    });

    return it('should call @client.send() with type unavailable', function(done) {
      bot.client.send = function(message) {
        assert.equal(message.attrs.type, 'unavailable');
        return done();
      };
      return bot.leaveRoom(room);
    });
  });

  describe('#readIq', function() {
    let stanza = '';
    const bot = Bot.use();
    bot.client =
      {stub: 'xmpp client'};
    bot.client.send = function() {
      throw new Error("shouldn't have called send.");
    };

    bot.robot = {
      name: 'bot',
      userForId() {
        let user;
        return user =
          {id: 1};
      },
      logger: {
        debug() {}
      }
    };

    beforeEach(() => stanza = {
      attrs: {
        type: 'get',
        from: 'test@example.com/ernie',
        to:   'user@example.com/element84',
        id:   '1234'
      },
      children: [ { name: 'query' }]
    });

    it('should ignore non-ping iqs', () => assert.strictEqual(bot.readIq(stanza), undefined));

    it('should reply to ping iqs with a pong result', function(done) {
      stanza.children = [ { name: 'ping' } ];
      bot.client.send = function(pong) {
        assert.equal(pong.name, 'iq');
        assert.equal(pong.attrs.to, stanza.attrs.from);
        assert.equal(pong.attrs.from, stanza.attrs.to);
        assert.equal(pong.attrs.id, stanza.attrs.id);
        assert.equal(pong.attrs.type, 'result');
        return done();
      };
      return bot.readIq(stanza);
    });

    return it('should parse room query iqs for users in the room', function(done) {
      stanza.attrs.id = 'get_users_in_room_8139nj32ma';
      stanza.attrs.from = 'test@example.com';
      const userItems = [
        { attrs: {name: 'mark'} },
        { attrs: {name: 'anup'} }
      ];
      stanza.children = [ {children: userItems} ];
      bot.on(`completedRequest${stanza.attrs.id}`, function(usersInRoom) {
        assert.deepEqual(usersInRoom, (Array.from(userItems).map((item) => item.attrs.name)));
        return done();
      });
      return bot.readIq(stanza);
    });
  });

  describe('#readMessage()', function() {
    let stanza = '';
    const bot = Bot.use();
    bot.options = {
      username: 'bot',
      rooms: [ {jid:'test@example.com', password: false} ]
    };

    bot.receive = function() {
      throw new Error('bad');
    };

    bot.robot = {
      name: 'bot',
      brain: {
        userForId(id, options){
          const user = {};
          user['name'] = id;
          for (let k in (options || {})) {
            user[k] = options[k];
          }
          return user;
        }
      },
      logger: {
        debug() {},
        warning() {}
      }
    };

    // start with a valid message
    beforeEach(() => stanza = {
      attrs: {
        type: 'chat',
        from: 'test@example.com/ernie'
      },
      getChild() {
        let body;
        return body = {
          getText() {
            return 'message text';
          }
        };
      }
    });

    it('should refuse types', function() {
      stanza.attrs.type = 'other';
      return assert.strictEqual(bot.readMessage(stanza), undefined);
    });

    it('should ignore messages from self', function() {
      bot.options.username = 'bot';
      // Only need to ignore message from self in groupchat
      stanza.attrs.type = 'groupchat';
      stanza.attrs.from = 'room@example.com/bot';
      return assert.strictEqual(bot.readMessage(stanza), undefined);
    });

    it('should ignore messages from the room', function() {
      stanza.attrs.type = 'groupchat';
      stanza.attrs.from = 'test@example.com';
      return assert.strictEqual(bot.readMessage(stanza), undefined);
    });

    it('should ignore messages with no body', function() {
      stanza.getChild = () => '';
      return assert.strictEqual(bot.readMessage(stanza), undefined);
    });

    it('should ignore messages we sent part 2', function() {
      stanza.attrs.type = 'groupchat';
      stanza.attrs.from = 'test@example.com/bot';
      return assert.strictEqual(bot.readMessage(stanza), undefined);
    });

    it('should send a message for private message', function(done) {
      bot.receive = function(message) {
        assert.equal(message.user.type, 'chat');
        assert.equal(message.user.name, 'test');
        assert.equal(message.user.privateChatJID, 'test@example.com/ernie');
        assert.equal(message.user.room, undefined);
        assert.equal(message.text, 'message text');
        return done();
      };
      return bot.readMessage(stanza);
    });

    it('should send a message (with bot name prefix added) for private message', function(done) {
      bot.options.pmAddPrefix = true;
      bot.receive = function(message) {
        assert.equal(message.user.type, 'chat');
        assert.equal(message.user.name, 'test');
        assert.equal(message.user.privateChatJID, 'test@example.com/ernie');
        assert.equal(message.user.room, undefined);
        assert.equal(message.text, 'bot message text');
        return done();
      };
      return bot.readMessage(stanza);
    });

    it('should send a message (with bot name prefix) for private message (with bot name prefix)', function(done) {
      stanza.getChild = function() {
          let body;
          return body = {
            getText() {
              return 'bot message text';
            }
          };
        };
      bot.options.pmAddPrefix = true;
      bot.receive = function(message) {
        assert.equal(message.user.type, 'chat');
        assert.equal(message.user.name, 'test');
        assert.equal(message.user.privateChatJID, 'test@example.com/ernie');
        assert.equal(message.user.room, undefined);
        assert.equal(message.text, 'bot message text');
        return done();
      };
      return bot.readMessage(stanza);
    });

    it('should send a message (with alias prefix) for private message (with alias prefix)', function(done) {
      process.env.HUBOT_ALIAS = ':';
      stanza.getChild = function() {
          let body;
          return body = {
            getText() {
              return ':message text';
            }
          };
        };
      bot.options.pmAddPrefix = true;
      bot.receive = function(message) {
        assert.equal(message.user.type, 'chat');
        assert.equal(message.user.name, 'test');
        assert.equal(message.user.privateChatJID, 'test@example.com/ernie');
        assert.equal(message.user.room, undefined);
        assert.equal(message.text, ':message text');
        return done();
      };
      return bot.readMessage(stanza);
    });

    return it('should send a message for groupchat', function(done) {
      stanza.attrs.type = 'groupchat';
      bot.receive = function(message) {
        assert.equal(message.user.type, 'groupchat');
        assert.equal(message.user.name, 'ernie');
        assert.equal(message.user.room, 'test@example.com');
        assert.equal(message.text, 'message text');
        return done();
      };
      return bot.readMessage(stanza);
    });
  });

  describe('#reply()', function() {
    const bot = Bot.use();
    const envelope = {
      user: {
        name: 'mark'
      }
    };

    it('should call send()', function(done) {
      bot.send = function(envelope, message) {
        assert.equal(message, 'mark: one');
        return done();
      };
      return bot.reply(envelope, 'one');
    });

    return it('should call send() multiple times', function(done) {
      let called = 0;
      bot.send = function(envelope, message) {
        called += 1;
        if (called === 2) { return done(); }
      };
      return bot.reply(envelope, 'one', 'two');
    });
  });

  describe('#topic()', function() {
    const bot = Bot.use();
    bot.client =
      {stub: 'xmpp client'};

    const envelope = {
      user: {
        name: 'mark'
      },
      room: 'test@example.com'
    };

    it('should call @client.send()', function(done) {
      bot.client.send = function(message) {
        assert.equal(message.parent.attrs.to, envelope.room);
        assert.equal('test', message.children[0]);
        return done();
      };
      return bot.topic(envelope, 'test');
    });

    return it('should call @client.send() with newlines', function(done) {
      bot.client.send = function(message) {
        assert.equal("one\ntwo", message.children[0]);
        return done();
      };
      return bot.topic(envelope, 'one', 'two');
    });
  });

  describe('#getUsersInRoom()', function() {
    const bot = Bot.use();

    bot.client =
      {stub: 'xmpp client'};

    bot.robot = {
      name: 'bot',
      logger: {
        debug() {}
      }
    };

    bot.options =
      {username: 'bot@example.com'};

    const room = {
      jid: 'test@example.com',
      password: false
    };

    it('should call @client.send()', function(done) {
      bot.client.send = function(message) {
        assert.equal(message.attrs.from, bot.options.username);
        assert.equal((message.attrs.id.startsWith('get_users_in_room')), true);
        assert.equal(message.attrs.to, room.jid);
        assert.equal(message.attrs.type, 'get');
        assert.equal(message.children[0].name, 'query');
        assert.equal(message.children[0].attrs.xmlns, 'http://jabber.org/protocol/disco#items');
        return done();
      };
      return bot.getUsersInRoom(room, function() {});
    });

    return it('should call callback on receiving users', function(done) {
      const users  = ['mark', 'anup'];
      const requestId = 'get_users_in_room_8139nj32ma';
      bot.client.send = function() {};
      const callback = function(usersInRoom) {
        assert.deepEqual(usersInRoom, users);
        return done();
      };
      bot.getUsersInRoom(room, callback, requestId);
      return bot.emit(`completedRequest${requestId}`, users);
    });
  });

  describe('#sendInvite()', function() {
    const bot = Bot.use();

    bot.client =
      {stub: 'xmpp client'};

    bot.robot = {
      name: 'bot',
      logger: {
        debug() {}
      }
    };

    const room = {
      jid: 'test@example.com',
      password: false
    };
    const invitee = 'anup@example.com';
    const reason = 'Inviting to test';

    return it('should call @client.send()', function(done) {
      bot.client.send = function(message) {
        assert.equal(message.attrs.to, invitee);
        assert.equal(message.children[0].attrs.jid, room.jid);
        assert.equal(message.children[0].attrs.reason, reason);
        return done();
      };
      return bot.sendInvite(room, invitee, reason);
    });
  });

  describe('#error()', function() {
    const bot = Bot.use();
    bot.robot = {
      logger: {
        error() {}
      }
    };

    before(() => bot.robot = {
      logger: {
        error() {}
      }
    });

    it('should handle ECONNREFUSED', function(done) {
      bot.robot.logger.error = function() {
        assert.ok('error logging happened.');
        return done();
      };
      const error =
        {code: 'ECONNREFUSED'};
      return bot.error(error);
    });

    return it('should handle system-shutdown', function(done) {
      bot.robot.logger.error = function() {
        assert.ok('exit was called');
        return done();
      };
      const error =
        {children: [ {name: 'system-shutdown'} ]};
      return bot.error(error);
    });
  });

  describe('#read()', function() {
    const bot = Bot.use();
    bot.robot = {
      logger: {
        error() {}
      }
    };

    it('should log errors', function(done) {
      bot.robot.logger.error = function(message) {
        const text = String(message);
        assert.ok(text.indexOf('xmpp error') > 0);
        assert.ok(text.indexOf('fail') > 0);
        return done();
      };
      const stanza = {
        attrs: {
          type: 'error'
        },
        toString() {
          return 'fail';
        }
      };
      return bot.read(stanza);
    });

    it('should delegate to readMessage', function(done) {
      const stanza = {
        attrs: {
          type: 'chat'
        },
        name: 'message'
      };
      bot.readMessage = function(arg) {
        assert.equal(arg.name, stanza.name);
        return done();
      };
      return bot.read(stanza);
    });

    return it('should delegate to readPresence', function(done) {
      const stanza = {
        attrs: {
          type: 'chat'
        },
        name: 'presence'
      };
      bot.readPresence = function(arg) {
        assert.equal(arg.name, stanza.name);
        return done();
      };
      return bot.read(stanza);
    });
  });

  describe('#readPresence()', function() {
    let robot = null;
    let bot = null;
    beforeEach(function() {
      robot = {
        name: 'bot',
        logger: {
          debug() {}
        },
        brain: {
          userForId(id, options){
            const user = {};
            user['name'] = id;
            for (let k in (options || {})) {
              user[k] = options[k];
            }
            return user;
          }
        }
      };
      bot = Bot.use(robot);
      bot.options = {
        username: 'bot',
        rooms: [ {jid: 'test@example.com', password: false} ]
      };
      return bot.client =
        {send() {}};
    });

    it('should handle subscribe types', function(done) {
      const stanza = {
        attrs: {
          type: 'subscribe',
          to: 'bot@example.com',
          from: 'room@example.com/mark',
          id: '12345'
        }
      };
      bot.client.send = function(el) {
        assert.equal(el.attrs.from, stanza.attrs.to);
        assert.equal(el.attrs.to, stanza.attrs.from);
        assert.equal(el.attrs.type, 'subscribed');
        return done();
      };
      return bot.readPresence(stanza);
    });

    it('should handle probe types', function(done) {
      const stanza = {
        attrs: {
          type: 'probe',
          to: 'bot@example.com',
          from: 'room@example.com/mark',
          id: '12345'
        }
      };
      bot.client.send = function(el) {
        assert.equal(el.attrs.from, stanza.attrs.to);
        assert.equal(el.attrs.to, stanza.attrs.from);
        assert.equal(el.attrs.type, undefined);
        return done();
      };
      return bot.readPresence(stanza);
    });

    it('should do nothing on missing item in available type', function() {
      const stanza = {
        attrs: {
          type: 'available',
          to: 'bot@example.com',
          from: 'room@example.com/mark',
          id: '12345'
        }
      };
      const tmp_userForId = robot.brain.userForId;
      robot.brain.userForId = function(id, user) {
        assert.equal(id, 'mark');
        return user;
      };
      bot.readPresence(stanza);
      return robot.brain.userForId = tmp_userForId;
    });

    it('should not trigger @recieve for presences coming from a room the bot is not in', function() {
      bot.receive = function(msg) {
        throw new Error('should not get here');
      };

      const stanza = {
        attrs: {
          type: 'available',
          to: 'bot@example.com',
          from: 'room@example.com/mark',
          id: '12345'
        }
      };
      return bot.readPresence(stanza);
    });

    it('should set @heardOwnPresence when the bot presence is received', function() {
      const stanza1 = {
        attrs: {
          type: 'available',
          to: 'bot@example.com',
          from: 'test@example.com/bot'
        },
        getChild() {
          let stub;
          return stub = {
            getChild() {
              return stub = {
                attrs: {
                  jid: 'bot@example.com'
                }
              };
            }
          };
        }
      };

      const stanza2 = {
        attrs: {
          type: 'available',
          to: 'bot@example.com',
          from: 'test@example.com/2578936351142164331380805'
        },
        getChild() {
          let stub;
          return stub = {
            getText() {
              return stub = 'bot';
            }
          };
        }
      };

      bot.readPresence(stanza1);
      assert.ok(bot.heardOwnPresence);
      bot.heardOwnPresence = false;
      bot.readPresence(stanza2);
      return assert.ok(bot.heardOwnPresence);
    });

    // FIXME decaffeinate failed to compile these
    // # Don't trigger enter messages in a room, until we get our
    // # own enter message.
    // it 'should not send event if we have not heard our own presence', () ->
    //   bot.heardOwnPresence = false
    //   bot.receive = (msg) ->
    //     throw new Error('Should not send a message yet')

    //   stanza =
    //     attrs:
    //       type: 'available'
    //       to: 'bot@example.com'
    //       from: 'test@example.com/mark'
    //     getChild: ->
    //       x =
    //         getChild: ->
    //           {} =
    //             attrs:
    //               jid: 'bot@example.com'

    //   bot.readPresence stanza

    // it 'should call @receive when someone joins', () ->
    //   bot.heardOwnPresence = true

    //   bot.receive = (msg) ->
    //     assert.equal msg.user.name, 'mark'
    //     assert.equal msg.user.room, 'test@example.com'
    //     assert.equal msg.user.privateChatJID, 'mark@example.com/mark'

    //   stanza =
    //     attrs:
    //       type: 'available'
    //       to: 'bot@example.com'
    //       from: 'test@example.com/mark'
    //     getChild: ->
    //       x =
    //         getChild: ->
    //           {} =
    //             attrs:
    //               jid: 'mark@example.com/mark'

    //   bot.readPresence stanza

    return it('should call @receive when someone leaves', function() {
      bot.receive = msg => assert.equal(msg.user.room, 'test@example.com');

      const stanza = {
        attrs: {
          type: 'unavailable',
          to: 'bot@example.com',
          from: 'test@example.com/mark'
        }
      };

      return bot.readPresence(stanza);
    });
  });

  describe('#send()', function() {
    const bot = Bot.use();
    bot.options = {
      username: 'bot',
      rooms: [ {jid:'test@example.com', password: false} ]
    };

    bot.client =
      {send() {}};

    bot.robot = {
      logger: {
        debug() {}
      }
    };

    it('should use type groupchat if type is undefined', function(done) {
      const envelope = {
        user: {
          id: 'mark'
        },
        room: 'test@example.com'
      };

      bot.client.send = function(msg) {
        assert.equal(msg.parent.attrs.to, 'test@example.com');
        assert.equal(msg.parent.attrs.type, 'groupchat');
        assert.equal(msg.getText(), 'testing');
        return done();
      };

      return bot.send(envelope, 'testing');
    });

    it('should send messages directly when message was private', function(done) {
      const envelope = {
        user: {
          id: 'mark',
          type: 'direct',
          privateChatJID: 'mark@example.com'
        },
        room: null
      };

      bot.client.send = function(msg) {
        assert.equal(msg.parent.attrs.to, 'mark@example.com');
        assert.equal(msg.parent.attrs.type, 'direct');
        assert.equal(msg.getText(), 'testing');
        return done();
      };

      return bot.send(envelope, 'testing');
    });

    it('should send messages directly when message was from groupchat and real JID was provided', function(done) {
      const envelope = {
        user: {
          id: 'room@example.com/mark',
          type: 'direct',
          privateChatJID: 'mark@example.com'
        },
        room: 'room@example.com'
      };

      bot.client.send = function(msg) {
        assert.equal(msg.parent.attrs.to, 'mark@example.com');
        assert.equal(msg.parent.attrs.type, 'direct');
        assert.equal(msg.getText(), 'testing');
        return done();
      };

      return bot.send(envelope, 'testing');
    });

    it('should send a message to private room JID when message was from groupchat and real JID was not provided', function(done) {
      const envelope = {
        user: {
          name: 'mark',
          room: 'room@example.com',
          type: 'direct'
        },
        room: 'room@example.com'
      };

      bot.client.send = function(msg) {
        assert.equal(msg.parent.attrs.to, 'room@example.com/mark');
        assert.equal(msg.parent.attrs.type, 'direct');
        assert.equal(msg.getText(), 'testing');
        return done();
      };

      return bot.send(envelope, 'testing');
    });

    it('should send messages to the room', function(done) {
      const envelope = {
        user: {
          name: 'mark',
          type: 'groupchat'
        },
        room: 'test@example.com'
      };

      bot.client.send = function(msg) {
        assert.equal(msg.parent.attrs.to, 'test@example.com');
        assert.equal(msg.parent.attrs.type, 'groupchat');
        assert.equal(msg.getText(), 'testing');
        return done();
      };

      return bot.send(envelope, 'testing');
    });

    it('should accept ltx.Element objects as messages', function(done) {
      const envelope = {
        user: {
          name: 'mark',
          type: 'groupchat'
        },
        room: 'test@example.com'
      };

      const el = new Element('message').c('body')
        .t('testing');

      bot.client.send = function(msg) {
        assert.equal(msg.root().attrs.to, 'test@example.com');
        assert.equal(msg.root().attrs.type, 'groupchat');
        assert.equal(msg.root().getText(), el.root().getText());
        return done();
      };

      return bot.send(envelope, el);
    });

    return it('should send XHTML messages to the room', function(done) {
      const envelope = {
        user: {
          name: 'mark',
          type: 'groupchat'
        },
        room: 'test@example.com'
      };

      bot.client.send = function(msg) {
        assert.equal(msg.root().attrs.to, 'test@example.com');
        assert.equal(msg.root().attrs.type, 'groupchat');
        assert.equal(msg.root().children[0].getText(), "<p><span style='color: #0000ff;'>testing</span></p>");
        assert.equal(msg.parent.parent.name, 'html');
        assert.equal(msg.parent.parent.attrs.xmlns, 'http://jabber.org/protocol/xhtml-im');
        assert.equal(msg.parent.name, 'body');
        assert.equal(msg.parent.attrs.xmlns, 'http://www.w3.org/1999/xhtml');
        assert.equal(msg.name, 'p');
        assert.equal(msg.children[0].name, 'span');
        assert.equal(msg.children[0].attrs.style, 'color: #0000ff;');
        assert.equal(msg.children[0].getText(), 'testing');

        return done();
      };

      return bot.send(envelope, "<p><span style='color: #0000ff;'>testing</span></p>");
    });
  });

  describe('#online', function() {
    let bot = null;
    beforeEach(function() {
      bot = Bot.use();
      bot.options = {
        username: 'mybot@example.com',
        rooms: [ {jid:'test@example.com', password: false} ]
      };

      bot.client = {
        connection: {
          socket: {
            setTimeout() {},
            setKeepAlive() {}
          }
        },
        send() {}
      };

      return bot.robot = {
        name: 'bert',
        logger: {
          debug() {},
          info() {}
        }
      };
    });

    it('should emit connected event', function(done) {
      let callCount = 0;
      bot.on('connected', function() {
        assert.equal(callCount, expected.length, 'Call count is wrong');
        return done();
      });

      var expected = [
        function(msg) {
          const root = msg.tree();
          assert.equal('presence', msg.name, 'Element name is incorrect');
          const nick = root.getChild('nick');
          return assert.equal('bert', nick.getText());
        }
        ,
        function(msg) {
          const root = msg.tree();
          assert.equal('presence', root.name, 'Element name is incorrect');
          return assert.equal("test@example.com/bert", root.attrs.to, 'Msg sent to wrong room');
        }
      ];

      bot.client.send = function(msg) {
        if (expected[callCount]) { expected[callCount](msg); }
        return callCount++;
      };

      return bot.online();
    });

    return it('should emit reconnected when connected', function(done) {
      bot.connected = true;

      bot.on('reconnected', function() {
        assert.ok(bot.connected);
        return done();
      });

      return bot.online();
    });
  });

  describe('privateChatJID', function() {
    let bot = null;
    beforeEach(function() {
      bot = Bot.use();

      bot.heardOwnPresence = true;

      bot.options = {
        username: 'bot',
        rooms: [ {jid:'test@example.com', password: false} ]
      };

      bot.client =
        {send() {}};

      return bot.robot = {
        name: 'bot',
        on() {},
        brain: {
          userForId(id, options){
            const user = {};
            user['name'] = id;
            for (let k in (options || {})) {
              user[k] = options[k];
            }
            return user;
          }
        },
        logger: {
          debug() {},
          warning() {},
          info() {}
        }
      };
    });

    it('should add private jid to user when presence contains http://jabber.org/protocol/muc#user', function(done) {
      // Send presence stanza with real jid sub element
      bot.receive = function(msg) {
      };
      let stanza = {
        attrs: {
          type: 'available',
          to: 'bot@example.com',
          from: 'test@example.com/mark'
        },
        getChild() {
          let stub;
          return stub = {
            getChild() {
              return stub = {
                attrs: {
                  jid: 'mark@example.com/mark'
                }
              };
            }
          };
        }
      };
      bot.readPresence(stanza);

      // Send a groupchat message and check that the private JID was retreived
      stanza = {
        attrs: {
          type: 'groupchat',
          from: 'test@example.com/mark'
        },
        getChild() {
          let body;
          return body = {
            getText() {
              return 'message text';
            }
          };
        }
      };
      bot.receive = function(msg) {
        assert.equal(msg.user.name, 'mark');
        assert.equal(msg.user.room, 'test@example.com');
        assert.equal(msg.user.privateChatJID, 'mark@example.com/mark');
        return done();
      };
      return bot.readMessage(stanza);
    });

    return it('should not fail when presence does not contain http://jabber.org/protocol/muc#user', function(done) {
      // Send presence stanza without real jid subelement
      bot.receive = function(msg) {
      };
      let stanza = {
        attrs: {
          type: 'available',
          to: 'bot@example.com',
          from: 'test@example.com/mark'
        },
        getChild() {
          return undefined;
        }
      };
      bot.readPresence(stanza);

      // Send a groupchat message and check that the private JID is undefined but message is sent through
      stanza = {
        attrs: {
          type: 'groupchat',
          from: 'test@example.com/mark'
        },
        getChild() {
          let body;
          return body = {
            getText() {
              return 'message text';
            }
          };
        }
      };
      bot.receive = function(msg) {
        assert.equal(msg.user.name, 'mark');
        assert.equal(msg.user.room, 'test@example.com');
        assert.equal(msg.user.privateChatJID, undefined);
        return done();
      };
      return bot.readMessage(stanza);
    });
  });

  describe('#configClient', function() {
    let bot = null;
    let clock = null;
    const options =
      {keepaliveInterval: 30000};

    beforeEach(function() {
      clock = sinon.useFakeTimers();
      bot = Bot.use();
      return bot.client = {
        connection: {
          socket: {}
        },
        on() {},
        send() {}
      };
    });

    afterEach(() => clock.restore());

    it('should set timeouts', function() {
      bot.client.connection.socket.setTimeout = val => assert.equal(0, val, 'Should be 0');
      bot.ping = sinon.stub();

      bot.configClient(options);

      clock.tick(options.keepaliveInterval);
      return assert(bot.ping.called);
    });

    return it('should set event listeners', function() {
      bot.client.connection.socket.setTimeout = function() {};

      const onCalls = [];
      bot.client.on = (event, cb) => onCalls.push(event);
      bot.configClient(options);

      const expected = ['error', 'online', 'offline', 'stanza', 'end'];
      return assert.deepEqual(onCalls, expected);
    });
  });

  describe('#reconnect', function() {
    let clock, mock;
    let bot = (clock = (mock = null));

    beforeEach(function() {
      bot = Bot.use();
      bot.robot = {
        logger: {
          error: sinon.stub()
        }
      };
      bot.client =
        {removeListener() {}};
      return clock = sinon.useFakeTimers();
    });

    afterEach(function() {
      clock.restore();
      if (mock) { return mock.restore(); }
    });

    it('should attempt a reconnect and increment retry count', function(done) {
      bot.makeClient = function() {
        assert.ok(true, 'Attempted to make a new client');
        return done();
      };

      assert.equal(0, bot.reconnectTryCount);
      bot.options = {reconnectTry: 5};
      bot.reconnect();
      assert.equal(1, bot.reconnectTryCount, 'No time elapsed');
      return clock.tick(5001);
    });

    return it('should exit after 5 tries', function() {
      mock = sinon.mock(process);
      mock.expects('exit').once();

      bot.options = {reconnectTry: 5};
      bot.reconnectTryCount = 5;
      bot.reconnect();

      mock.verify();
      return assert.ok(bot.robot.logger.error.called);
    });
  });

  return describe('uuid_on_join', function() {
    beforeEach(function() {
      uuid['v4'] = () => 'fake-uuid-for-testing';
      return process.env.HUBOT_XMPP_UUID_ON_JOIN = true;
    });

    const bot = Bot.use();

    bot.client =
      {stub: 'xmpp client'};

    bot.robot = {
      name: 'bot',
      logger: {
        debug() {},
        info() {}
      },
      brain: {
        userForId(id, options){
          const user = {};
          user['name'] = id;
          for (let k in (options || {})) {
            user[k] = options[k];
          }
          return user;
        }
      }
    };

    const room = {
      jid: 'test@example.com',
      password: false
    };

    it('should call @client.send() with a uuid', function(done) {
      bot.client.send = function(message) {
        if (message.name === 'body') {
          assert.equal(message.children.length, 1);
          assert.equal(message.children[0], 'fake-uuid-for-testing');
          return done();
        }
      };
      return bot.joinRoom(room);
    });

    it('should ignore messages', function(done) {
      const stanza = {
        attrs: {
          type: 'groupchat'
        },
        name: 'message',
        flag: 'ignore_me'
      };
      const proxied = bot.readMessage.bind(bot);
      bot.readMessage = function(message) {
        proxied(message);
        if (message.flag === 'ignore_me') {
          return done();
        }
      };
      bot.receive = function(message) {
        throw 'no message should be received';
      };
      return bot.read(stanza);
    });

    it('listen for the uuid before responding', function(done) {
      const stanza = {
        attrs: {
          type: 'groupchat',
          from: 'test@example.com/bot'
        },
        name: 'message',
        flag: 'join_me',
        getChild() {
          let body;
          return body = {
            getText() {
              return 'fake-uuid-for-testing';
            }
          };
        }
      };
      const proxied = bot.readMessage.bind(bot);
      bot.readMessage = function(message) {
        proxied(message);
        assert.equal(true, Array.from(bot.joined).includes('test@example.com'));
        if (message.flag === 'join_me') {
          return done();
        }
      };
      bot.receive = function(message) {
        throw 'no message should be received';
      };
      return bot.read(stanza);
    });

    return it('should process messages after joining', function(done) {
      const stanza = {
        attrs: {
          type: 'groupchat',
          from: 'test@example.com/someone'
        },
        name: 'message',
        getChild() {
          let body;
          return body = {
            getText() {
              return '@bot howdy';
            }
          };
        }
      };
      bot.receive = function(message) {
        assert.equal(message, '@bot howdy');
        return done();
      };
      return bot.read(stanza);
    });
  });
});
