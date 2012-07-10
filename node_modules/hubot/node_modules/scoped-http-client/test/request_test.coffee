ScopedClient = require('../lib')
http         = require('http')
assert       = require('assert')
called       = 0
curr         = null
ua           = null

server = http.createServer (req, res) ->
  body = ''
  req.on 'data', (chunk) ->
    body += chunk

  req.on 'end', ->
    curr     = req.method
    ua       = req.headers['user-agent']
    respBody = "#{curr} hello: #{body} #{ua}"
    res.writeHead 200,
      'content-type': 'text/plain'
      'content-length': respBody.length
      'x-sent-authorization': req.headers.authorization

    res.write respBody if curr != 'HEAD'
    res.end()

server.listen 9999

server.addListener 'listening', ->
  client = ScopedClient.create('http://localhost:9999')
    .headers({'user-agent':'bob'})
  client.del() (err, resp, body) ->
    called++
    assert.equal 'DELETE', curr
    assert.equal 'bob',    ua
    assert.equal "DELETE hello:  bob", body
    client
      .header('user-agent', 'fred')
      .auth('monkey', 'town')
      .put('yea') (err, resp, body) ->
        called++
        assert.equal 'PUT',  curr
        assert.equal 'fred', ua
        assert.equal "PUT hello: yea fred", body
        assert.equal 'Basic bW9ua2V5OnRvd24=', resp.headers['x-sent-authorization']
        client
          .auth('mode:selektor')
          .head() (err, resp, body) ->
            called++
            assert.equal 'HEAD', curr
            assert.equal 'Basic bW9kZTpzZWxla3Rvcg==', resp.headers['x-sent-authorization']
            server.close()

process.on 'exit', ->
  assert.equal 3, called
