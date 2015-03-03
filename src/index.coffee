{User,Adapter,Robot,TextMessage,EnterMessage,LeaveMessage} = require 'hubot'

fs = require 'fs'
util = require 'util'
{EventEmitter} = require 'events'

global._ = require 'underscore'
_.str = require 'underscore.string'
XmppClient = require 'node-xmpp-client'
global.JID = require('node-xmpp-core').JID
global.ltx = XmppClient.ltx
global.uuid = require './lib/uuid'

config = require(process.cwd() + "/config")

global.logError = => @robot.logger.error arguments...
global.log = => console.log arguments...
global.debug = => # @robot.logger.info arguments...

class Realtime extends EventEmitter

    constructor: (@client) ->
    
    send: (stanza) ->
      debug 'stanza', 'out', stanza.toString()
      @client.send stanza
    
    jid: null
    
    debug: debug

    connected: false

    features: {}

class PurecloudBot extends Adapter

  reconnectTryCount: 0

  realtime: null

  controllers: {}

  run: ->
    options = config

    @robot.on 'error', (error) => console.error error

    @robot.logger.info util.inspect(options)

    @options = options

    @makeClient()

    @realtime = new Realtime @client

    @setupControllers()

    @realtime.on 'message', @_onMessage

  setupControllers: ->

    for fileName in fs.readdirSync __dirname + '/controllers'
      unless fileName.match /.*Controller(.coffee)?$/ then continue
      name = _.str.camelize(fileName.substring(0, fileName.indexOf('Controller'))).replace /^./, (m) -> m.toLowerCase()
      Controller = require "./controllers/#{fileName}"
      @controllers[name] = new Controller(@realtime)

      do (name, Controller) =>
        for funcName, func of Controller.expose
          debug 'handler', 'registering exposed controller method', funcName, 'in controller', name
          do (funcName, func) =>
            @realtime[funcName] = (args...) =>
              apply = =>
                debug 'handle', 'executing', funcName, _.omit @controllers[name], 'realtime', 'client'
                func.apply @controllers[name], args
              unless @realtime.connected
                debug 'handle', 'deferring call to', funcName, @realtime.connected
                return @realtime.once 'connect', => apply()
              else apply()

            null

        for event in Controller.exposeEvents
          do (name, event) =>
            @['on'+_.str.capitalize(event)] = (callback) => @on event, callback
            @controllers[name].on event, =>
              @realtime.emit event, arguments...

            null

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

    log 'jid is', @client.jid

    @client.on 'error', (error) => logError error
    
    @client.on 'online', @onConnect
    
    @client.on 'offline', => 
      log 'offline', arguments...
      @realtime.emit 'disconnect'
    
    @client.on 'stanza', @onStanza

    @client.on 'end', =>
      @robot.logger.info 'Connection closed, attempting to reconnect'
      @client.reconnect()

    @client

  onConnect: ({jid}) => 
    log 'online', jid.toString(), jid.bare().toString()
    @realtime.jid = jid
    @realtime.emit 'connect'
    unless @realtime.connected
      @realtime.connected = true
      @emit 'connected'

  onStanza: (stanza) =>
    debug 'stanza', 'in', stanza.toString()

    handled = false

    for name, controller of @controllers
      for func, test of controller.constructor.stanzas
        do (stanza) =>
          # stanza = stanza.clone()
          if test.apply(controller, [stanza])
            debug 'stanza', 'handled by', "#{controller.constructor.name}.#{func}"
            handled = true
            controller[func] stanza

    unless handled then debug 'stanza', 'unhandled'

    null

  send: (envelope, messages...) ->
    log 'robot', 'send', arguments...
    for msg in messages
      unless msg then continue
      @robot.logger.debug "Sending to #{envelope.room or envelope.user?.id}: #{msg}"

      to = envelope.room or envelope.user?.id

      @realtime.sendMessage to, msg

  offline: =>
    @robot.logger.debug "Received offline event", @client.connect?
    @client.connect()
    clearInterval(@keepaliveInterval)
    @robot.logger.debug "Received offline event"
    @client.connect()

  _onMessage: (msg) =>
    if msg.from is @options.username then return
    if msg.body?.match /nsfw/ then return

    if msg.body?.match(/^hubot leave$/) and msg.to?.match(/@conference/)
      @realtime.sendMessage msg.to, 'Goodbye!'
      return @realtime.leaveRoom msg.to

    console.log 'message', 'got msg', msg, @options.username


    if msg.type is 'person' then user = @robot.brain.userForId msg.from
    else user = @robot.brain.userForId msg.to

    console.log 'message', 'user', user
    
    @receive new TextMessage(user, msg.body)


exports.use = (@robot) ->
  new PurecloudBot @robot

