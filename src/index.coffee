{Adapter,Robot,TextMessage,EnterMessage,LeaveMessage} = require 'hubot'

fs = require 'fs'
util = require 'util'

global._ = require 'underscore'
_.str = require 'underscore.string'
XmppClient = require 'node-xmpp-client'
global.JID = require('./JID')
global.ltx = XmppClient.ltx

config = require(process.cwd() + "/config")

logError = => @robot.logger.error arguments...
log = => @robot.logger.info arguments...


class PurecloudBot extends Adapter

  reconnectTryCount: 0

  run: ->
    options = config

    @robot.logger.info util.inspect(options)

    @options = options
    @connected = false

    controllers = {}

    for fileName in fs.readdirSync __dirname + '/controllers'
      unless fileName.match /.*Controller(.coffee)?$/ then continue
      name = _.str.camelize(fileName.substring(0, fileName.indexOf('Controller'))).replace /^./, (m) -> m.toLowerCase()
      controllers[name] = new (require "./controllers/#{fileName}")(@)

    console.log 'controllers', controllers

    @makeClient()

  makeClient: ->
    options = @options

    @client = new XmppClient
      reconnect: true
      jid: options.username
      password: options.password
      host: options.host
      port: options.port
      legacySSL: options.legacySSL
      preferredSaslMechanism: options.preferredSaslMechanism
      disallowTLS: options.disallowTLS

    @robot.logger.debug 'jid is', @client.jid

    @options = options

    @connected = false
    
    @client.connection.socket.setTimeout 0

    @robot.logger.debug 'jid is', @client.jid

    @client.on 'error', (error) => logError error
    @client.on 'online', => log 'online', arguments...
    @client.on 'offline', => log 'offline', arguments...
    @client.on 'stanza', @stanza

    @client.on 'end', =>
      @robot.logger.info 'Connection closed, attempting to reconnect'
      @reconnect()

    @client

  stanza: (stanza) ->
    log 'stanza', stanza.toString()

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

      # ltx.Element type
      if msg.attrs?
        message = msg.root()
        message.attrs.to ?= params.to
        message.attrs.type ?= params.type
      else
        parsedMsg = try new ltx.parse(msg)
        bodyMsg   = new ltx.Element('message', params).c('body').t(msg)
        message   = if parsedMsg?
          bodyMsg.up()
          .c('html',{xmlns:'http://jabber.org/protocol/xhtml-im'})
          .c('body',{xmlns:'http://www.w3.org/1999/xhtml'})
          .cnode(parsedMsg)
        else
          bodyMsg

      @client.send message


  offline: =>
    @robot.logger.debug "Received offline event", @client.connect?
    @client.connect()
    clearInterval(@keepaliveInterval)
    @robot.logger.debug "Received offline event"
    @client.connect()

exports.use = (@robot) ->
  new PurecloudBot @robot
