# Updates who is currently on-call and receives SMS notifications from
# the automation app.
#
# show me on-call - list who is on-call
# put <name>[ ,<name>...] on-call - add people to the on-call list
# remove <name>[ ,<name>...] from on-call - remove people from the on-call list
# reset on-call - resets to nobody on-call

util = require 'util'
HttpClient = require 'scoped-http-client'
_ = require 'underscore'

onCall =
  url: process.env.ESCALATION_URL
  user: process.env.ESCALATION_USER
  password: process.env.ESCALATION_PASSWORD
  http: () ->
    HttpClient.create(@url, headers: { 'Authorization': 'Basic ' + new Buffer("#{@user}:#{@password}").toString('base64') }).path("/on-call")
  list: (msg) ->
    @http().get() (err, res, body) ->
      if err
        msg.reply "Sorry, I couldn't get the on-call list: #{util.inspect(err)}"
      else
        msg.reply ["Here's who's on-call:", body.trim().split("\n").join(", ")].join(" ")
  modify: (msg, people, op) ->
    http = @http()
    http.get() (err,res,body) =>
      if err
        msg.reply "Sorry, I couldn't get the on-call list: #{util.inspect(err)}"
      else
        newOnCall = op(body.trim().split("\n"), people)
        http.header('Content-Type', 'text/plain').put(newOnCall.join("\n")) (err, res, body) ->
          if err
            msg.reply "Sorry, I couldn't set the new on-call list to #{newOnCall.join(', ')}: #{util.inspect(err)}"
          else
            msg.reply "Ok, I updated the on-call list."
            @list(msg)

module.exports = (robot) ->

  robot.hear /who is on[- ]call\??/i, (msg) ->
    msg.robot.logger.info "Checking on-call."
    onCall.list(msg)

  robot.respond /show me on[- ]call\??/i, (msg) ->
    msg.robot.logger.info "Checking on-call."
    onCall.list(msg)

  robot.respond /put (.*) on[- ]call\s*/i, (msg) ->
    people = msg.match[1].trim().split(/\s*,\s*/)
    msg.robot.logger.info "Adding #{util.inspect people} to on-call list"
    onCall.modify(msg, people, _.union)

  robot.respond  /remove (.*) from on[- ]call\s*/i, (msg) ->
    people = msg.match[1].trim().split(/\s*,\s*/)
    msg.robot.logger.info "Removing #{util.inspect people} from on-call list"
    onCall.modify(msg, people, _.difference)

  robot.respond  /reset on[- ]call\s*/i, (msg) ->
    msg.robot.logger.info "Removing all from on-call list"
    onCall.modify(msg, ["Justin Pease"], _.intersection)
