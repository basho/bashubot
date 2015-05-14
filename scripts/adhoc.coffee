#description:
# adhoc - manage one-off changes to the on call schedule
#
#dependencies:
# cron
# crypto
# time
# underscore
# util
# updateusers.coffee
# redirector.coffee
#
#configuration
#  ADHOC_DEBUG
#  ADHOC_SECRET
#  ADHOC_URL
#  ADHOC_DOCID
#  ADHOC_SHEET
#
#commands:
# hubot set my timezone to <timezone> - specify timezone to use when interacting with adhoc schedules
# hubot list timezones <prefix> - list all available timezones that start with <prefix>
# hubot cover <name> with <name> from <datetime> to <datetime>
#

cron = require 'cron'
crypto = require 'crypto'
time = require 'time'
_ = require 'underscore'
util = require 'util'
api = require '../customlib/redirector.coffee'

class Adhoc 
    debug: process.env.ADHOC_DEBUG || 0
    chatdebug: false
    docid: process.env.ADHOC_DOCID
    sheetname: process.env.ADHOC_SHEET
    waiting: true

    intValue: (value) ->    
        if typeof value is 'number'
            value
        if typeof value is 'string'
            if "#{parseInt(value)}" is value
                parseInt(value)
            else
                if value.toLowerCase in ['true','on','yes']
                    1
                else
                    0
    setDebug: (value) ->
        @debug = @intValue(value)

    setChatDebug: (value) ->
        @chatdebug = @intValue(value)

    debugMsg: (msg, text, level=7) ->
        return unless @debug
        if @debug >= level
            logmsg = "ADHOC DEBUG: #{text}"
            msg.send logmsg if @chatdebug
            msg.robot.logger.info logmsg if @debug > 0

    addAuth: (req) ->
        docid = req.id
        dt = new Date
        md5sum = crypto.createHash('md5')
        md5sum.update "#{process.env.ADHOC_SECRET}#{dt}#{docid}"
        req.date = "#{dt}"
        req.data = "#{md5sum.digest 'base64'}"
        req

    trimSplit: (csvstr) ->
        csvstr.split(",")
        .map (i) ->
            i.trim()

    formatResponse: (msg,txt,data) ->
        if "count" of data
          lines = []
          size = []
          datarow = []
          size = for head in data.colheads
            datarow.push "#{head}"
            "#{head}".length
          lines.push datarow
          for row in data.items
            datarow = []
            i = 0
            for r in row
              size[i] ||= 0
              if "#{r}".length > size[i]
                size[i] = "#{r}".length
              datarow.push "#{r}"
              i += 1
            lines.push datarow
          response = "/quote #{txt}\n"
          for l in lines
            sizedrow = []
            i = 0
            for f in l
              if f.length < size[i]
                f = "#{f}#{Array(size[i] - f.length + 1).join ' '}"
              sizedrow.push f
              i += 1
            response += "#{sizedrow.join(', ')}\n"
          msg.send response
        else
          msg.reply "Unexpected response: #{util.inspect data}"


    postReq: (msg, req, pfun) ->
        req.id = @docid
        req.sheet = @sheetname
        @doPost msg, req, pfun

    doPost: (msg, req, reqfun) ->
        @debugMsg msg, "doPost(msg,#{JSON.stringify(req)}, reqfun)", 1
        request = 
          data: @addAuth req
          url: "#{process.env.ADHOC_URL}"
          method: "post"
          headers: { "Content-Type":"application/x-www-form-urlencoded", "Accept":"*/*" }
        @debugMsg msg, JSON.stringify request, 2
        api.do_request request, (err, res, body) ->
          if res.statusCode == 200
            reqfun(JSON.parse(body)) if reqfun
          else
            msg.reply "Error #{res.statusCode}\n#{body}"
    
    getByRow: (msg, fromrow, torow) ->
        torow = fromrow if not torow or torow is ""
        @postReq msg, 
          action: "Filter"
          filters: [{fromrow:fromrow, torow:torow}], (data) =>
            @formatResponse msg, "Retrieved rows #{fromrow} through #{torow}", data
    
    getByValue: (msg, column, value1, value2) ->
        if value2
          filter = {col:column, rangefrom:value1, rangeto:value2}
          textMsg = "Search for #{column} between #{value1} and #{value2}"
        else
          filter = {col:column, value:value1}
          textMsg = "Search #{column} for #{value1}"
        @postReq msg, 
          action: "Filter"
          filters: [filter], (data) =>
            @formatResponse msg, textMsg, data
    
    getByPrefix: (msg, column, value) ->
        @postReq msg, 
          action: "Filter"
          filters: [{col:column ,prefix:value}], (data) =>
            @formatResponse msg, "Search for #{column} starting with #{value}", data
    
    getByContains: (msg, column, value) ->
        @postReq msg, 
          action: "Filter"
          filters: [{col:column, contains:value}], (data) =>
            @formatResponse msg, "Search for #{column} containing #{value}", data
    
    appendRow: (msg, csvdata) ->
        @postReq msg, 
          action: "Append"
          rows: [ @trimSplit(csvdata) ],
          (data) =>
            @formatResponse msg, "Appended row to #{nickname}", data

    getTimezone: (msg, retry=true) ->
        @debugMsg msg, "getTimezone #{util.inspect msg.envelope.user}, #{retry}", 1
        user = msg.robot.brain.userForField 'jid', msg.envelope.user.jid
        if user is null and retry is true
    #     if we don't have a user record, request an update from hipchat
    #     this requires that updateusers.coffee be loaded
            newmsg = msg.dup()
            newmsg.text = "@bashobot update hipchat users"
            newmsg.robot.router.handle(newmsg)
            @getTimezone(msg, false)
        if user
            return user.timezone || 'UTC'
        else
    #     this should never happen
            msg.send("Did not find user #{msg.envelope.user.name}, default to UTC")
            return 'UTC'
    
    listTimezones: (msg, zone='', callback) =>
        @debugMsg msg, "listTimezones #{util.inspect msg.envelope.user}, #{util.inspect zone}", 2
        verify = (err,zones) =>
          if err is null
            realZone = []
            for z in zones
                realZone.push(z) if z.toLowerCase().match(zone.toLowerCase())
            msg.reply "No timezone found matching #{zone}" if realZone.length is 0
            msg.reply "Multiple timezones found matching #{zone}:#{util.inspect realZone}" if realZone.length > 1
            callback? msg, realZone[0], @ if realZone.length is 1
          else
            msg.send("Error getting list of time zones: #{err}")
        time.listTimezones(verify)
   
    setTimezone: (msg, zone) =>
        @debugMsg msg, "setTimezone #{util.inspect msg.envelope.user}, #{util.inspect zone}", 1
        @listTimezones msg, zone, @setTimezoneVerified

    setTimezoneVerified: (msg, zone, me) =>
        @debugMsg msg, "setTimezoneVerified #{util.inspect msg.envelope.user}, #{util.inspect zone}", 1
        oldZone = @getTimezone(msg)
        if oldZone is zone
            msg.reply "Keeping timezone: #{oldZone}"
        else
            user = msg.robot.brain.userForField 'jid', msg.envelope.user.jid
            if user
                msg.robot.brain.setUserField user.id, 'timezone', zone
                msg.reply "Changed timezone from #{oldZone} to #{@getTimezone(msg)}"
            else
                msg.reply "Unable to retrieve user record"
    
    date2epoch: (str,zone='UTC') ->
        @debugMsg msg, "date2epoch #{util.inspect str}, #{util.inspect zone}", 1
        dt = null
        return str if typeof str is not 'string'
        dt = Date.parse((new time.Date).setTimezone(zone).toDateString()) if /today/i.test str
        dt = (new time.Date()).setTimezone(zone).getTime() + 86400000 if /tomorrow/i.test str
        dt = dt ? Date.parse(new time.Date(str,zone))
        if isNaN dt
            dt = parseInt(str)
        return dt
    
    epoch2ISO: (epoch, zone='UTC') ->
        @debugMsg msg, "epoch2ISO #{util.inspect epoch}, #{util.inspect zone}", 3
        i = epoch
        if typeof i is 'string'
          i = parseInt(epoch)
        d = new time.Date(i,zone)
        "#{d.toDateString()}T#{d.toTimeString().replace(/\ .+/,'')} #{dt.getTimezoneAbbr()}"
    
    epoch2Date: (epoch, zone) ->
        @debugMsg msg, "epoch2Date #{util.inspect epoch}, #{util.inspect zone}", 1
        @epoch2ISO(epoch,zone).replace(/T.+/, '')
    
    epoch2DateTime: (epoch, zone) ->
        @debugMsg msg, "epoch2DateTime #{util.inspect epoch}, #{util.inspect zone}", 1
        @epoch2ISO(epoch, zone).replace(/T/, ' ')

    getSchedule: (msg) ->
        @getByRow(msg, 'TOP', 'BOTTOM')
   
adhoc = new Adhoc

module.exports = (robot) ->
    robot.respond /get adhoc( schedule)*/i, (msg) ->
        adhoc.getSchedule(msg)

    robot.respond /set my timezone (?:to)*\s*([^ ]*)/i, (msg) ->
        adhoc.setTimezone msg, msg.match[1]

    robot.respond /list timezones*/i, (msg) ->
        if msg.envelope.room
            msg.reply "Please repeat request in a private chat room"
        else
            adhoc.listTimezones(msg, '') 

    robot.respond /cover (.*) with (.*) from (.*) to (.*)/i, (msg) ->
        tzone = adhoc.getTimezone(msg)
    
    robot.respond /cancel cover (.*) with (.*) from (.*) to (.*)/i, (msg) ->
        tzone = adhoc.getTimezone(msg)

    robot.respond /set adhoc debug(?: level)?(?: to)? (.*)/i, (msg) ->
        adhoc.setDebug msg.match[1]
        msg.reply "adhoc debug now set to #{util.inspect adhoc.debug}"

    robot.respond /set adhoc chat debug(?: to)? (true|false|on|off)/i, (msg) ->
        adhoc.setChatDebug msg.match[1].toLowerCase() in ['true','on']
        msg.reply "adhoc chat debug now set to #{if adhoc.chatdebug then "on" else "off"}"

    robot.respond /time(?: in)*\s*(.*)/i, (msg) ->
        if msg.match[1]
            adhoc.listTimezones msg, msg.match[1], (err, zone) ->
                adhoc.debugMsg msg, util.inspect zone, 0
                msg.reply((new time.Date()).setTimezone(zone))
        else
            zone = adhoc.getTimezone(msg)
            msg.reply((new time.Date()).setTimezone(zone))

