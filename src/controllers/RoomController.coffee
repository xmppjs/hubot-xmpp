
Controller = require './framework/Controller.coffee'

module.exports = class RoomController extends Controller

  @expose:
    createRoom: (callback) -> #(err,roomJid) ->
      @realtime.debug 'room', 'createRoom'
      room = "#{uuid.generate()}-z@conference.#{@realtime.jid.domain}"
      return callback null, room

    inviteToRoom: (roomJid, userJid) ->
      @realtime.debug 'room', 'inviteToRoom', roomJid, userJid
      stanza = new ltx.Element 'message', from:@realtime.jid.toString(), to:userJid
      stanza.c 'x', xmlns:'jabber:x:conference', jid:roomJid

      @realtime.send stanza

    joinRoom: (roomJid, callback) ->
      unless roomJid then return console?.error('joinRoom called with no jid.')
      roomJid = roomJid.toString().split('@')[0]+'@conference.'+@realtime.jid.domain
      @realtime.debug 'room', 'joining', roomJid
      @_joinRoom roomJid
      @once 'join:'+roomJid.split('@')[0], =>
        # @realtime.sendMessage roomJid, 'Hello!'
        if typeof callback is 'function' then callback()

    leaveRoom: (roomJid) ->
      unless roomJid then return console?.error('leaveRoom called with no jid.')
      roomJid = roomJid.toString().split('@')[0]+'@conference.'+@realtime.jid.domain
      @realtime.debug 'room', 'joining', roomJid
      stanza = new ltx.Element 'presence', from:@realtime.jid.toString(), to:"#{roomJid}/#{@_nick}", id:uuid.generate(), type:'unavailable'
      delete @_rooms[roomJid]
      @realtime.send stanza
      @realtime._clearMessages roomJid

    setRoomSubject: (roomJid, subject, callback = ->) ->
      roomJid = roomJid.toString().split('@')[0]+'@conference.'+@realtime.jid.domain
      stanza = new ltx.Element 'message', from:@realtime.jid.toString(), to:roomJid, type:'groupchat'
      stanza.c('subject').t(subject)

      @realtime.send stanza

      setTimeout (=>
        @emit 'subjectChange', {room:roomJid, subject}
        callback()
      ), 500

    getRoomInfo: (roomJid, callback) ->
      roomJid = roomJid.toString().split('@')[0]+'@conference.'+@realtime.jid.domain

      id = uuid.generate()
      stanza = new ltx.Element 'iq', id:id, to:roomJid, type:'get'
      stanza.c('query', xmlns:'http://jabber.org/protocol/disco#info')
      
      @realtime.send stanza
      @on 'roomInfo:'+id, (obj) =>
        return callback null, obj

    setAttributes: (roomJid, attributes) ->
      roomJid = roomJid.toString().split('@')[0]+'@conference.'+@realtime.jid.domain

      stanza = new ltx.Element 'message', to:roomJid, type:'groupchat'
      @_attributes[roomJid] ?= {}
      if _.isEqual @_attributes[roomJid], attributes then return
      @_attributes[roomJid] = attributes
      stanza.c('attributes').t(JSON.stringify(attributes))
      @realtime.send stanza


  @exposeEvents: ['invite', 'subjectChange', 'data', 'occupantChange']

  @stanzas:
    handleInvite: (stanza) -> stanza.is('message') and stanza.getChild('x', 'jabber:x:conference')?.attrs.jid?
    handleSubject: (stanza) -> stanza.is('message') and stanza.getChild('subject')?.text().length > 0
    handleData: (stanza) -> stanza.is('message') and stanza.attrs.type is 'groupchat' and stanza.getChild('data')?.text().length > 0
    handleInfo: (stanza) -> stanza.is('iq') and stanza.attrs.type is 'result' and stanza.attrs.from?.match(/@conference/) and stanza.getChild('query', 'http://jabber.org/protocol/disco#info')?
    handlePresence: (stanza) -> stanza.is('presence') and stanza.attrs.from isnt @realtime.jid?.bare().toString() and stanza.attrs.type in [undefined, 'unavailable'] and stanza.attrs.from.match(/@conference/)

  constructor: ->
    super
    @_rooms = {}
    @_occupants = {}
    @_attributes = {}
    @_pendingOccupants = {}
    
    @realtime.on 'connect', =>
      oldRooms = @_rooms

      @_rooms = {}
      @_attributes = {}
      @_pendingOccupants = {}
      for jid of oldRooms then @_joinRoom jid
      @_nick = @realtime.jid.bare().toString().replace('@', '#')

  handleInfo: (stanza) ->
    query = stanza.getChild('query')

    attributes = {}
    for child in query.getChild('attributes')?.children
      if child.name
        attributes[child.name] = child.text()

    participants = []
    for child in query.getChild('participants')?.getChildren('participant')
      participants.push child.text()

    occupants = []
    for child in query.getChild('occupants')?.getChildren('occupant')
      occupants.push child.text()
      
    subject = query.getChild('subject')?.text()

    @emit 'roomInfo:'+stanza.attrs.id, {subject, occupants, participants, attributes}


  handleSubject: (stanza) ->
    out = {room:new JID(stanza.attrs.from).bare().toString(), from:stanza.attrs.ofrom, subject:stanza.getChild('subject').text()}
    @realtime.debug 'room', 'subjectChange', out
    @realtime.debug 'subject', 'subjectChange', out
    @emit 'subjectChange', out

  handleInvite: (stanza) ->
    @realtime.debug 'room', 'got invite', stanza.toString()
    room = if stanza.getChild('x','http://jabber.org/protocol/muc#user')?.getChild('invite')? then stanza.attrs.to else stanza.getChild('x', 'jabber:x:conference').attrs.jid

    @_joinRoom room

  handleData: (stanza) ->
    @realtime.debug 'data', 'handleData', stanza.toString()
    data = JSON.parse stanza.getChild('data').text()
    @realtime.debug 'data', 'handleData', 'data', data
    @emit 'data', {data, room:stanza.attrs.from, from:stanza.attrs.ofrom}

  handlePresence: (stanza) ->
    [from] = stanza.attrs.ofrom.split('/')
    [room] = stanza.attrs.from.split('/')
    [to] = stanza.attrs.to.split('/')

    @_occupants[room] or= {}
    @_pendingOccupants[room] or= {}
    if stanza.attrs.type is 'unavailable'
      type = 'leave'
      unless @_occupants[room][from] then return
      delete @_occupants[room][from]
      delete @_pendingOccupants[room][from]
    else
      type = 'join'
      if @_pendingOccupants[room][from] then return
      @_occupants[room][from] = true
      @_pendingOccupants[room][from] = true
      if from is @realtime.jid.bare().toString()
        @emit 'join:'+room.split('@')[0]

    @realtime.debug 'room', 'occupantChange', {room, from, type}
    @emit 'occupantChange', {room, from, type}

    if from is to
      @_handleJoinRoomConfirmation stanza

  _handleJoinRoomConfirmation: (stanza)->
    [room] = stanza.attrs.from.split('/')

    debug 'room', 'join room confirmation'
    @realtime.getActiveChats (err, actives) => 
      if actives and !actives[room]
        debug 'room', "I'm not even supposed to be here today!", room, actives
        @realtime.leaveRoom room
      else 
        if @_occupants[room] and @_pendingOccupants[room]
          for from of @_occupants[room]
            unless @_pendingOccupants[room][from]
              @emit 'occupantChange', {room, from, type: 'leave'}
          @_occupants[room] = @_pendingOccupants[room]

  _joinRoom: (roomJid) ->
    if @_rooms[roomJid] then return
    @_rooms[roomJid] = true
    stanza = new ltx.Element 'presence', from:@realtime.jid.toString(), to:"#{roomJid}/#{@_nick}", id:uuid.generate()
    stanza.c 'x', xmlns:'http://jabber.org/protocol/muc'
    @realtime.send stanza

