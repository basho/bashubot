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
#  hubot (make|create) upload user <name> for ticket [#]<number> - create a user on upload.basho.com and note it in the ticket and organization record
#  hubot change password for upload user <name> for ticket [#]<number> - generate a new password for the upload user
#  hubot validate upload user <name> password <password> for ticket [#]<number>- test sftp authentication 
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

  userAction: (msg, cmd, name, password, ticket) ->
    if ticket is undefined
      ticket = password 
      password = ""
      passwordarg = ""
    else
      passwordarg = ":#{password}"
    msg.robot.logger.info "upload user #{cmd} #{name} ticket #{ticket}"
    fs.writeFile "#{@keyfile}","#{process.env.UPLOAD_KEY}", {mode:0o0600}, (err) =>
     msg.robot.logger.info "Keyfile: #{@keyfile} Err: #{err}"
     if err
      msg.reply "Error creating key file"
     else
      cmdstr = "echo -e 'BASHOBOT:#{cmd}:#{name}#{passwordarg}\n' | ssh -T -o LogLevel=quiet -o UserKnownHostsFile=/dev/null -o StrictHostKeyChecking=no -i #{@keyfile} bashobot@upload.basho.com"
      cp.exec cmdstr, (error, stdout, stderr) => 
          try 
            re = new RegExp "#{name}:([^ ]*)(.*)\n"
            if m = "#{stdout}".match re
              switch cmd
                  when "Create"
                    msg.reply "New user #{name} password #{m[1]}. #{m[2]}.\nPlease copy these details to https://sites.google.com/a/basho.com/handbook/services/projects/customer-uploads"
                    password = m[1]
                    pnote = "Bashobot created an upload.basho.com user '#{name}' with password '#{m[1]}'."
                  when "Change"
                    msg.reply "User #{name} new password #{m[1]}. #{m[2]}.\nPlease copy these details to https://sites.google.com/a/basho.com/handbook/services/projects/customer-uploads"
                    password = m[1]
                    pnote = "Bashobot changed password for upload.basho.com user '#{name}' with password '#{m[1]}'."
                  when "Validate"
                    msg.reply "Validate user #{stdout}"
              if pnote isnt undefined
                msg.robot.zenDesk.addComment(msg, ticket, pnote, false) (ticketdata) ->
                  msg.reply("Updated ticket #{ticketdata.id}") if "id" of ticketdata
                  msg.robot.zenDesk.updateOrgFields(msg, ticketdata.organization_id, {"upload_user":name, "upload_password":password}) (org) ->
                    msg.reply("Updated organization record for #{org.name}")
            else
              msg.reply "#{cmd} failed for user #{name}: #{stdout}\n#{stderr}"
          catch err 
            msg.reply util.inspect err

  findUser: (msg, ticket) ->
    msg.robot.zenDesk.ticketData(msg, ticket) (ticketdata) =>
      org = ticketdata.organization_id
      msg.robot.zenDesk.getOrgFields(msg, org,  ["upload_user","upload_password"]) (resultobj) =>
        if resultobj? and resultobj.upload_user? and resultobj.upload_password?
            msg.reply "Found user in organization data: User: #{resultobj.upload_user} Password: #{resultobj.upload_password}"
            @userAction msg, "Validate", resultobj.upload_user, resultobj.upload_password, ticket
        else
          msg.reply "Searching ZenDesk, please be patient"
          msg.robot.zenDesk.getOrgName(msg,org) (orgname) ->
            squery = "type:ticket organization:#{org} description:Bashobot+created+an+upload.basho.com+user description:Bashobot+changed+password+for+upload.basho.com+user"
            msg.robot.logger.info "search query: \"#{squery}\""
            msg.robot.zenDesk.search(msg, {"query":squery}) (data) ->
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

  robot.respond /validate upload user (....*) password (..*) for ticket \#*([0-9]*)/i, (msg) ->
    uploadUserMan.userAction msg, 'Validate', msg.match[1], msg.match[2], msg.match[3] 
