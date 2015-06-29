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
fs = require 'fs'

uploadUserMan = 
  user: process.env.UPLOAD_USER
  host: process.env.UPLOAD_HOST
  home: process.env.UPLOAD_HOME
  keyfile: "#{process.env.UPLOAD_HOME}/#{process.env.UPLOAD_KEYFILE}"

  userAction: (msg, cmd, name, ticket) ->
    msg.robot.logger.info "upload user #{cmd} #{name} ticket #{ticket}"
    fs.writeFile "#{@keyfile}","#{process.env.UPLOAD_KEY}", {mode:0o0600}, (err) =>
     msg.robot.logger.info "Keyfile: #{@keyfile} Err: #{err}"
     if err
      msg.reply "Error creating key file"
     else
      cmdstr = "echo -e 'BASHOBOT:#{cmd}:#{name}\n' | ssh -T -o LogLevel=quiet -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i #{@keyfile} bashobot@upload.basho.com"
      cp.exec cmdstr, (error, stdout, stderr) => 
          try 
            re = new RegExp "#{name}:([^ ]*)(.*)\n"
            if m = "#{stdout}".match re
              msg.reply "New user #{name} password #{m[1]}. #{m[2]}.\nPlease copy these details to https://sites.google.com/a/basho.com/handbook/services/projects/customer-uploads"
              pnote = "Bashobot created an upload.basho.com user '#{name}' with password '#{m[1]}'." if cmd == "Create"
              pnote = "Bashobot changed password for upload.basho.com user '#{name}' with password '#{m[1]}'." if cmd == "Change"
              msg.robot.zenDesk.addComment(msg, ticket, pnote, false) (ticketdata) ->
                msg.reply("Updated ticket #{ticketdata.id}") if "id" of ticketdata
            else
              msg.reply "#{cmd} failed for user #{name}: #{stdout}\n#{stderr}"
          catch err 
            msg.reply util.inspect err

  findUser: (msg, ticket) ->
    msg.reply "Searching ZenDesk, please be patient"
    msg.robot.zenDesk.ticketData(msg, ticket) (ticketdata) ->
      org = ticketdata.organization_id
      msg.robot.zenDesk.getOrgName(msg,org) (orgname) ->
        msg.robot.zenDesk.search(msg, {"query":"type:ticket organization:\"#{org}\" Bashobot+created+an+upload.basho.com+user Bashobot+changed+password+for+upload.basho.com+user"}) (data) ->
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
