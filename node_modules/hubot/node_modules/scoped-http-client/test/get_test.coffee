ScopedClient = require '../lib'
http         = require 'http'
assert       = require 'assert'
called       = 0

server = http.createServer (req, res) ->
  res.writeHead 200, 'Content-Type': 'text/plain'
  res.end "#{req.method} #{req.url} -- hello #{req.headers['accept']}"

server.listen 9999

server.on 'listening', ->
  client = ScopedClient.create 'http://localhost:9999',
    headers:
      accept: 'text/plain'

  client.get() (err, resp, body) ->
    called++
    assert.equal 200,          resp.statusCode
    assert.equal 'text/plain', resp.headers['content-type']
    assert.equal 'GET / -- hello text/plain', body
    client.path('/a').query('b', '1').get() (err, resp, body) ->
      called++
      assert.equal 200,          resp.statusCode
      assert.equal 'text/plain', resp.headers['content-type']
      assert.equal 'GET /a?b=1 -- hello text/plain', body
      server.close()

process.on 'exit', ->
  assert.equal 2, called
