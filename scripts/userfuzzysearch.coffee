#Description:
#  Extend the robot's brain to search for users a little better
#
#Dependencies:
#  hubot-slack
#  underscore
#
#Commands:
#

_ = require 'underscore'
util = require 'util'

module.exports = (robot) ->
  robot.brain.findUsersForFuzzyName = (msg, name, returnfield=null, failmarker=null) ->
      if name is undefined
        name = msg
        msg = undefined
      
      haveUsers = false
      for own key,value of robot.brain.data.users
        haveUsers = true
        break  
      if haveUsers is false
        robot.logger.info "Fetching user list: #{util.inspect robot.brain.basho_slack.updateUserList}"
        robot.logger.info util.inspect robot.brain.basho_slack.updateUserList(msg)
        return []

      fieldlist = [ 
          "name"
          "profile.real_name"
          "profile.first_name"
          "profile.last_name"
          "profile.email"
          ]

      pullField = (object, fieldparts, depth=0) ->
        return "" unless object instanceof Object
        fieldparts = fieldparts.split(".") unless fieldparts instanceof Array
        if fieldparts.length is 1
          if object and object[fieldparts[0]]?
            tag = if depth is 0 and field is "name" then "@" else "" #add @ for mention name since slack doesn't 
            val = object[fieldparts[0]]
            "#{tag}#{val}"
          else
            ""
        else
            part = fieldparts.shift()
            pullField(object[part], fieldparts, depth+1)

      name = name.toUpperCase()
      exact = []
      initial = []
      matched = []

      if msg and name.match /^ME$/i
          exact.push msg.envelope.user
      else 
        for field in fieldlist
          for id, user of robot.brain.data.users
            val = pullField(user, field)
            val = val.toUpperCase() if typeof val is "string"
            if val == name 
               exact.push user
            else if 0 is val.indexOf name
              initial.push user
            else if -1 isnt val.indexOf name
              matched.push user
      if exact.length isnt 0
        resultset = _.uniq exact.sort(), true
      else 
        if initial.length isnt 0
          resultset = _.uniq initial.sort(), true
        else
          resultset = _.uniq matched.sort(), true
      if returnfield
        _.map resultset, (user) -> pullField user, returnfield
      else
        resultset

