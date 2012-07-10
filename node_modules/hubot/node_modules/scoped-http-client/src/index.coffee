path = require 'path'
http = require 'http'
https= require 'https'
url  = require 'url'
qs   = require 'querystring'

class ScopedClient
  constructor: (url, options) ->
    @options = @buildOptions url, options

  request: (method, reqBody, callback) ->
    if typeof(reqBody) == 'function'
      callback = reqBody
      reqBody  = null

    try
      headers      = extend {}, @options.headers
      sendingData  = method.match(/^P/) and reqBody and reqBody.length > 0
      headers.Host = @options.hostname

      headers['Content-Length'] = reqBody.length if sendingData

      if @options.auth
        headers['Authorization'] = 'Basic ' + new Buffer(@options.auth).toString('base64');

      port = @options.port ||
        ScopedClient.defaultPort[@options.protocol] || 80
      req = (if @options.protocol == 'https:' then https else http).request(
        port:    port
        host:    @options.hostname
        method:  method
        path:    @fullPath()
        headers: headers
        agent:   false
      )
      if callback
        req.on 'error', callback
      req.write reqBody, 'utf-8' if sendingData
      callback null, req if callback
    catch err
      callback err, req if callback

    (callback) =>
      if callback
        req.on 'response', (res) ->
          res.setEncoding 'utf8'
          body = ''
          res.on 'data', (chunk) ->
            body += chunk

          res.on 'end', ->
            callback null, res, body

      req.end()
      @

  # Adds the query string to the path.
  fullPath: (p) ->
    search = qs.stringify @options.query
    full   = this.join p
    full  += "?#{search}" if search.length > 0
    full
  
  scope: (url, options, callback) ->
    override = @buildOptions url, options
    scoped   = new ScopedClient(@options)
      .protocol(override.protocol)
      .host(override.hostname)
      .path(override.pathname)

    if typeof(url) == 'function'
      callback = url
    else if typeof(options) == 'function'
      callback = options
    callback scoped if callback
    scoped
  
  join: (suffix) ->
    p = @options.pathname || '/'
    if suffix and suffix.length > 0
      if suffix.match /^\//
        suffix
      else
        path.join p, suffix
    else
      p
  
  path: (p) ->
    @options.pathname = @join p
    @

  query: (key, value) ->
    @options.query ||= {}
    if typeof(key) == 'string'
      if value
        @options.query[key] = value
      else
        delete @options.query[key]
    else
      extend @options.query, key
    @
  
  host: (h) ->
    @options.hostname = h if h and h.length > 0
    @
  
  port: (p) ->
    if p and (typeof(p) == 'number' || p.length > 0)
      @options.port = p
    @
  
  protocol: (p) ->
    @options.protocol = p if p && p.length > 0
    @

  auth: (user, pass) ->
    if !user
      @options.auth = null
    else if !pass and user.match(/:/)
      @options.auth = user
    else
      @options.auth = "#{user}:#{pass}"
    @

  header: (name, value) ->
    @options.headers[name] = value
    @

  headers: (h) ->
    extend @options.headers, h
    @

  buildOptions: ->
    options = {}
    i       = 0
    while arguments[i]
      ty = typeof arguments[i]
      if ty == 'string'
        options.url = arguments[i]
      else if ty != 'function'
        extend options, arguments[i]
      i += 1

    if options.url
      extend options, url.parse(options.url, true)
      delete options.url
      delete options.href
      delete options.search
    options.headers ||= {}
    options

ScopedClient.methods = ["GET", "POST", "PATCH", "PUT", "DELETE", "HEAD"]
ScopedClient.methods.forEach (method) ->
  ScopedClient.prototype[method.toLowerCase()] = (body, callback) ->
    @request method, body, callback
ScopedClient.prototype.del = ScopedClient.prototype['delete']

ScopedClient.defaultPort = {'http:':80, 'https:':443, http:80, https:443}

extend = (a, b) ->
  prop = null
  Object.keys(b).forEach (prop) ->
    a[prop] = b[prop]
  a

exports.create = (url, options) ->
  new ScopedClient url, options
