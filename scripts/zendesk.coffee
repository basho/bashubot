#  Description
#  Library/API module to permit interaction with ZenDesk
#
# Dependencies
#  util
#  scoped-http-client
#  rolemanager.coffee
#
# Configuration
#  ZENDESKAPI_URL
#  ZENDESKAPI_USER
#  ZENDESKAPI_TOKEN
#
# Commnads
#  hubot set zendesk id for <fuzzy user> to <id> - note numeric ID for later use
util = require 'util'
HttpClient = require 'scoped-http-client'
_ = require 'underscore'

zenDesk = 
  roles: {}
  testing: process.env.TESTING || false
  url: process.env.ZENDESKAPI_URL
  user: process.env.ZENDESKAPI_USER
  token: process.env.ZENDESKAPI_TOKEN

  httpClient: () ->
    HttpClient.create(@url, headers: { 'Authorization': 'Basic ' + new Buffer("#{@user}/token:#{@token}").toString('base64'), 'Accept': 'application/json', 'Content-Type': 'application/json' })

  
  process: (msg, method, fun, field) ->
    (err, res, body) ->
      if err
        msg.reply "Error processing #{method} request: #{err}"
      else
        if res.statusCode == 200
          bodydata = JSON.parse body
          if fun
            if field
              data = bodydata[field]
            else
              data = bodydata
            fun(data)
        else
          msg.reply "HTTP status #{res.statusCode} processing #{method} request: #{body}"
  
  get: (msg, api, field) ->
    (fun) =>
      @httpClient().path(api).get() @process(msg, "GET", fun, field)

  put: (msg, api, data, field) ->
    (fun) =>
      @httpClient().path(api).put(data) @process(msg, "PUT", fun, field)

  post: (msg, api, data, field) ->
    (fun) =>
      @httpClient().path(api).post(data) @process(msg, "POST", fun, field)

  query: (msg, api, qry, field) ->
    (fun) =>
      @httpClient().query(qry).path(api).get() @process(msg, "GET", fun, field)

  userData: (msg, uid) ->
    @get msg, "users/#{uid}.json", "user"

  ticketData: (msg, ticknum) ->
    @get msg,"tickets/#{ticknum}.json","ticket"

  addComment: (msg, ticknum, comment, customercansee) ->
    updateobject = '{"ticket":{"status":"pending","comment":{"public":"'+customercansee+'","body":"'+comment+'"}}}'
    @put msg, "tickets/#{ticknum}.json", updateobject, "ticket"

  getComments: (msg, ticketnum) ->
    @get msg, "tickets/#{ticketnum}/comments.json"

  getOrganization: (msg, orgid) ->
    @get msg, "organizations/#{orgid}.json","organization"

  getOrgName: (msg, orgid) ->
    (namefun) =>
      @getOrganization(msg,orgid) (org) ->
        if namefun
          namefun(org.name)

  search: (msg, queryobj) ->
    @query msg, "search.json", queryobj

  getRoleData: (msg, role) ->
    roleData = @roles[role.toUpperCase()]
    if roleData instanceof Object
      if roleData.setUrl or roleData.getUrl
        return roleData
      else
        msg.reply "Invalid configuration for role '#{role}'"
        return null
    else
        msg.reply "Unknown role '#{role}'"
        return null

  setRole: (msg, n, role) ->
    roleData = @getRoleData(msg, role) 
    name = msg.robot.roleManager.fudgeNames(msg, n, "zendesk_id")
    if roleData.setUrl and roleData.setData
      @parseAction(msg, name, roleData.setData) (actionData) =>
        if @testing
            msg.reply "If I were allowed to set it, I would set #{util.inspect n} as the new #{role}"
        else
          @httpClient().path(roleData.setUrl).put(actionData) (err, res, body) =>
            if err
              msg.reply "Error setting role '" + role + "': " + err
            else
              if res.statusCode == 200
                @showRole(msg, role)
              else
                msg.reply "HTTP status " + res.statusCode + " received setting role '" + role + "':\n" + body

  getUID: (role, msg) ->
    (fun) =>
      roleData = @getRoleData(msg,role)
      if roleData.getUrl and roleData.extractFun
        @httpClient().path(roleData.getUrl).get() (err, res, body) ->
          if err
            msg.reply "Error querying role '" + role + "': " + err
          else
            if res.statusCode == 200
              fun(roleData.extractFun(body))
            else
              msg.reply "HTTP status " + res.statusCode + " received querying role '" + role + "'\n" + body
      else
        msg.reply "I don't know how to check that."

  getRole: (msg, role) ->
    (fun) =>
      @getUID(role,msg) (userid) =>
        @userData(msg, userid) (data) ->
          # map back to a hipchat user by name or id
          byid = _.filter msg.robot.brain.users(), (u) ->
            "#{u.zendesk_id}" == "#{data.id}"
          if byid.length == 1
            fun [byid[0].name]
          else
            byname = _.filter msg.robot.brain.users(), (u) ->
              "#{u.name}" == "#{data.name}"
            if byname.length == 1
              fun [byname[0].name]
            else
              fun [data.name]

  showRole: (msg, role) ->
    @getUID(role,msg) (userid) =>
       @userData(msg, userid) (data) ->
         msg.send "#{role} role is currently occupied by #{data.name}"

  parseAction: (msg, user, action) ->
    (fun) =>
      if "#{user}".match(/^[0-9]*$/)
        client = @httpClient().path("users/#{user}.json")
      else
        client = @httpClient().path('search.json').query("query","name:\"#{user}\" role:agent role:admin")
      client.get() (err, res, body) ->
        if err
          msg.reply "Error searching for user '" + user + "': " + err
        else
          if res.statusCode == 200 
            data = JSON.parse body
            if "user" of data
              u = data.user
            else
              if data.count == 1
                u = data.results[0]
              else
                list=[]
                if data.results instanceof Array
                  for u in data.results
                    list.push("ID: #{u.id}, Name: #{u.name}, Organization: #{u.organization}, Role: #{u.role}")
                msg.reply "Found #{data.count} results for search '#{user}'. Please refine the query. #{list.join('\n')}"
            if u
              parsed = action.replace(/%{user_id}/gi, u.id).replace(/%{user_name}/gi,u.name).replace(/%{user_email}/gi,u.email)
              fun(parsed) if fun
          else
            msg.reply "Received HTTP status " + res.statusCode + " searching for '" + user + "'"

zenDesk.roles = 
  BARCLAY:
      name: "Barclay"
      ratelimit: 1000
      setUrl:'macros/28124595.json',
      setData:'{"macro":{"actions":[{"field":"assignee_id","value":"%{user_id}"}]}}',
      getUrl:'macros/28124595.json',
      extractFun: (data) =>
        act = JSON.parse(data).macro.actions
        userid = -1
        for a in act
          if a.field == "assignee_id"
            userid = a.value
            break
        return userid
      #required functions for rolemanager
      show: (msg) => 
        zenDesk.showRole.call zenDesk, msg, 'Barclay'
      set: (msg, name) =>
        if name instanceof Array
          zenDesk.setRole.call zenDesk, msg, name.join(', '), 'Barclay'
        else 
          zenDesk.setRole.call zenDesk, msg, name, 'Barclay'
      unset: (msg, name) ->
        msg.reply "To unset Barclay role, assign a different person"
      get: (msg) => 
        zenDesk.getRole.call zenDesk, msg, 'Barclay'

module.exports = (robot) ->
  robot.zenDesk = zenDesk

  robot.logger.info "Zendesk role module loading"
  robot.brain.once "loaded", () =>
    if "roleManager" of robot
      for role of zenDesk.roles
        robot.logger.info "Register #{role}: #{robot.roleManager.register(role,zenDesk.roles[role])}"
    else
      robot.logger.info "defer roles"
      robot.roleHook ||= []
      robot.roleHook.push (robot) =>
        for role of robot.zenDesk.roles
          roleData = robot.zenDesk.roles[role]
          robot.logger.info "#{role}: #{robot.roleManager.register role, roleData}"
  
  robot.respond /set zendesk id for (.*) to (.*)$/i, (msg) ->
    msg.robot.roleManager.mapUserName(msg,'zendesk_id',msg.match[1],msg.match[2])

