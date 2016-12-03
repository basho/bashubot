#Description
#  miscellaneous slack specific functions
#
#Dependencies
#  hubot-slack
#  underscore
#
#Commands
#  hubot update slack users - get user list from Slack
#  hubot update slack (rooms|channels)
#
#Configuration
#


User = require '../node_modules/hubot/src/user'
_ = require 'underscore'
util = require 'util'

Slack = 
  robot: undefined
  updateUserList: (msg) ->
    @robot = msg.robot unless @robot
    msg.reply "Getting user list" if msg
    @robot.adapter.client.web.users.list {}, (err, users) =>
      if users?.ok is true
        count = 0
        for user in users.members
          count += 1
          newuser = @robot.brain.userForId user.id, user
          for k of user
            @robot.brain.data.users[newuser.id][k] = user[k]
        msg.reply "Updated #{count} users" if msg
      else
        @robot.logger.error "Error listing users: #{err}"
        msg.reply "Error listing users: #{err}" if msg

  updateChannelList: (msg, callback) ->
    @robot = msg.robot unless @robot
    msg.reply "Getting channel list" if msg
    @robot.adapter.client.web.channels.list {}, (err, data) =>
      if data?.ok is true
        updated = 0
        removed = 0
        @robot.brain.data.slack_channels ||= {}
        for channel in data.channels
          if channel.is_archived
            if @robot.brain.data.slack_channels[channel.id]
              removed += 1
              delete @robot.brain.data.slack_channels[channel.id]
          else
            updated += 1
            @robot.brain.data.slack_channels[channel.id] = channel.name
        text = "Updated #{updated} channels"
        text +=", removed #{removed} archived channels" if removed > 0
        msg.reply text if msg
        callback?(data) 
      else
        @robot.logger.error "Error listing channels: #{err}"
        msg.reply "Error listing channels: #{err}" if msg


module.exports = (robot) ->
    Slack.robot = robot
    robot.brain.basho_slack = Slack

    robot.respond /update slack users?/i, Slack.updateUserList

    robot.respond /update slack (room|channel)s?/i, Slack.updateChannelList
               
