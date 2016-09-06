#Description:
#  scripts for debugging bashubot-slack integrations
#
#Commands:
#
#

util = require 'util'

module.exports = (robot) ->

  robot.hear /(.*)/i, (msg) ->
    msg.robot.logger.info "Received #{msg.envelope.room}:#{msg.message.text}"


