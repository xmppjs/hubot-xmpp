var ScopedClient, extend, http, https, path, qs, url;
var __bind = function(fn, me){ return function(){ return fn.apply(me, arguments); }; };
path = require('path');
http = require('http');
https = require('https');
url = require('url');
qs = require('querystring');
ScopedClient = (function() {
  function ScopedClient(url, options) {
    this.options = this.buildOptions(url, options);
  }
  ScopedClient.prototype.request = function(method, reqBody, callback) {
    var headers, port, req, sendingData;
    if (typeof reqBody === 'function') {
      callback = reqBody;
      reqBody = null;
    }
    try {
      headers = extend({}, this.options.headers);
      sendingData = method.match(/^P/) && reqBody && reqBody.length > 0;
      headers.Host = this.options.hostname;
      if (sendingData) {
        headers['Content-Length'] = reqBody.length;
      }
      if (this.options.auth) {
        headers['Authorization'] = 'Basic ' + new Buffer(this.options.auth).toString('base64');
      }
      port = this.options.port || ScopedClient.defaultPort[this.options.protocol] || 80;
      req = (this.options.protocol === 'https:' ? https : http).request({
        port: port,
        host: this.options.hostname,
        method: method,
        path: this.fullPath(),
        headers: headers,
        agent: false
      });
      if (callback) {
        req.on('error', callback);
      }
      if (sendingData) {
        req.write(reqBody, 'utf-8');
      }
      if (callback) {
        callback(null, req);
      }
    } catch (err) {
      if (callback) {
        callback(err, req);
      }
    }
    return __bind(function(callback) {
      if (callback) {
        req.on('response', function(res) {
          var body;
          res.setEncoding('utf8');
          body = '';
          res.on('data', function(chunk) {
            return body += chunk;
          });
          return res.on('end', function() {
            return callback(null, res, body);
          });
        });
      }
      req.end();
      return this;
    }, this);
  };
  ScopedClient.prototype.fullPath = function(p) {
    var full, search;
    search = qs.stringify(this.options.query);
    full = this.join(p);
    if (search.length > 0) {
      full += "?" + search;
    }
    return full;
  };
  ScopedClient.prototype.scope = function(url, options, callback) {
    var override, scoped;
    override = this.buildOptions(url, options);
    scoped = new ScopedClient(this.options).protocol(override.protocol).host(override.hostname).path(override.pathname);
    if (typeof url === 'function') {
      callback = url;
    } else if (typeof options === 'function') {
      callback = options;
    }
    if (callback) {
      callback(scoped);
    }
    return scoped;
  };
  ScopedClient.prototype.join = function(suffix) {
    var p;
    p = this.options.pathname || '/';
    if (suffix && suffix.length > 0) {
      if (suffix.match(/^\//)) {
        return suffix;
      } else {
        return path.join(p, suffix);
      }
    } else {
      return p;
    }
  };
  ScopedClient.prototype.path = function(p) {
    this.options.pathname = this.join(p);
    return this;
  };
  ScopedClient.prototype.query = function(key, value) {
    var _base;
    (_base = this.options).query || (_base.query = {});
    if (typeof key === 'string') {
      if (value) {
        this.options.query[key] = value;
      } else {
        delete this.options.query[key];
      }
    } else {
      extend(this.options.query, key);
    }
    return this;
  };
  ScopedClient.prototype.host = function(h) {
    if (h && h.length > 0) {
      this.options.hostname = h;
    }
    return this;
  };
  ScopedClient.prototype.port = function(p) {
    if (p && (typeof p === 'number' || p.length > 0)) {
      this.options.port = p;
    }
    return this;
  };
  ScopedClient.prototype.protocol = function(p) {
    if (p && p.length > 0) {
      this.options.protocol = p;
    }
    return this;
  };
  ScopedClient.prototype.auth = function(user, pass) {
    if (!user) {
      this.options.auth = null;
    } else if (!pass && user.match(/:/)) {
      this.options.auth = user;
    } else {
      this.options.auth = "" + user + ":" + pass;
    }
    return this;
  };
  ScopedClient.prototype.header = function(name, value) {
    this.options.headers[name] = value;
    return this;
  };
  ScopedClient.prototype.headers = function(h) {
    extend(this.options.headers, h);
    return this;
  };
  ScopedClient.prototype.buildOptions = function() {
    var i, options, ty;
    options = {};
    i = 0;
    while (arguments[i]) {
      ty = typeof arguments[i];
      if (ty === 'string') {
        options.url = arguments[i];
      } else if (ty !== 'function') {
        extend(options, arguments[i]);
      }
      i += 1;
    }
    if (options.url) {
      extend(options, url.parse(options.url, true));
      delete options.url;
      delete options.href;
      delete options.search;
    }
    options.headers || (options.headers = {});
    return options;
  };
  return ScopedClient;
})();
ScopedClient.methods = ["GET", "POST", "PATCH", "PUT", "DELETE", "HEAD"];
ScopedClient.methods.forEach(function(method) {
  return ScopedClient.prototype[method.toLowerCase()] = function(body, callback) {
    return this.request(method, body, callback);
  };
});
ScopedClient.prototype.del = ScopedClient.prototype['delete'];
ScopedClient.defaultPort = {
  'http:': 80,
  'https:': 443,
  http: 80,
  https: 443
};
extend = function(a, b) {
  var prop;
  prop = null;
  Object.keys(b).forEach(function(prop) {
    return a[prop] = b[prop];
  });
  return a;
};
exports.create = function(url, options) {
  return new ScopedClient(url, options);
};