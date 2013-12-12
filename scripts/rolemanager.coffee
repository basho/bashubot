# Description:
#   Central dispater for named roles.
#
# Dependencies:
#   util
#   underscore
#
# Configuration:
#   none
#
# Commands:
#   hubot show [me] (all|named) roles - show all roles with occupants
#   hubot put <name> in <role> role - designate name as an occupant of role
#   hubot remove <name> from <role> role - remove name from role
#   hubot summon <role> - summon role occupants by mention name
#   hubot (who is|show [me]) <role> - show occupant of role
#   hubot create role <role> - create a role for tracking/summoning, no integration with external APIs
#
util = require 'util'
_ = require 'underscore'

roleManager = {
#to support varied roles and actions, each role must have the following functions defined:
#  show(msg) - send current role occupant(s) in a msg.reply
#  set(msg, <name/names>) - change current occupant(s)i
#  unset(msg, <name/names>) - remove specified occupant(s)
#  get(msg) - returns a function that accepts (callback) where callback will be called as callback(<array of names>)
#   after retrieving the list of occupants
# 
#  msg should be a hubot msg structur, name should be a comma delimited string or array
#
#  other action functions may be defined as needed 

    register: (name,data) ->
      if "show" of data and "set" of data and "unset" of data and "get" of data
        roleManager.roles[name] = data
        return true
      else 
        return false
     roles: {}

    getRoleData: (role,msg) ->
      roleData = @roles[role.toUpperCase()]
      if roleData instanceof Object
        if roleData.show and roleData.set and roleData.unset
          return roleData
        else
          msg.reply "Invalid configuration for role '#{role}'"
          return false
      else
          msg.reply "Unknown role '#{role}'"
          return false

    action: (msg, act, role, name) ->
      #some external APIs have aggrtessive rate limits
      #so limit to 1 role action every 5 seconds
      if last = msg.robot.brain.get("LastRoleChange")
        last = 0
      now = Date.now()
      if now - last > 5000
        if roleData = @getRoleData role, msg 
          if roleData[act]
              msg.robot.brain.set("LastRoleChange",Date.now())
              roleData[act] msg, name 
          else
              msg.reply "Unkown method '#{act}' for role '#{role}'"
      else
        delay = last + 5000 - now
        msg.reply "Schedule #{act} #{role} #{name} in #{delay} ms"
        delaymod = () ->
          msg.reply "#{act} #{role} #{name}"
          msg.robot.roleManager.action(msg,act,role,name);
        setTimeout delaymod, delay

    isRole: (role) -> @roles.hasOwnProperty role.toUpperCase()

    showAllRoles: (msg) ->
      for own r,roleData of @roles
          roleData.show msg

    fudgeNames: (msg,names,field) ->
      mapUsers = (users,name,step) ->
        if users.length is 0
          users = msg.robot.brain.data.users
        switch step
          #step 1 - name match
          when 1 then users = msg.robot.brain.usersForFuzzyName(name)
          #step 2 - mention name match
          when 2 then users = _.filter users,(u) ->
                          u.mention_name == name or "@#{u.mention_name}" == name
          #step 3 - jabber id match
          when 3 then users = _.filter user,(u) ->
                          u.jid == name
          #step 4 - match requested field
          when 4 then users = _.filter user, (u) ->
                          "#{u[field]}" == "#{name}"
          else
              users = [null]
        return users

      if names not instanceof Array
        names = names.split(',')
      field ||= "name"
      found = []
      for name in names
        if name.match /me/i
            name = msg.envelope.user.name
        step = 1
        users = msg.robot.brain.data.users
        while users.length isnt 1
          users = mapUsers(users,name,step)
          step = step + 1
        if users[0] == null
          found.push name
        else
          user = users[0]
          if field of user
              found.push user[field]
          else
              found.push user.name
      return found

  mapUserName: (msg, field, name, mapname) ->
    users = msg.robot.brain.usersForFuzzyName name
    if users.length is 0
        ids = msg.robot.roleManager.fudgeNames msg,name,'id'
        list = _.map ids, (i) ->
                           msg.robot.brain.users[i] 
        users = _.filter list, (u) ->
                                  return (u instanceof Object)
    if users.length is 0
        msg.reply "No user found for '#{name}'"
    else if users.length > 1
        msg.reply "Multiple matches for '#{name}' #{(_.map users,(u) -> u.name).join(',')}"
    else if users.length is 1
        user = users[0]
        msg.robot.brain.data.users[user.id][field] = mapname
        msg.send "Set #{field} for #{user.name}(@#{user.mention_name}) to '#{mapname}'"

  simpleModify: (msg, role, name, op) ->
    roletag = "role-#{role.toUpperCase()}"
    name = name.split(",") unless name instanceof Array
    names = @fudgeNames(msg, name, "name")
    msg.robot.brain.set roletag, op(msg.robot.brain.get(roletag),names)
    msg.send "#{role} is currently occupied by #{msg.robot.brain.get roletag}"

  createRole: (msg, role) ->
    rolename = role.toUpperCase()
    if @isRole(rolename) 
      msg.reply "Role #{role} already exists"
    else
      dynroles = msg.robot.brain.get("dynamic_roles")
      dynroles = [] unless dynroles instanceof Array
      @register rolename, {
        show: (msg)=>
          names = msg.robot.brain.get "role-" + rolename
          if names.length > 0
            msg.send "#{role} is currently occupied by #{names}"
          else
            msg.send "#{role} is currently unoccupied"
        set: (msg, name) =>
          @simpleModify(msg, role, name, _.union)
        unset: (msg, name) =>
          @simpleModify(msg, role, name, _.difference)
        get: (msg) ->
          (fun) ->
            fun msg.robot.brain.get "role-" + rolename 
        clear: (msg) ->
          msg.robot.brain.set "role-" + rolename, []
      }
      dynroles =  _.union dynroles, role
      msg.robot.brain.set "dynamic_roles", dynroles
      msg.robot.brain.set("role-#{rolename}", []) unless msg.robot.brain.get("role-#{rolename}") instanceof Array
      msg.send "Created role #{rolename} - occupied by #{@action(msg, 'get', role) (data) -> data}"

  deleteRole: (msg, role, force) ->
    if @isRole(role)
      rolename = role.toUpperCase()
      dynroles = msg.robot.brain.get "dynamic_roles"
      if rolename in dynroles
        names = msg.robot.brain.get "role-" + rolename
        names = [] unless names instanceof Array
        if names.length is 0 or force
          msg.robot.brain.remove "role-" + rolename
          msg.robot.brain.set "dynamic_roles", _.difference dynroles, rolename
          delete @roles[rolename]
          msg.send "Deleted role #{role}"
        else
          msg.reply "Role #{role} is occupied"
      else
        msg.reply "Role #{role} was not dynamically created"
    else
      msg.reply "Unknown role #{role}"

  deleteEmpty: (msg) ->
    dynroles = msg.robot.brain.get("dynamic_roles") || []
    ignore = () ->
     return
    for role in dynroles
      @deleteRole {"robot":msg.robot, "reply": ignore, "send": ignore}, role
    newroles = msg.robot.brain.get("dynamic_roles") || []
    msg.send "Purged empty roles"
    msg.send "Removed roles #{_.difference(dynroles,newroles).join ", "}" if dynroles.length isnt newroles.length

  loadRoles: (robot) ->
    dynroles = robot.brain.get("dynamic_roles")
    if dynroles instanceof Array
      dummy = {
        reply: (m) ->
          return
        send: (m) ->
          return
        robot: robot
      }
      for role in dynroles
        robot.logger.info "Load dynamic role '#{role}'"
        @createRole dummy, role
}

module.exports = (robot) ->
  robot.logger.info "Loading role manager"
  robot.roleManager = roleManager
  robot.brain.once "loaded", =>
    roleManager.loadRoles(robot)

  if "roleHook" of robot
    if robot.roleHook instanceof Array
      robot.logger.info "Deferred role registraion"
      hook(robot) for own hook in robot.roleHook
      delete robot.roleHook

  robot.respond /create role ([^ ]*) *$/i, (msg) ->
    roleManager.createRole msg, msg.match[1]

  robot.respond /(?:delete|destroy) role ([^ ]*) *$/i, (msg) ->
    roleManager.deleteRole msg, msg.match[1]

  robot.respond /(?:delete|destroy) empty roles? *$/i, (msg) ->
    roleManager.deleteEmpty(msg)
  robot.respond /(?:who is|show(?: me)?) (all roles|named roles|[^ ]*)\??/i, (msg) ->
    if msg.match[1] is "all roles" or msg.match[1] is "named roles"
      roleManager.showAllRoles msg
    if roleManager.isRole msg.match[1]
      roleManager.action msg, 'show', msg.match[1]

  robot.respond /put \s*(.*) \s*in \s*([^ ]*) role\s*/i, (msg) ->
    roleManager.action msg, 'set', msg.match[2], msg.match[1]

  robot.respond /remove \s*(.*) \s*from \s*([^ ]*) \s*role\s*/i, (msg) ->
    roleManager.action msg, 'unset', msg.match[2], msg.match[1]

  robot.respond /summon \s*([^ ]*)\s*/i, (msg) ->
    role = msg.match[1]
    if roleManager.isRole role
      roleManager.action(msg, 'get', role) (names) ->
        names = [] unless names instanceof Array
        if names.length > 0
          ids = msg.robot.roleManager.fudgeNames msg,names,'id'
          list = _.map ids, (u) ->
                        msg.robot.brain.data.users[u]
          users = _.filter list, (i) ->
                             i instanceof Object
          for user in users
            if "mention_name" of user
              msg.send "@#{users[0].mention_name} " + msg.random([
                       "From the depths of Hell, I summon thee!",  
                       "Please report to the bridge.",  
                       "Your presence is requested in #{msg.message.room}.",  
                       "I summon thee!",  
                       "Come hither!",  
                       "Make it so!",
                       "Resistance is futile",
                       "Peek-a-Boo",  
                       "Ooo Ee Ooo Ah Ah",  
                       "Ego vocare te!",  
                       "Get over here!", 
                       "Come out, come out, where ever you are!", 
                       "Ping", 
                       "Marco",
                       "Prepare to beam up", 
                       "Live long and prosper", 
                       "Perhaps today *is* a good day to die"
                       "The needs of #{msg.message.room} outweigh the needs of the few, or the one",
                       "#{msg.envelope.user['mention_name']} is looking for you in #{msg.envelope.room}!" ])
        else
          msg.reply "No mention names found for role #{role}, #{names}"
