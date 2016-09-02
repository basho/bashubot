User = require '../node_modules/hubot/src/user'
util = require 'util'

module.exports = (robot) ->
    robot.respond /update slack users/i, (msg) ->
        msg.reply "Getting user list"
        msg.robot.adapter.client.web.users.list {}, (err, users, somethingelse) ->
            if users and users.ok is true
                count = 0
                for user in users.members
                    msg.reply util.inspect user if count == 0
                    newuser = msg.robot.brain.userForId user.id, user
                    msg.robot.logger.info "Updating #{newuser.name}(#{newuser.id}) with #{util.inspect user}"
                    for k of user
                        msg.robot.brain.data.users[newuser.id][k] = user[k]
                    count += 1
                msg.reply "Updated #{count} users"
            else
                msg.robot.logger.error "Can't list users: #{err}"
