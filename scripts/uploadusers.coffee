# Description
#  Create users / change passwords for customer accounts on the upload server
#
# Dependencies
#  util
#  child_process
#  rolemanager.coffee
#
# Configuration
#  UPLOAD_DEBUG - 'true'|'false' - enable debug messages
#  UPLOAD_USER - string - username for bot to use on upload server
#  UPLOAD_HOST - string - hostname of upload server
#  UPLOAD_KEY - string - SSH key for bot to use to connect ot upload server
#  UPLOAD_HOME - string - path to homedir on Heroku
#  UPLOAD_KEYFILE - string - filename for SSH key (within homedir)
#  UPLOAD_SECRET - string - shared secret for google sheet
#  UPLOAD_DOCID - string - document ID for google sheet
#  UPLOAD_SHEET - string - name of sheet within google sheet doc
#  UPLOAD_DOC_URL - string - URL for bot integration script
#  UPLOAD_DOC_MANUAL_URL - URL to give users to find upload cred sheet
#
# Commands
#  hubot (make|create) upload user <name> for ticket [#]<number> - create a user on upload.basho.com and note it in the ticket and organization record
#  hubot change password for upload user <name> for ticket [#]<number> - generate a new password for the upload user
#  hubot validate upload user <name> password <password> for ticket [#]<number>- test sftp authentication 
#  hubot find upload user for ticket [#]<number> - search the organizations' other tickets for upload users created by BashoBot
#

httpClient = require('scoped-http-client')
crypto = require 'crypto'
util = require 'util'
_ = require 'underscore'
cp = require 'child_process'
fs = require 'fs'

uploadUserMan = 
  debug: (process.env.UPLOAD_DEBUG == 'true')
  user: process.env.UPLOAD_USER
  host: process.env.UPLOAD_HOST
  home: process.env.UPLOAD_HOME
  keyfile: "#{process.env.UPLOAD_HOME}/#{process.env.UPLOAD_KEYFILE}"

  do_request_with_redirect: (request, callback) ->
    if request.data instanceof Object
      data = ""
      for k of request.data
        data = data + '&' if data isnt ""
        value = request.data[k]
        if value instanceof Object
          value = JSON.stringify request.data[k]
        data = data + k + '=' + encodeURIComponent(value)
    else 
      data = request.data
    headers = request.headers
    client = httpClient.create(request.url, headers)
    for h of headers
      client.header(h,headers[h])
    client[request.method](data) (err, res, body) =>
      @logger.info "status: #{res.statusCode}" if @debug
      @logger.info "location: #{res.headers.location}" if @debug
      if err
        callback? err, res, body
      else if res.statusCode > 299 and res.statusCode < 400 and res.headers.location?
        cookies = res.headers["set-cookie"]
        newurl = res.headers.location
        @do_request_with_redirect {
          method: "get"
          url:newurl,
          headers: {
              cookies:cookies
          }}, callback
      else
        callback? err, res, body

  doPost: (msg, req, reqfun) ->
    msg.send "doPost(msg,#{JSON.stringify(req)}, reqfun)" if @debug
    request =
      data: @addAuth req
      url: "#{process.env.UPLOAD_DOC_URL}"
      method: "post"
      headers:  
        "Content-Type":"application/x-www-form-urlencoded"
        Accept:"*/*"
    msg.send "Request #{JSON.stringify request}" if @debug
    @do_request_with_redirect request, (err, res, body) =>
      if res.statusCode is 200
        reqfun?(JSON.parse(body))
      else
        msg.reply "Error #{res.statusCode}\n#{body}"

  addAuth: (req) ->
    docid = req.id
    dt = new Date
    md5sum = crypto.createHash('md5')
    md5sum.update "#{process.env.UPLOAD_SECRET}#{dt}#{docid}"
    req.date = "#{dt}"
    req.data = "#{md5sum.digest 'base64'}"
    req

  appendCred: (msg, orgid, orgname, username, password) ->
    reqdata =
      action: "Append"
      id: process.env.UPLOAD_DOCID
      sheet: process.env.UPLOAD_SHEET
      rows: [{
        Id: orgid
        Name: orgname
        User: username
        Password: password
        }]
    @doPost msg, reqdata, (data) =>
      msg.reply "Added #{orgname}/#{username} to google sheet"

  updateCred: (msg, orgid, username, password) ->
    reqdata = 
      action: "Update"
      id: process.env.UPLOAD_DOCID
      sheet: process.env.UPLOAD_SHEET
      rows: [
        {col:"User", value: username}
        {col:"Password", value: password}
      ]
      filters: [{col:"Id", value: orgid}]
    @doPost msg, reqdata, (data) =>
      msg.send util.inspect data
      if data.error?
        msg.reply "Unable to automatically update sheet: #{data.error}"
        manual_url = process.env.UPLOAD_DOC_MANUAL_URL
        msg.send "Please manually update #{manual_url}" if manual_url 
      else 
        msg.reply "Updated #{username} in google sheet"

  getCredForOrgId: (msg, orgid, callback) ->
    reqdata = 
      action: "Filter"
      id: process.env.UPLOAD_DOCID
      sheet: process.env.UPLOAD_SHEET
      filters: [{col:"Id", value:orgid}]
    @doPost msg, reqdata, callback

  userAction: (msg, cmd, name, password, ticket, callback) ->
    if callback is undefined
      callback = ticket
      ticket = password 
      password = ""
      passwordarg = ""
    else
      passwordarg = ":#{password}"
    msg.robot.zenDesk.ticketData(msg, ticket) (ticketdat) =>
      orgid = ticketdat.organization_id
      msg.robot.logger.info "upload user #{cmd} #{name} ticket #{ticket}"
      fs.writeFile "#{@keyfile}","#{process.env.UPLOAD_KEY}", {mode:0o0600}, (err) =>
       msg.robot.logger.info "Keyfile: #{@keyfile} Err: #{err}" if @debug
       if err
        msg.reply "Error creating key file"
       else
        cmdstr = "echo -e 'BASHOBOT:#{cmd}:#{name}#{passwordarg}\n' | ssh -T -o LogLevel=quiet -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i #{@keyfile} #{@user}@#{@host}"
        cp.exec cmdstr, (error, stdout, stderr) => 
            try 
              re = new RegExp "#{name}:([^ ]*)(.*)\n"
              if m = "#{stdout}".match re
                switch cmd
                    when "Create"
                      msg.reply "New user #{name} password #{m[1]}. #{m[2]}."
                      password = m[1]
                      pnote = "Bashobot created an upload.basho.com user '#{name}' with password '#{m[1]}'."
                    when "Change"
                      msg.reply "User #{name} new password #{m[1]}. #{m[2]}."
                      password = m[1]
                      pnote = "Bashobot changed password for upload.basho.com user '#{name}' with password '#{m[1]}'."
                    when "Validate"
                      msg.reply "Validate user #{stdout}"
                if pnote isnt undefined
                  msg.robot.zenDesk.addComment(msg, ticket, pnote, false) (ticketdata) =>
                    msg.reply("Updated ticket #{ticketdata.id}") if ticketdata?.id?
                    @getCredForOrgId msg, orgid, (data) =>
                      if data.count is 0 
                        msg.robot.zenDesk.getOrgName(msg, orgid) (orgname) =>
                          @appendCred msg, orgid, orgname, name, password 
                      else if data.count is 1
                        @updateCred msg, orgid, name, password
                      else
                        msg.reply "#{data.count} results founding matching organization ID #{orgid}"
                        manual_url = process.env.UPLOAD_DOC_MANUAL_URL
                        msg.send "Please manually update #{manual_url}" if manual_url 
                callback?(true, name, password)
              else
                msg.reply "#{cmd} failed for user #{name}: #{stdout}\n#{stderr}"
                callback?(false, name, password)
            catch err 
              msg.reply "Error: #{util.inspect err}"

  findUser: (msg, ticket, useorg=true, usesheet=true) ->
    msg.robot.zenDesk.ticketData(msg, ticket) (ticketdata) =>
      if ticketdata
        org = ticketdata.organization_id
        msg.robot.zenDesk.getOrgFields(msg, org,  ["upload_user","upload_password"]) (resultobj) =>
          if resultobj? and resultobj.upload_user? and resultobj.upload_password? and useorg
              msg.reply "Found user in organization data: User: #{resultobj.upload_user} Password: #{resultobj.upload_password}"
              @userAction msg, "Validate", resultobj.upload_user, resultobj.upload_password, ticket, (success, name, password) ->
                if success is false
                  @findUser msg, ticket, false
          else if usesheet
            @getCredForOrgId msg, org, (data) =>
              usercol = data.colheads.indexOf("User")
              passcol = data.colheads.indexOf("Password")
              rowcol = data.colheads.indexOf("Row")
              if data.count is 1
                useritem = data.items[0]
                user = useritem[usercol] if usercol >= 0
                pass = useritem[passcol] if passcol >= 0
                row = useritem[rowcol] if rowcol >= 0
                if user? and pass?
                  msg.reply "Found user in Google spreadsheet: Username: #{user} Password: #{pass} Row: #{row}"
                  @userAction msg, "Validate", user, pass, ticket, (success, username, password) ->
                    if success is false
                      @findUser msg, ticket, false, false
              else if data.count > 0
                msg.reply "Multiple entries found:"
                for useritem in data.items
                  user = useritem[usercol] if usercol >= 0
                  pass = useritem[passcol] if passcol >= 0
                  row = useritem[rowcol] if rowcol >= 0
                  msg.send "User: #{user} Password: #{pass} Row: #{row}"
              else
                @findUser msg, ticket, false, false
          else
            msg.reply "Searching ZenDesk, please be patient"
            msg.robot.zenDesk.getOrgName(msg,org) (orgname) ->
              squery = "type:ticket organization:#{org} description:Bashobot+created+an+upload.basho.com+user description:Bashobot+changed+password+for+upload.basho.com+user"
              msg.robot.logger.info "search query: \"#{squery}\""
              msg.robot.zenDesk.search(msg, {"query":squery}) (data) ->
                if data.count is 0
                    msg.reply "No upload users found for #{orgname} ticket #{ticketdata.id}"
                else
                  tickets = []
                  for tick in data.results
                    tickets.push("https://basho.zendesk.com/agent/#/tickets/#{tick.id}") if "id" of tick 
                  ticklist = tickets.join "\n"
                  msg.reply "#{orgname} upload users/passwords found in tickets:\n#{ticklist}"
      else
        msg.reply "Ticket #{ticket} not found"

module.exports = (robot) ->
  uploadUserMan.logger = robot.logger
  robot.um = uploadUserMan

  robot.respond /(?:create|make) upload user (....*) (?:for|in) ticket [#]?([0-9]*)/i, (msg) ->
    uploadUserMan.userAction msg, 'Create', msg.match[1], msg.match[2]
    
  robot.respond /change password for upload user (.*) (?:for|in|from) ticket [#]?([0-9]*)/i, (msg) ->
    uploadUserMan.userAction  msg, 'Change', msg.match[1], msg.match[2]

  robot.respond /find upload user (?:for|in|from) ticket [#]?([0-9]*)/i, (msg) ->
    uploadUserMan.findUser msg, msg.match[1] 

  robot.respond /validate upload user (....*) password (..*) (?:for|in|from) ticket \#*([0-9]*)/i, (msg) ->
    uploadUserMan.userAction msg, 'Validate', msg.match[1], msg.match[2], msg.match[3] 
