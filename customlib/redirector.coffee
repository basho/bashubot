# very rudimentary interface to post to a google macro
# and read the result from the redirect location


httpClient = require('scoped-http-client')
util = require 'util'
handle_following_redirects = {
    do_request: (request, callback) =>
      if request.data instanceof Object
        data = ""
        for k of request.data
          data = data + '&' if data isnt ""
          data = data + k + '=' + encodeURIComponent(request.data[k])
      else 
        data = request.data
      headers = request.headers
      client = httpClient.create(request.url, headers)
      for h of headers
        client.header(h,headers[h])
      client[request.method](data) (err, res, body) =>
        if err
          callback err, res, body
        else if res.statusCode > 299 and res.statusCode < 400
          cookies = res.headers["set-cookie"]
          newurl = res.headers.location
          handle_following_redirects.do_request {
            method: "get"
            url:newurl,
            headers: {
                cookies:cookies
            }}, callback
        else
          callback(err, res, body)
}


module.exports = handle_following_redirects
