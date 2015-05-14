#
# Description
#  Interact with a google docs spreadsheet
#
# Dependencies
#  scoped-http-client
#  util
#  crypto
#
# Commands
#  hubot te use <docid>:<sheet> as <nickname> - register an existing google doc with this module
#  hubot te <nickname> create <newsheet> as <newnickname> with <comma separated headers> - create a new sheet in a previously registered document
#  hubot te create <docname> [sheet] <sheetname> as <nickname> with <comma separated headers> - create a new sheet in a new document
#  hubot te (add|append|new) [row] <comma separated data> 
#  hubot te <nickname>  get [row|rows] <number> [(through|to|thru) <number>]
#  hubot te <nickname> search [(col|column)] <column nme> (is|contains|starts with|between) <value> [and <value>]
#  hubot te list - list known sheet nicknames
#

crypto = require 'crypto'
util = require 'util'
HttpClient = require 'scoped-http-client'
ssLogVolitiles = {}
api = require '../customlib/redirector.coffee'

ssLog = 
  debug: process.env.SS_DEBUG || false
  watiting: true
  addAuth: (req) ->
    docid = req.id
    dt = new Date
    md5sum = crypto.createHash('md5')
    md5sum.update "#{process.env.SS_SECRET}#{dt}#{docid}"
    req.date = "#{dt}"
    req.data = "#{md5sum.digest 'base64'}"
    req

  trimSplit: (csvstr) ->
    csvstr.split(",")
    .map (i) ->
        i.trim()

  getDoc: (msg, nickname, dfun) ->
    if @waiting
      msg.reply "Waiting for my brain to come online"
      return false
    doclist = msg.robot.brain.get "SS_EV_DOCS"
    s = nickname.toUpperCase().trim()
    if doclist instanceof Object
       for d of doclist
         if d.toUpperCase() == s
           if dfun 
             dfun(doclist[d].docid,doclist[d].sheet)
           return
    msg.reply "I don't recall any datasheet named '#{nickname}'"

  dropDoc: (msg, nickname) ->
    doclist = msg.robot.brain.get "SS_EV_DOCS"
    s = nickname.toUpperCase().trim()
    response = []
    if doclist instanceof Object
      for d,v of doclist
        if d.toUpperCase() == s
            response.push "Forgetting datasheet '#{nickname}' -> #{doclist[d].name}(#{doclist[d].docid}):#{doclist[d].sheet}"
            delete doclist[d]
    if response.length > 0
      msg.robot.brain.set "SS_EV_DOCS", doclist
      msg.reply response
    else
      msg.reply "I don't know about datasheet '#{nickname}'"

  setDoc: (msg, docid, sheetname, nickname) ->
   if @waiting
     msg.reply "Waiting for my brain to come online"
     return false
   if typeof nickname isnt "string"
      nickname = sheetname
    @doPost msg, 
      action: "Check"
      id: docid
      sheet: sheetname,
      (data) ->
        if "docname" of data
          doclist = msg.robot.brain.get "SS_EV_DOCS"
          doclist ||= {} 
          doclist[nickname] = 
            docid: docid
            name: data.docname
            sheet: sheetname
          msg.reply "Remembering that '#{nickname}' refers to sheet '#{sheetname}' in document '#{data.docname}'(#{docid})"
          msg.robot.brain.set "SS_EV_DOCS", doclist
        else
          msg.reply "Unable to locate requested sheet: #{JSON.stringify data}"

 
  formatResponse: (msg,txt,data) ->
    if "count" of data
      lines = []
      size = []
      datarow = []
      size = for head in data.colheads
        datarow.push "#{head}"
        "#{head}".length
      lines.push datarow
      for row in data.items
        datarow = []
        i = 0
        for r in row
          size[i] ||= 0
          if "#{r}".length > size[i]
            size[i] = "#{r}".length
          datarow.push "#{r}"
          i += 1
        lines.push datarow
      response = "/quote #{txt}\n"
      for l in lines
        sizedrow = []
        i = 0
        for f in l
          if f.length < size[i]
            f = "#{f}#{Array(size[i] - f.length + 1).join ' '}"
          sizedrow.push f
          i += 1
        response += "#{sizedrow.join(', ')}\n"
      msg.send response
    else
      msg.reply "Unexpected response: #{util.inspect data}"

  postReq: (msg, nickname, req, pfun) ->
    @getDoc msg, nickname, (docid, sheetname) =>
      req.id = docid
      req.sheet = sheetname
      @doPost msg, req, pfun

  doPost: (msg, req, reqfun) ->
    msg.send "doPost(msg,#{JSON.stringify(req)}, reqfun)" if @debug
    request = 
      data: @addAuth req
      url: "#{process.env.SS_URL}"
      method: "post"
      headers: { "Content-Type":"application/x-www-form-urlencoded", "Accept":"*/*" }
    msg.send JSON.stringify request if @debug
    api.do_request request, (err, res, body) ->
      if res.statusCode == 200
        reqfun(JSON.parse(body)) if reqfun
      else
        msg.reply "Error #{res.statusCode}\n#{body}"

  getByRow: (msg, nickname, fromrow, torow) ->
    torow = fromrow if not torow or torow is ""
    @postReq msg, nickname, 
      action: "Filter"
      filters: [{fromrow:fromrow, torow:torow}], (data) =>
        @formatResponse msg, "Retrieved rows #{fromrow} through #{torow} from #{nickname}", data

  getByValue: (msg, nickname, column, value1, value2) ->
    if value2
      filter = {col:column, rangefrom:value1, rangeto:value2}
      textMsg = "Search #{nickname} for #{column} between #{value1} and #{value2}"
    else
      filter = {col:column, value:value1}
      textMsg = "Search #{nickname} #{column} for #{value1}"
    @postReq msg, nickname,
      action: "Filter"
      filters: [filter], (data) =>
        @formatResponse msg, textMsg, data

  getByPrefix: (msg, nickname, column, value) ->
    @postReq msg, nickname,
      action: "Filter"
      filters: [{col:column ,prefix:value}], (data) =>
        @formatResponse msg, "Search #{nickname} for #{column} starting with #{value}", data

  getByContains: (msg, nickname, column, value) ->
    @postReq msg, nickname,
      action: "Filter"
      filters: [{col:column, contains:value}], (data) =>
        @formatResponse msg, "Search #{nickname} for #{column} containing #{value}", data

  addSheet: (msg, oldsheet, newsheet, headers, nickname) ->
    req = 
      action: "Create" 
      headers: @trimSplit(headers)
      sheet: newsheet
    @getDoc msg, oldsheet, (docid, sheetname) =>
      req.id = docid
      @doPost msg, req, (data) =>
        @setDoc msg, req.id, req.sheet, nickname 
        @formatResponse msg, "Added #{nickname} to doc containing #{oldsheet}", data

  appendRow: (msg, nickname, csvdata) ->
    @postReq msg, nickname,
      action: "Append"
      rows: [ @trimSplit(csvdata) ],
      (data) =>
        @formatResponse msg, "Appended row to #{nickname}", data

  createDoc: (msg, docname, sheetname, headers, nickname) ->
    req = 
      id: "NEW"
      name: docname
      sheet: sheetname
      action: "Create"
      headers: @trimSplit(headers)
    @doPost msg, req, (data) =>
      @setDoc msg, data.docid, req.sheet, nickname 
      @formatResponse msg, "Created #{nickname} in new document", data

module.exports = (robot) ->
  robot.brain.once "loaded", () ->
    ssLog.waiting = false

  robot.respond /te use ([^:]*):(.*) as (.*)\s*$/i, (msg) ->
    msg.send "ssLog.setDoc msg, '#{msg.match[1]}', '#{msg.match[2]}', '#{msg.match[3]}'" if ssLog.debug
    ssLog.setDoc msg, msg.match[1], msg.match[2], msg.match[3]

  robot.respond /te (.*) create (?:sheet )*(.*) as (.*) with (.*)\s*$/i, (msg) ->
    msg.send "ssLog.addSheet msg, '#{msg.match[1]}', '#{msg.match[2]}', '#{msg.match[4]}', '#{msg.match[3]}'" if ssLog.debug
    ssLog.addSheet msg, msg.match[1], msg.match[2], msg.match[4], msg.match[3]

  robot.respond /te create (?:doc |document )*(.*) sheet (.*) as (.*) with (.*)\s*/i, (msg) ->
    msg.send "ssLog.createDoc msg, '#{msg.match[1]}', '#{msg.match[2]}', '#{msg.match[4]}', '#{msg.match[3]}'" if ssLog.debug
    ssLog.createDoc msg, msg.match[1], msg.match[2], msg.match[4], msg.match[3]

  robot.respond /te (.*) (?:add|append|new) (?:row )*(.*)\s*/i, (msg) ->
    msg.send "ssLog.appendRow msg, '#{msg.match[1]}', '#{msg.match[2]}'" if ssLog.debug
    ssLog.appendRow msg, msg.match[1], msg.match[2]

  robot.respond /te (.*) get (?:row |rows )*(top|start|[0-9]*)\s*(?:through|to|thru)*\s*(bottom|end|[0-9]*)/i, (msg) ->
    msg.send "ssLog.getByRow msg, '#{msg.match[1]}', '#{msg.match[2]}', '#{msg.match[3]}'" if ssLog.debug
    ssLog.getByRow msg, msg.match[1], msg.match[2], msg.match[3]

  robot.respond /te (.*) get all\s*(?:row|rows)*\s*/i, (msg) ->
    msg.send "ssLog.getByRow msg, '#{msg.match[1]}', \"start\", \"end\"" if ssLog.debug
    ssLog.getByRow msg, msg.match[1], "start", "end"

  robot.respond /te (.*) search (?:col\s|column\s)*(.*) (is|contains|starts with|between) (.*)\s*/i, (msg) ->
    msg.send util.inspect msg.match if ssLog.debug
    switch msg.match[3]
        when "is"
          msg.send "ssLog.getByValue msg, '#{msg.match[1]}', '#{msg.match[2]}', '#{msg.match[4]}'" if ssLog.debug
          ssLog.getByValue msg, msg.match[1], msg.match[2], msg.match[4]
        when "between"
          m = msg.match[4].match /(.*) and (.*)/
          msg.send "ssLog.getByValue msg, '#{msg.match[1]}', '#{msg.match[2]}', '#{m[1]}', '#{m[2]}'" if ssLog.debug
          ssLog.getByValue msg, msg.match[1], msg.match[2], m[1], m[2]
        when "contains"
          msg.send "ssLog.getByContains msg, '#{msg.match[1]}', '#{msg.match[2]}', '#{msg.match[4]}'" if ssLog.debug
          ssLog.getByContains msg, msg.match[1], msg.match[2], msg.match[4]
        when "starts with"
          msg.send "ssLog.getByPrefix msg, '#{msg.match[1]}', '#{msg.match[2]}', '#{msg.match[4]}'" if ssLog.debug
          ssLog.getByPrefix msg, msg.match[1], msg.match[2], msg.match[4]
        else
          msg.reply "Unknown operation '#{msg.match[3]}'"

  robot.respond /te list/i, (msg) ->
    doclist =  msg.robot.brain.get('SS_EV_DOCS')
    colheads = ["Nickname","Document Name","Document Id","Sheet Name"]
    sheets = []
    for k,v of doclist
      sheets.push [k,v.name,v.docid,v.sheet]
    ssLog.formatResponse msg, "Known sheets:",
      items: sheets
      colheads: colheads
      count: sheets.length

  robot.respond /te forget (.*)\s*/i, (msg) ->
    msg.send "ssLog.dropDoc msg, #{msg.match[1]}" if ssLog.debug
    ssLog.dropDoc msg, msg.match[1]

  robot.respond /te (un)*set debug/i, (msg) ->
    if msg.match[1]
        msg.reply "debug output disabled"
        ssLog.debug = false
    else
        msg.reply "debug output enabled"
        ssLog.debug = true

  robot.respond /te inspect (.*)/i, (msg) ->
    eval "obj=#{msg.match[1]}"
    msg.reply "#{util.inspect obj}"
