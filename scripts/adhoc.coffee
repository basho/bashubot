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
# rolemanager.coffee
# escalation.coffee
#
#configuration
#  ADHOC_DEBUG
#  ADHOC_SECRET
#  ADHOC_URL
#  ADHOC_DOCID
#  ADHOC_SHEET
#
#commands:
# hubot get adhoc schedule - retrieve and display on call schedule modifications
# hubot show current adhoc schedule - show currently active schedule modifications
# hubot set my timezone to <timezone> - specify timezone to use when interacting with adhoc schedules
# hubot list timezones like <prefix> - list all timezones available for use with adhoc schedules that start with <prefix>
# hubot cover <name> (on-call|rolename) with <name> from <datetime> to <datetime> - create an adhoc schedule modification
# hubot cover (on-call|rolename):<name> with <name> from <datetime> to <datetime> - create an adhoc schedule modification
# hubot time - display current time in your selected timezone (adhoc schedule module)
# hubot time in <zone> - display current time in timezone
#

cron = require 'cron'
crypto = require 'crypto'
time = require 'time'
_ = require 'underscore'
util = require 'util'
api = require '../customlib/redirector.coffee'

class Adhoc 
    debug: process.env.ADHOC_DEBUG || 0
    cdebug: false
    docid: process.env.ADHOC_DOCID
    sheetname: process.env.ADHOC_SHEET
    waiting: true
    logger:
        info: () ->
                 return

    intValue: (value) ->    
        if value == true
            1
        else if typeof value is 'number'
            value
        else if typeof value is 'string'
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
        @cdebug = @intValue(value)

    debugMsg: (msg, text, level=7) ->
        return unless @debug
        if @debug >= level
            logmsg = "ADHOC DEBUG: #{text}"
            msg.send logmsg if @cdebug and msg? and msg.send?
            @logger.info logmsg if @debug > 0

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

    allToLower: (arr) ->
        _.map arr, (s) -> 
            if typeof s is 'string'
                s.toLowerCase()
            else
                s

    ## if the format of the spreadsheet in Google Docs should ever change
    ## this function will need to be changed to match
    formatScheduleLine: (msg, fields, heads, zone='UTC') ->
        entry = _.object @allToLower(heads), fields
        if entry.from and entry.to
            entry.from = @epoch2DateTime Date.parse(entry.from), zone 
            entry.to = @epoch2DateTime Date.parse(entry.to), zone
            _.map entry,(v,k) -> v
        else
            false


    formatResponse: (msg,txt,data) =>
        @debugMsg msg, "formatResponse msg, #{txt}, #{util.inspect data}", 2
        timezone = @getTimezone msg
        if "count" of data
          lines = []
          size = []
          datarow = []
          size = for head in data.colheads
            datarow.push "#{head}"
            "#{head}".length
          lines.push datarow
          for rawrow in data.items
            @debugMsg msg, util.inspect(data), 3
            if row = @formatScheduleLine msg, rawrow, data.colheads, timezone
                datarow = []
                i = 0
                for r in row
                  size[i] ||= 0
                  if "#{r}".length > size[i]
                    size[i] = "#{r}".length
                  datarow.push "#{r}"
                  i += 1
                lines.push datarow
          response = "/code #{txt}\n"
          for l in lines
            sizedrow = []
            i = 0
            for f in l
              if f.length < size[i]
                f = "#{f}#{Array(size[i] - f.length + 1).join String.fromCharCode 160}"
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
        api.do_request request, (err, res, body) =>
          @debugMsg msg, "Response: #{err}\n#{util.inspect res}\n#{body}", 3
          if res.statusCode == 200
            reqfun(msg, JSON.parse(body)) if reqfun
          else
            msg.reply "Error #{res.statusCode}\n#{body}"
   
    getCurrent: (msg, callback) ->
        now = (new Date).toISOString()
        @postReq msg,
            action: "Filter"
            # 4294967295000 is (2^32-1) * 1000,  an epic epoch date far into the future
            filters: [{col:'From', rangefrom:(new Date(0)).toISOString(), rangeto:now },
                   {col:'To', rangefrom:now, rangeto:(new Date(4294967295000)).toISOString()}],
            callback

    showCurrent: (msg) ->
        @getCurrent msg, 
            (msg, data) => @formatResponse msg, "Currently active adhoc entries", data

    getSince: (msg, stamp, callback) =>
        @getStartedSince msg, stamp, (startData) =>
            @getEndedSince msg, stamp, (stopData) =>
                allitems = _.union startData.items, stopData.items
                callback 
                    colheads: stopData.colheads,
                    count: allitems.length,
                    items: allitems

    getStartedSince: (msg, stamp, callback) ->
        now = Date.parse(new Date)
        @postReq msg,
            action: 'Filter'
            filters: [{col:'From', rangefrom:stamp, rangeto:now}],
            callback

    getEndedSince: (msg, stamp, callback) ->
        now = Date.parse(new Date)
        @postReq msg,
            action: 'Filter'
            filters: [{col:'To', rangefrom:stamp, rangeto:now}],
            callback

    getByRow: (msg, fromrow, torow, callback) ->
        torow = fromrow if not torow or torow is ""
        @postReq msg, 
          action: "Filter"
          filters: [{fromrow:fromrow, torow:torow}], 
          callback
    
    showByRow: (msg, fromrow, torow) ->
        @getByRow msg, fromrow, torow, (msg, data) =>
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
          filters: [filter], (msg, data) =>
            @formatResponse msg, textMsg, data
    
    getByPrefix: (msg, column, value) ->
        @postReq msg, 
          action: "Filter"
          filters: [{col:column ,prefix:value}], (msg, data) =>
            @formatResponse msg, "Search for #{column} starting with #{value}", data
    
    getByContains: (msg, column, value) ->
        @postReq msg, 
          action: "Filter"
          filters: [{col:column, contains:value}], (msg, data) =>
            @formatResponse msg, "Search for #{column} containing #{value}", data
    
    appendRow: (msg, csvdata) ->
        @postReq msg, 
          action: "Append"
          rows: [ @trimSplit(csvdata) ],
          (msg, data) =>
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
        zone_regex = zone.replace /[ ]/, '[ \/_]'
        verify = (err,zones) =>
          if err is null
            realZone = []
            for z in zones
                realZone.push(z) if z.toLowerCase().match(zone_regex)
            msg.reply "No timezone found matching #{zone}" if realZone.length is 0
            if realZone.length > 1
                if realZone.length > 100 and msg.envelope.room
                    msg.reply "#{realZone.length} timezones match #{zone}"
                else 
                    msg.reply "Multiple timezones found matching #{zone}:#{util.inspect realZone}" if realZone.length > 1
            if realZone.length is 1
                if callback
                    callback msg, realZone[0], @ 
                else
                    msg.reply realZone[0]
          else
            msg.send "Error getting list of time zones: #{err}"
        time.listTimezones verify 
   
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
        @debugMsg null, "date2epoch #{str}, #{zone}", 2
        dt = null
        return str if typeof str is not 'string'
        dt = Date.parse(new Date) if /now|today/i.test str
        dt = (new time.Date()).setTimezone(zone).getTime() + 86400000 if /tomorrow/i.test str
        dt = dt ? Date.parse(new time.Date(str,zone))
        if isNaN dt
            dt = parseInt(str)
        return dt
        
    epoch2ISO: (epoch, zone='UTC') ->
        i = epoch
        if typeof i is 'string'
          i = parseInt(epoch)
        d = new time.Date(i,zone) if typeof i is 'number'
        "#{d.getFullYear()}-#{"0#{d.getMonth()+1}".slice -2}-#{"0#{d.getDate()}".slice -2}T#{d.toTimeString().replace(/\ .+/,'')} #{d.getTimezoneAbbr()}" if d
    
    epoch2Date: (epoch, zone) ->
        @epoch2ISO(epoch,zone).replace(/T.+/, '')
    
    epoch2DateTime: (epoch, zone) ->
        @epoch2ISO(epoch, zone).replace(/T/, ' ')

    getSchedule: (msg) ->
        @showByRow(msg, 'TOP', 'BOTTOM')

    newEntry: (msg, role, remove, replacement, dtfrom, dtto) =>
        @debugMsg msg, "newEntry msg, #{role}, #{remove}, #{replacement}, #{dtfrom}, #{dtto}", 1
        zone = @getTimezone msg
        now = Date.parse((new time.Date()).setTimezone(zone))
        from = @date2epoch dtfrom, zone
        fromstr = @epoch2DateTime(from, 'UTC').replace /.UTC/, ''
        to = @date2epoch dtto, zone
        tostr = @epoch2DateTime(to, 'UTC').replace /.UTC/, ''
        remove_name =  msg.robot.roleManager.fudgeNames msg, remove, "on_call_name", "_fail_"
        replace_name =  msg.robot.roleManager.fudgeNames msg, replacement, "on_call_name", "_fail_"
        role = '' if role.match /^on.*call$/i

        valid = true
        response = "Failed to add schedule modification"
        if remove_name.length isnt 1 or remove_name[0] is "_fail_"
            response = "#{response}\n#{if remove_name.length < 2 then "No" else "multiple"} matches found for '#{remove}'"
            valid = false
        if replace_name.length isnt 1 or replace_name[0] is "_fail_"
            response = "#{response}\n#{if remove_name.length < 2 then "No" else "multiple"} matches found for '#{replacement}'"
            valid = false
        if from >= to
            response = "#{response}\n'To' datetime must occur after 'From' datetime"
            valid = false
        if from < now
            response = "#{response}\n'From' datetime cannot be retroactive"
            valid = false
        if to < now
            response = "#{response}\n'To' datetime must be in the future"
            valid = false
        if not (role is '' or msg.robot.roleManager.isRole role)
            response = "#{response}\nUnknown role '#{role}'"
            valid=false

        if valid
            req = 
                action: "Append"
                rows: [  
                    From: fromstr,
                    To: tostr,
                    Role: role,
                    Remove: remove_name[0],
                    Add: replace_name[0]
                    ],
            @postReq msg, req, (msg, data) =>
                    @formatResponse msg, "Added schedule modification:", data
        else
            msg.reply response

      applyOne: (msg, entry) ->
          now = Date.parse(new Date)
          if entry.to? and entry.from? and entry.to isnt '' and entry.from isnt ''
              from = @date2epoch entry.from
              to = @date2epoch entry.to
              action = "fail"
              action = "start" if to < now
              action = "stop" if from < now
              if action isnt "fail"
                  if entry.role? and msg.roleManager.isRole(entry.role)
                      msg.robot.roleManager.action msg, (if action is "start" then 'set' else 'unset'), entry.role, entry.add
                      msg.robot.roleManager.action msg, (if action is "start" then 'unset' else 'set'), entry.role, entry.remove
                  else
                      msg.robot.onCall.add msg, if action is "start" then entry.add else entry.remove
                      msg.robot.onCall.remove msg, if action is "start" then entry.remove else entry.add
              else
                  msg.send "Skipping future schedule entry: #{util.inspect entry}"
          else
              msg.send "Skipping invalid schedule entry: #{util.inspect entry}"

      reapplyCurrent: (msg, now) =>
          @getCurrent msg, @applyList
              
      applySinceLast: (msg) =>
        now = Date.parse(new Date)
        lastrun = msg.robot.brain.get("adhoc_lastrun") || 0
        msg.robot.brain.set("adhoc_lastrun",now)
        @getSince msg, lastrun, @applyList
        msg.robot.brain.set("adhoc_lastrun", now)

      applyList: (msg, data) =>
            if data.count? and data.count > 0
                for fields in data.items
                    try
                        entry = _.object @allToLower(data.colheads), fields
                        @applyOne msg, entry
                    catch error
                        msg.send "Adhoc error: #{util.inspect error}"

adhoc = new Adhoc

module.exports = (robot) ->
   adhoc.logger = robot.logger
   robot.adhoc = adhoc
   cron
   robot.respond /adhoc inspect (.*)/, (msg) ->
       eval "obj=#{msg.match[1]}"
       msg.reply "#{util.inspect obj}"

    robot.respond /(?:get|show) adhoc(?: schedule)*/i, (msg) ->
        adhoc.getSchedule msg

    robot.respond /(?:get|show) current adhoc(?: schedule)*/i, (msg) ->
        adhoc.showCurrent msg

    robot.respond /set my timezone (?:to)*\s*([^ ]*)/i, (msg) ->
        adhoc.setTimezone msg, msg.match[1]

    robot.respond /list timezones$/i, (msg) ->
        if msg.envelope.room
            msg.reply "Please repeat request in a private chat room"
        else
            adhoc.listTimezones msg, '' 

    robot.respond /list timezones(?: like)* (.*)/, (msg) ->
        adhoc.listTimezones msg, msg.match[1]

    robot.respond /cover (.*) (on-?call|[^ ]*) with (.*) from (.*) to (.*)/i, (msg) ->
        adhoc.newEntry msg, msg.match[2], msg.match[1], msg.match[3], msg.match[4], msg.match[5]
 
    robot.respond /cover (on[- ]*call|[^:]*):(.*) with (.*) from (.*) to (.*)/i, (msg) ->
        adhoc.newEntry msg, msg.match[1], msg.match[2], msg.match[3], msg.match[4], msg.match[5]
    
    robot.respond /cancel cover (.*) with (.*) from (.*) to (.*)/i, (msg) ->
        adhoc.removeEntry msg, msg.match[1], msg.match[2], msg.match[3], msg.match[4]

    robot.respond /set adhoc debug(?: level)?(?: to)? (.*)/i, (msg) ->
        adhoc.setDebug msg.match[1]
        msg.reply "adhoc debug now set to #{util.inspect adhoc.debug}"

    robot.respond /set adhoc chat debug(?: to)? (true|false|on|off)/i, (msg) ->
        enable = msg.match[1].toLowerCase() in ['true','on']
        adhoc.setChatDebug enable
        msg.reply "adhoc chat debug now set to #{if adhoc.cdebug then "on" else "off"}"

    robot.respond /time(?: in)* (.*)/i, (msg) ->
        if msg.match[1]
            adhoc.listTimezones msg, msg.match[1], (err, zone) ->
                adhoc.debugMsg msg, util.inspect zone, 0
                msg.reply((new time.Date()).setTimezone(zone))
        else
            zone = adhoc.getTimezone(msg)
            msg.reply((new time.Date()).setTimezone(zone))

