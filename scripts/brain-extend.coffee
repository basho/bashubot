#description
# Adds functions to the hubot brain
# This is incredibly hacktastic, but since Heroku loads a clean hubot
# I don't have a better way to extend the brain at the moment
#
#dependencies
# hubot
#
#commands
#

module.exports = (robot) ->

    robot.brain.once "loaded", () ->
        robot.brain.userForField = (field, value) ->
            result = null
            lowerVal = "#{value}".toLowerCase()
            for k of (robot.brain.data.users or { })
                userVal = robot.brain.data.users[k][field]
                if userVal? and "#{userVal}".toLowerCase() is lowerVal
                    result = robot.brain.data.users[k]
            result

        robot.brain.setUserField = (id,field,value) ->
            robot.brain.data.users[id][field] = value

        robot.brain.getUserField = (id,field) ->
            robot.brain.data.users[id][field]

