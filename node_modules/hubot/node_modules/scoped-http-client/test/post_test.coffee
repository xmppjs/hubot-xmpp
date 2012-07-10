ScopedClient = require '../lib'
http         = require 'http'
assert       = require 'assert'
called       = 0

server = http.createServer (req, res) ->
  body = ''
  req.on 'data', (chunk) ->
    body += chunk

  req.on 'end', ->
    res.writeHead 200, 'Content-Type': 'text/plain'
    res.end "#{req.method} hello: #{body}"

server.listen 9999

server.on 'listening', ->
  client = ScopedClient.create 'http://localhost:9999'
  client.post((err, req) ->
    called++
    req.write 'boo', 'ascii'
    req.write 'ya',  'ascii'
  ) (err, resp, body) ->
    called++
    assert.equal 200,          resp.statusCode
    assert.equal 'text/plain', resp.headers['content-type']
    assert.equal 'POST hello: booya', body

    client.post((err, req) ->
      req.on 'response', (resp) ->
        resp.on 'end', ->
          # opportunity to stream response differently
          called++
          server.close()
    )()

process.on 'exit', ->
  assert.equal 3, called