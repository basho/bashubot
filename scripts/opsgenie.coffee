#Description:
#  On-demand paging via opsgenie with user data pulled from Slack
#
#Dependencies:
#  scoped-http-client
#  underscore
#  util
#  
#Configuration:
#  OPSGENIE_API_KEY
#  OPSGENIE_API_URL
#
#Commands:
#  hubot page <fuzzyname> message <text> - send page, text limited to 130 characters
#  hubot who is on-call
#


HttpClient = require 'scoped-http-client'
_ = require 'underscore'
util = require 'util'

OpsGenie = 

  apiKey: process.env.OPSGENIE_API_KEY
  url: process.env.OPSGENIE_API_URL

  httpClient: (contentType = "application/json", customHeaders = {}) ->
    headerObj =  {
                    'Accept': 'application/json',
                    'Content-Type': contentType
                  }
    for k of customHeaders
        headerObj[k] = customHeaders[k]
    HttpClient.create(@url, headers: headerObj)

  get: (msg, api, field, queryObject) ->
    (fun) =>
      if field instanceof Object
        queryObject = field
        field = undefined
      client = @httpClient().path(api).query('apiKey',@apiKey)
      client.query(key,queryObject[key]) for key of queryObject 
      client.get() @process(msg, "GET", fun, field)

  put: (msg, api, data, field) ->
    (fun) =>
      data.apiKey = @apiKey unless data.apiKey
      @httpClient().path(api).put(data) @process(msg, "PUT", fun, field)

  post: (msg, api, data, field) ->
    (fun) =>
      data.apiKey = @apiKey unless data.apiKey
      @httpClient().path(api).post(JSON.stringify(data)) @process(msg, "POST", fun, field)

  query: (msg, api, qry, field) ->
    (fun) =>
      @httpClient().query(qry).path(api).get() @process(msg, "GET", fun, field)

  process: (msg, method, fun, field) ->
    (err, res, body) ->
      if err
        msg.reply "Error processing #{method} request: #{err}"
      else
        if res.statusCode is 200 or 201
          bodydata = JSON.parse body
          if bodydata.ok? and  bodydata.ok isnt true
            msg.reply "Server responded code:#{res.statusCode} ok:#{bodydata.ok}"
            msg.send util.inspect bodydata
          else
            if fun
              if field
                data = bodydata[field]
                if data is undefined
                  msg.reply "HTML response did not contain field #{field}"
                  msg.robot.logger "HTML response did not contain field #{field}"
                  msg.robot.logger util.inspect(body)
              else
                data = bodydata
              fun(data)
        else if res.statusCode is 204
          fun() if fun
        else
          msg.reply "HTTP status #{res.statusCode} processing #{method} request: #{body}"

  getCurrentOnCall: (msg, listId) ->
    (fun) =>
      @get(msg, "schedule/whoIsOnCall", { id: listId }) (response) ->
        names=[]
        if response?.participants?
          for o in response.participants
             person = msg.robot.brain.findUsersForFuzzyName(msg, o.name, "profile.real_name") 
             person = [o.name] unless person.length is 1
             names.push(person[0])
        fun(names)

  getScheduleList: (msg) ->
    (fun) =>
      @get(msg, "schedule") (response) ->
        if response?.schedules?
          schedules = []
          for schedule in response.schedules
            schedules[schedule.id] = schedule.name
          fun(schedules)
        else
          msg.reply("Error getting schedule list from OpsGenie")
        

  sendPage: (msg, ids, message, description = "", tags="OverwritesQuietHours") ->
    ids = ids.join "," if ids instanceof Array
    req = {
            "recipients":ids
            "tags":tags
            "message":message
            "description":description
          }
    @post(msg, "alert", req) (response) ->
      if response.status and response.status is "successful"
        msg.reply "Page sent to #{ids}"
      else
        msg.reply "Page failed: #{util.inspect response}"
    

  doPage: (msg, names, message=null) ->
    #slack specific - if we ever make a slack script move this over there
    if msg.envelope.room[0] is 'D'
      channel = "Private Chat"
    else
      if not msg.robot.brain.data.slack_channels?[msg.envelope.room]?
        msg.reply("Updating slack channel list, please try again in a moment")
        msg.robot.brain.basho_slack.updateChannelList(msg)
        return false;
      channel = msg.robot.brain.data.slack_channels[msg.envelope.room] ? "Unknown Channel '#{msg.envelope.room}'" 
    if message is null
      msg.reply "No message text found"
      return false
    text = "Page requested by #{msg.envelope.user.profile.real_name}"
    text = " #{text} in channel #{channel}" if channel?
    text = "#{text}: #{message}"
    names = names.split(",") unless names instanceof Array
    recipients = []
    for name in names
      name = name.trim()
      found = msg.robot.brain.findUsersForFuzzyName(msg, name)
      if found.length is 1
        recipients.push (found[0]).profile.email
      else if found.length is 0
        msg.reply "No matches found for #{name}"
      else 
        msg.reply "Multiple matches found for #{name}: #{_.map(found,(u)->"#{u.profile.real_name}(#{u.profile.email})").join ',\n'}"
    if recipients.length > 0
        @sendPage msg, recipients, text.substring(0,129), text

  displayList: (msg, head) ->
    (items) ->
      msg.send("#{head}: #{items.join(", ")}")

  displayOnCall: (msg, namesearch='') ->
    @getScheduleList(msg) (schedules) =>
      for s of schedules
        if namesearch isnt ''
          re = new RegExp namesearch, "i"
        if !re or schedules[s]?.match? re
          msg.robot.logger.info("Checking on call for #{schedules[s]}(#{s})")
          @getCurrentOnCall(msg, s) @displayList(msg, schedules[s])
 
module.exports = (robot) ->

  robot.respond /page \s*(.*) \s*message \s*(.*)/i, (msg) ->
    msg.robot.logger.info "Paging #{msg.match[1]}"
    OpsGenie.doPage msg, msg.match[1], msg.match[2]

  robot.respond /page (.*)/i, (msg) ->
    if not msg.match[1].match /.* message .*/
      msg.reply "please include a message - `page <name>[,<name>] message <text>`"

  robot.respond /(?:who is|show me) on[- ]?call\?? *(?:in|for|at)? *(.*)$/i, (msg) ->
      msg.robot.logger.info "Checking on-call."
      OpsGenie.displayOnCall(msg,msg.match[1])

  robot.respond /ops test (.*)/i, (msg) ->
      eval "obj=#{msg.match[1]}"
      msg.reply "#{util.inspect obj}"
