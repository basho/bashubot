#description:
# updateusers - update the user list in the brain
#
#commands:
# hubot update hipchat users - pull new user roster from Hipchat

User = require '../node_modules/hubot/src/user'

module.exports = (robot) ->
  robot.respond /update hipchat users/i, (msg) ->
    msg.robot.adapter.connector.getRoster (err, users, stanza) =>
      if users
        for user in users
          newuser = msg.robot.brain.userForId msg.robot.adapter.userIdFromJid(user.jid), user
          msg.robot.logger.info "Updating #{newuser.name}(#{newuser.id}) with #{user}"
          for k of user
            msg.robot.brain.data.users[newuser.id][k] = user[k]
      else
        msg.robot.logger.error "Can't list users: #{err}"

