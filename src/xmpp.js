'use strict';

/*
 * decaffeinate suggestions:
 * DS102: Remove unnecessary code created because of implicit returns
 * DS103: Rewrite code to no longer use __guard__
 * DS205: Consider reworking code to avoid use of IIFEs
 * DS207: Consider shorter variations of null checks
 * Full docs: https://github.com/decaffeinate/decaffeinate/blob/master/docs/suggestions.md
 */
const {Adapter,Robot,TextMessage,EnterMessage,LeaveMessage} = require('hubot/es2015');
const {JID, Stanza, Client, parse, Element} = require('node-xmpp-client');
const uuid = require('uuid/v4');
const util = require('util');

class XmppBot extends Adapter {
  constructor( robot ) {
    super(robot)

    // Flag to log a warning message about group chat configuration only once
    this.anonymousGroupChatWarningLogged = false;

    // Store the room JID to private JID map.
    // Key is the room JID, value is the private JID
    this.roomToPrivateJID = {};
  }

  run() {
    (this.checkCanStart)();

    const options = {
      username: process.env.HUBOT_XMPP_USERNAME,
      password: '********',
      host: process.env.HUBOT_XMPP_HOST,
      port: process.env.HUBOT_XMPP_PORT,
      rooms: this.parseRooms(process.env.HUBOT_XMPP_ROOMS.split(',')),
      // ms interval to send whitespace to xmpp server
      keepaliveInterval: process.env.HUBOT_XMPP_KEEPALIVE_INTERVAL || 30000,
      reconnectTry: process.env.HUBOT_XMPP_RECONNECT_TRY || 5,
      reconnectWait: process.env.HUBOT_XMPP_RECONNECT_WAIT || 5000,
      legacySSL: process.env.HUBOT_XMPP_LEGACYSSL,
      preferredSaslMechanism: process.env.HUBOT_XMPP_PREFERRED_SASL_MECHANISM,
      disallowTLS: process.env.HUBOT_XMPP_DISALLOW_TLS,
      pmAddPrefix: process.env.HUBOT_XMPP_PM_ADD_PREFIX
    };

    this.robot.logger.info(util.inspect(options));
    options.password = process.env.HUBOT_XMPP_PASSWORD;

    this.options = options;
    this.connected = false;
    return this.makeClient();
  }

  // Only try to reconnect 5 times
  reconnect() {
    const {
      options
    } = this;

    this.reconnectTryCount += 1;
    if (this.reconnectTryCount > options.reconnectTry) {
      this.robot.logger.error('Unable to reconnect to jabber server dying.');
      process.exit(1);
    }

    this.client.removeListener('error', this.error);
    this.client.removeListener('online', this.online);
    this.client.removeListener('offline', this.offline);
    this.client.removeListener('stanza', this.read);

    return setTimeout(() => {
      return this.makeClient();
    }
    , options.reconnectWait);
  }

  makeClient() {
    const {
      options
    } = this;

    this.client = new Client({
      reconnect: true,
      jid: options.username,
      password: options.password,
      host: options.host,
      port: options.port,
      legacySSL: options.legacySSL,
      preferred: options.preferredSaslMechanism,
      disallowTLS: options.disallowTLS
    });
    this.configClient(options);
  }

  configClient(options) {
    this.client.connection.socket.setTimeout(0);
    setInterval(this.ping, options.keepaliveInterval);

    this.client.on('error', this.error);
    this.client.on('online', this.online);
    this.client.on('offline', this.offline);
    this.client.on('stanza', this.read);

    this.client.on('end', () => {
      this.robot.logger.info('Connection closed, attempting to reconnect');
      this.reconnect();
    });
  }

  error(error) {
    this.robot.logger.error(`Received error ${error.toString()}`);
  }

  online() {
    this.robot.logger.info('Hubot XMPP client online');

    // Setup keepalive
    this.client.connection.socket.setTimeout(0);
    this.client.connection.socket.setKeepAlive(true, this.options.keepaliveInterval);

    const presence = new Stanza('presence');
    presence.c('nick', {xmlns: 'http://jabber.org/protocol/nick'}).t(this.robot.name);
    this.client.send(presence);
    this.robot.logger.info('Hubot XMPP sent initial presence');

    for (let room of this.options.rooms) { this.joinRoom(room); }

    this.emit(this.connected ? 'reconnected' : 'connected');
    this.connected = true;
    this.reconnectTryCount = 0;
  }

  ping() {
    const ping = new Stanza('iq', {type: 'get', id: this.currentIqId++});
    ping.c('ping', {xmlns: 'urn:xmpp:ping'});

    this.robot.logger.debug(`[sending ping] ${ping}`);
    this.client.send(ping);
  }

  parseRooms(items) {
    const rooms = [];
    for (let room of items) {
      const index = room.indexOf(':');
      rooms.push({
        jid:      room.slice(0, index > 0 ? index : room.length),
        password: index > 0 ? room.slice(index+1) : false
      });
    }
    return rooms;
  }

  // XMPP Joining a room - http://xmpp.org/extensions/xep-0045.html#enter-muc
  joinRoom(room) {
    this.client.send((() => {
      this.robot.logger.debug(`Joining ${room.jid}/${this.robot.name}`);

      // prevent the server from confusing us with old messages
      // and it seems that servers don't reliably support maxchars
      // or zero values
      const el = new Stanza('presence', {to: `${room.jid}/${this.robot.name}`});
      const x = el.c('x', {xmlns: 'http://jabber.org/protocol/muc'});
      x.c('history', {seconds: 1} );

      if (room.password) {
        x.c('password').t(room.password);
      }
      return x;
    }
    )());

    if (process.env.HUBOT_XMPP_UUID_ON_JOIN != null) {
      // send a guid message and ignore any responses until that's been received
      const room_id = uuid();
      const params = {
        to: room.jid,
        type: 'groupchat'
      };
      this.robot.logger.info(`Joining ${room.jid} with ${room_id}`);
      this.joining[room_id] = room.jid;
      this.client.send(new Stanza('message', params).c('body').t(room_id));
    }
  }

  // XMPP Leaving a room - http://xmpp.org/extensions/xep-0045.html#exit
  leaveRoom(room) {
    // messageFromRoom check for joined rooms so remove it from the list
    for (let index = 0; index < this.options.rooms.length; index++) {
      const joined = this.options.rooms[index];
      if (joined.jid === room.jid) {
        this.options.rooms.splice(index, 1);
      }
    }

    return this.client.send((() => {
      this.robot.logger.debug(`Leaving ${room.jid}/${this.robot.name}`);

      return new Stanza('presence', {
        to: `${room.jid}/${this.robot.name}`,
        type: 'unavailable'
      });
    }
    )());
  }

  // Send query for users in the room and once the server response is parsed,
  // apply the callback against the retrieved data.
  // callback should be of the form `(usersInRoom) -> console.log usersInRoom`
  // where usersInRoom is an array of username strings.
  // For normal use, no need to pass requestId: it's there for testing purposes.
  getUsersInRoom(room, callback, requestId) {
    // (pseudo) random string to keep track of the current request
    // Useful in case of concurrent requests
    if (!requestId) {
      requestId = 'get_users_in_room_' + Date.now() + Math.random().toString(36).slice(2);
    }

    // http://xmpp.org/extensions/xep-0045.html#disco-roomitems
    this.client.send((() => {
      this.robot.logger.debug(`Fetching users in the room ${room.jid}`);
      const message = new Stanza('iq', {
        from : this.options.username,
        id: requestId,
        to : room.jid,
        type: 'get'
      });
      message.c('query',
        {xmlns : 'http://jabber.org/protocol/disco#items'});
      return message;
    }
    )());

    // Listen to the event with the current request id, one time only
    return this.once(`completedRequest${requestId}`, callback);
  }

  // XMPP invite to a room, directly - http://xmpp.org/extensions/xep-0249.html
  sendInvite(room, invitee, reason) {
    this.client.send((() => {
      this.robot.logger.debug(`Inviting ${invitee} to ${room.jid}`);
      const message = new Stanza('message',
        {to : invitee});
      message.c('x', {
        xmlns : 'jabber:x:conference',
        jid: room.jid,
        reason
      });
      return message;
    }
    )());
  }

  read(stanza) {
    if (stanza.attrs.type === 'error') {
      this.robot.logger.error('[xmpp error]' + stanza);
      return;
    }

    switch (stanza.name) {
      case 'message':
        return this.readMessage(stanza);
      case 'presence':
        return this.readPresence(stanza);
      case 'iq':
        return this.readIq(stanza);
    }
  }

  readIq(stanza) {
    this.robot.logger.debug(`[received iq] ${stanza}`);

    // Some servers use iq pings to make sure the client is still functional.
    // We need to reply or we'll get kicked out of rooms we've joined.
    if ((stanza.attrs.type === 'get') && (stanza.children[0].name === 'ping')) {
      const pong = new Stanza('iq', {
        to: stanza.attrs.from,
        from: stanza.attrs.to,
        type: 'result',
        id: stanza.attrs.id
      });

      this.robot.logger.debug(`[sending pong] ${pong}`);
      return this.client.send(pong);
    } else if ((stanza.attrs.id != null ? stanza.attrs.id.startsWith('get_users_in_room') : undefined) && stanza.children[0].children) {
      const roomJID = stanza.attrs.from;
      const userItems = stanza.children[0].children;

      // Note that this contains usernames and NOT the full user JID.
      const usersInRoom = userItems.map((item) => item.attrs.name);
      this.robot.logger.debug(`[users in room] ${roomJID} has ${usersInRoom}`);

      return this.emit(`completedRequest${stanza.attrs.id}`, usersInRoom);
    }
  }

  readMessage(stanza) {
    // ignore non-messages
    let privateChatJID, room, user;
    if (!['groupchat', 'direct', 'chat'].includes(stanza.attrs.type)) { return; }
    if (stanza.attrs.from === undefined) { return; }

    // ignore empty bodies (i.e., topic changes -- maybe watch these someday)
    const body = stanza.getChild('body');
    if (!body) { return; }

    const {
      from
    } = stanza.attrs;
    let message = body.getText();

    // check if this is a join guid and if so start accepting messages
    if ((process.env.HUBOT_XMPP_UUID_ON_JOIN != null) && message in this.joining) {
      this.robot.logger.info(`Now accepting messages from ${this.joining[message]}`);
      this.joined.push(this.joining[message]);
    }

    if (stanza.attrs.type === 'groupchat') {
      // Everything before the / is the room name in groupchat JID
      [room, user] = from.split('/');

      // ignore our own messages in rooms or messaged without user part
      if ((user === undefined) || (user === "") || (user === this.robot.name)) { return; }

      // Convert the room JID to private JID if we have one
      privateChatJID = this.roomToPrivateJID[from];

    } else {
      // Not sure how to get the user's alias. Use the username.
      // The resource is not the user's alias but the unique client
      // ID which is often the machine name
      [user] = from.split('@');
      // Not from a room
      room = undefined;
      // Also store the private JID so we can use it in the send method
      privateChatJID = from;
      // For private messages, make the commands work even when they are not prefixed with hubot name or alias
      if (this.options.pmAddPrefix &&
          (message.slice(0, this.robot.name.length).toLowerCase() !== this.robot.name.toLowerCase()) &&
          (message.slice(0, process.env.HUBOT_ALIAS != null ? process.env.HUBOT_ALIAS.length : undefined).toLowerCase() !== (process.env.HUBOT_ALIAS != null ? process.env.HUBOT_ALIAS.toLowerCase() : undefined))) {
        message = `${this.robot.name} ${message}`;
      }
    }

    // note that 'user' isn't a full JID in case of group chat,
    // just the local user part
    // FIXME Not sure it's a good idea to use the groupchat JID resource part
    // as two users could have the same resource in two different rooms.
    // I leave it as-is for backward compatiblity. A better idea would
    // be to use the full groupchat JID.
    user = this.robot.brain.userForId(user);
    user.type = stanza.attrs.type;
    user.room = room;
    if (privateChatJID) { user.privateChatJID = privateChatJID; }

    // only process persistent chant messages if we have matched a join
    if ((process.env.HUBOT_XMPP_UUID_ON_JOIN != null) && (stanza.attrs.type === 'groupchat') && !this.joined.includes(user.room)) { return; }

    this.robot.logger.debug(`Received message: ${message} in room: ${user.room}, from: ${user.name}. Private chat JID is ${user.privateChatJID}`);

    return this.receive(new TextMessage(user, message));
  }

  readPresence(stanza) {
    const fromJID = new JID(stanza.attrs.from);

    // xmpp doesn't add types for standard available mesages
    // note that upon joining a room, server will send available
    // presences for all members
    // http://xmpp.org/rfcs/rfc3921.html#rfc.section.2.2.1
    if (stanza.attrs.type == null) { stanza.attrs.type = 'available'; }

    switch (stanza.attrs.type) {
      case 'subscribe':
        this.robot.logger.debug(`${stanza.attrs.from} subscribed to me`);

        return this.client.send(new Stanza('presence', {
            from: stanza.attrs.to,
            to:   stanza.attrs.from,
            id:   stanza.attrs.id,
            type: 'subscribed'
          }
        )
        );
      case 'probe':
        this.robot.logger.debug(`${stanza.attrs.from} probed me`);

        return this.client.send(new Stanza('presence', {
            from: stanza.attrs.to,
            to:   stanza.attrs.from,
            id:   stanza.attrs.id
          }
        )
        );
      case 'available':
        // If the presence is from us, track that.
        if ((fromJID.resource === this.robot.name) ||
           (__guardMethod__(typeof stanza.getChild === 'function' ? stanza.getChild('nick') : undefined, 'getText', o => o.getText()) === this.robot.name)) {
          this.heardOwnPresence = true;
          return;
        }

        // ignore presence messages that sometimes get broadcast
        // Group chat jid are of the form
        // room_name@conference.hostname/Room specific id
        var room = fromJID.bare().toString();
        if (!this.messageFromRoom(room)) { return; }

        // Some servers send presence for the room itself, which needs to be
        // ignored
        if (room === fromJID.toString()) {
          return;
        }

        // Try to resolve the private JID
        var privateChatJID = this.resolvePrivateJID(stanza);

        // Keep the room JID to private JID map in this class as there
        // is an initialization race condition between the presence messages
        // and the brain initial load.
        // See https://github.com/github/hubot/issues/619
        this.roomToPrivateJID[fromJID.toString()] = privateChatJID != null ? privateChatJID.toString() : undefined;
        this.robot.logger.debug(`Available received from ${fromJID.toString()} in room ${room} and private chat jid is ${(privateChatJID != null ? privateChatJID.toString() : undefined)}`);

        // Use the resource part from the room jid as this
        // is most likely the user's name
        var user = this.robot.brain.userForId(fromJID.resource, {
          room,
          jid: fromJID.toString(),
          privateChatJID: (privateChatJID != null ? privateChatJID.toString() : undefined)
        });

        // Xmpp sends presence for every person in a room, when join it
        // Only after we've heard our own presence should we respond to
        // presence messages.
        if (!!this.heardOwnPresence) { return this.receive(new EnterMessage(user)); }
        break;

      case 'unavailable':
        [room, user] = stanza.attrs.from.split('/');

        // ignore presence messages that sometimes get broadcast
        if (!this.messageFromRoom(room)) { return; }

        // ignore our own messages in rooms
        if (user === this.options.username) { return; }

        this.robot.logger.debug(`Unavailable received from ${user} in room ${room}`);

        user = this.robot.brain.userForId(user, {room});
        return this.receive(new LeaveMessage(user));
    }
  }

  // Accept a stanza from a group chat
  // return privateJID (instanceof JID) or the
  // http://jabber.org/protocol/muc#user extension was not provided
  resolvePrivateJID( stanza ) {
    const jid = new JID(stanza.attrs.from);

    // room presence in group chat uses a jid which is not the real user jid
    // To send private message to a user seen in a groupchat,
    // you need to get the real jid. If the groupchat is configured to do so,
    // the real jid is also sent as an extension
    // http://xmpp.org/extensions/xep-0045.html#enter-nonanon
    const privateJID = __guard__(__guard__(__guardMethod__(stanza.getChild('x', 'http://jabber.org/protocol/muc#user'), 'getChild', o => o.getChild('item')), x1 => x1.attrs), x => x.jid);

    if (!privateJID) {
      if (!this.anonymousGroupChatWarningLogged) {
        this.robot.logger.warning("Could not get private JID from group chat. Make sure the server is configured to broadcast real jid for groupchat (see http://xmpp.org/extensions/xep-0045.html#enter-nonanon)");
        this.anonymousGroupChatWarningLogged = true;
      }
      return null;
    }

    return new JID(privateJID);
  }

  // Checks that the room parameter is a room the bot is in.
  messageFromRoom(room) {
    for (let joined of this.options.rooms) {
      if (joined.jid.toUpperCase() === room.toUpperCase()) { return true; }
    }
    return false;
  }

  send(envelope, ...messages) {
    return (() => {
      const result = [];
      for (var msg of messages) {
        var message;
        this.robot.logger.debug(`Sending to ${envelope.room}: ${msg}`);

        let to = envelope.room;
        if (['direct', 'chat'].includes(envelope.user != null ? envelope.user.type : undefined)) {
          to = envelope.user.privateChatJID != null ? envelope.user.privateChatJID : `${envelope.room}/${envelope.user.name}`;
        }

        const params = {
          // Send a real private chat if we know the real private JID,
          // else, send to the groupchat JID but in private mode
          // Note that if the original message was not a group chat
          // message, envelope.user.privateChatJID will be
          // set to the JID from that private message
          to,
          type: (envelope.user != null ? envelope.user.type : undefined) || 'groupchat'
        };

        if (msg instanceof Element) {
          message = msg.root();
          if (message.attrs.to == null) { message.attrs.to = params.to; }
          if (message.attrs.type == null) { message.attrs.type = params.type; }
        } else {
          const parsedMsg = (() => { try { return parse(msg); } catch (error) {} })();
          const bodyMsg   = new Stanza('message', params).
                      c('body').t(msg);
          message   = (parsedMsg != null) ?
                        bodyMsg.up().
                        c('html',{xmlns:'http://jabber.org/protocol/xhtml-im'}).
                        c('body',{xmlns:'http://www.w3.org/1999/xhtml'}).
                        cnode(parsedMsg)
                      :
                        bodyMsg;
        }

        result.push(this.client.send(message));
      }
      return result;
    })();
  }

  reply(envelope, ...messages) {
    return messages.map((msg) =>
      msg instanceof Element ?
        this.send(envelope, msg)
      :
        this.send(envelope, `${envelope.user.name}: ${msg}`));
  }

  topic(envelope, ...strings) {
    const string = strings.join("\n");

    const message = new Stanza('message', {
                to: envelope.room,
                type: envelope.user.type
              }
              ).
              c('subject').t(string);

    return this.client.send(message);
  }

  offline() {
    return this.robot.logger.debug("Received offline event");
  }

  checkCanStart() {
    if (!process.env.HUBOT_XMPP_USERNAME) {
      throw new Error("HUBOT_XMPP_USERNAME is not defined; try: export HUBOT_XMPP_USERNAME='user@xmpp.service'");
    } else if (!process.env.HUBOT_XMPP_PASSWORD) {
      throw new Error("HUBOT_XMPP_PASSWORD is not defined; try: export HUBOT_XMPP_PASSWORD='password'");
    } else if (!process.env.HUBOT_XMPP_ROOMS) {
      throw new Error("HUBOT_XMPP_ROOMS is not defined: try: export HUBOT_XMPP_ROOMS='room@conference.xmpp.service'");
    }
  }
}

XmppBot.prototype.reconnectTryCount = 0;
XmppBot.prototype.currentIqId = 1001;
XmppBot.prototype.joining = [];
XmppBot.prototype.joined = [];

exports.use = robot => new XmppBot(robot);

function __guardMethod__(obj, methodName, transform) {
  if (typeof obj !== 'undefined' && obj !== null && typeof obj[methodName] === 'function') {
    return transform(obj, methodName);
  } else {
    return undefined;
  }
}
function __guard__(value, transform) {
  return (typeof value !== 'undefined' && value !== null) ? transform(value) : undefined;
}
