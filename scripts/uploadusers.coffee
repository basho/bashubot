# Description
#  Create users / change passwords for customer accounts on the upload server
#
# Dependencies
#  util
#  child_process
#  rolemanager.coffee
#
# Configuration
#  UPLOAD_USER
#  UPLOAD_HOST
#  UPLOAD_KEY
#  UPLOAD_HOME
#
# Commands
#  hubot (make|create) upload user <name> for ticket [#]<number> - create a user on upload.basho.com and note it in the ticket
#  hubot change password for upload user <name> for ticket [#]<number> - the upload server doesn't support this yet
#  hubot find upload user for ticket [#]<number> - search the organizations' other tickets for upload users created by BashoBot
#

util = require 'util'
_ = require 'underscore'
cp = require 'child_process'

uploadUserMan = 
  user: process.env.UPLOAD_USER
  host: process.env.UPLOAD_HOST
  home: process.env.UPLOAD_HOME
  keyfile: "#{process.env.UPLOAD_HOME}/.ssh/#{process.env.UPLOAD_KEYFILE}"
  writeKey: (msg, fun) ->
    cmd = "sh -c \"[ -d '#{@home}/.ssh' ] || mkdir -p #{@home}/.ssh; chmod 700 #{@home}/.ssh; [ -e #{@keyfile} ] || echo '#{process.env.UPLOAD_KEY}' > #{@keyfile}; chmod 600 #{@keyfile}\""
    msg.robot.logger.info cmd
    response = cp.exec cmd, (error, stdout, stderr) ->
      if error
        msg.reply "Error #{error} creating key file\n#{stdout}\n#{stderr}"
      else
        if fun
          fun()

  userAction: (msg, cmd, name, ticket) ->
    @writeKey msg, () =>
      msg.robot.logger.info "cp.spawn \"ssh\", [\"-i\",@keyfile,\"#{@user}@#{@host}\"]"
      stream = cp.spawn "ssh", ["-i",@keyfile,"#{@user}@#{@host}"]
      stream.stdout.on "data", (data) ->
        re = new RegExp "#{name}:([^ ]*)(.*)\n"
        if m = data.toString().match re
          msg.reply "New user #{name} password #{m[1]}. #{m[2]}.\nPlease copy these details to http://goo.gl/ScbtChPlease copy these details to http://goo.gl/ScbtCh"
          pnote = "Bashobot created an upload.basho.com user '#{name}' with password '#{m[1]}'." if cmd == "Create"
          pnote = "Bashobot changed password for upload.basho.com user '#{name}' with password '#{m[1]}'." if cmd == "Change"
          msg.robot.zenDesk.addComment(msg, ticket, pnote, false) (ticketdata) ->
            msg.reply("Updated ticket #{ticketdata.id}") if id of ticketdata
        else
          msg.reply "#{cmd} failed for user #{name}: #{data}"
      stream.on "close", (code) ->
        if code != 0
          msg.reply "Stream closed with result code #{code}"
      stream.stdin.write("BASHOBOT:#{cmd}:#{name}\n")

  findUser: (msg, ticket) ->
    msg.reply "Searching ZenDesk, please be patient"
    msg.robot.zenDesk.ticketData(msg, ticket) (ticketdata) ->
      org = ticketdata.organization_id
      msg.robot.zenDesk.getOrgName(msg,org) (orgname) ->
        msg.robot.zenDesk.search(msg, {"query":"type:ticket organization:#{org} Bashobot+created+an+upload.basho.com+user Bashobot+changed+password+for+upload.basho.com+user"}) (data) ->
          if data.count == 0
              msg.reply "No upload users found for #{orgname} ticket #{ticketdata.id}"
          else
            tickets = []
            for tick in data.results
              tickets.push("https://basho.zendesk.com/agent/#/tickets/#{tick.id}") if "id" of tick 
            ticklist = tickets.join "\n"
            msg.reply "#{orgname} upload users/passwords found in tickets:\n#{ticklist}"

module.exports = (robot) ->
  robot.um = uploadUserMan

  robot.respond /(?:create|make) upload user (....*) for ticket [#]?([0-9]*)/i, (msg) ->
    uploadUserMan.userAction msg, 'Create', msg.match[1], msg.match[2]
    
  robot.respond /change password for upload user (.*) for ticket [#]?([0-9]*)/i, (msg) ->
    uploadUserMan.userAction  msg, 'Change', msg.match[1], msg.match[2]

  robot.respond /find upload user for ticket [#]?([0-9]*)/i, (msg) ->
    uploadUserMan.findUser msg, msg.match[1] 
