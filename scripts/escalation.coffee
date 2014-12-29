# Description:
#   Manage the on-call list and automate on-call schedule
#
# Dependencies:
#   cron
#   util
#   underscore
#   scoped-http-client
#   rolemanager.coffee
#
# Configuration:
#   ESCALATION_URL
#   ESCALATION_USER
#   ESCALATION_PASSWORD
#   ESCALATION_CRONSCHEDULE
#   ESCALATION_NOTIFICATIONROOM
#   ESCALATION_CREATESCHEDROLE
#
# Commands:
#  hubot add <name>[ ,<name>...] to the <name> on-call schedule for|from <mm/dd/yyyy>[ through|thru|to|until <mm/dd/yyyy>] - add people to a schedule
#  hubot set the <name> on-call schedule for <mm/dd/yyyy> to <name>[,<name>...] - Create a schedule entry for date containing only the listed names
#  hubot unschedule <name>[, <name>...] from <name> on-call for|from <mm/dd/yyyy>[ through|thru|to|until <mm/dd/yyyy>] - remove people from a schedule
#  hubot apply the <name> on-call schedule - [re]update the current on-call list with the schedule for today
#  hubot clear the <name> on-call schedule [for|from <mm/dd/yyyy>[ through|thru|to|until <mm/dd/yyyy>]] - remove the schedule entries for dates
#  hubot display|show|export the [name] on-call schdeule [for|from <mm/dd/yyyy>[ through|thru|to|until <mm/dd/yyyy>]] - list the on-call schedule in a csv text blob
#  hubot display|show|export the current|next|today's|tomorrow's [name] on-call schedule - list a single on-call schedule
#  hubot audit the <name> on-call schedule [for|from <mm/dd/yyyy>[ through|thru|to|until <mm/dd/yyyy>]] - show audit entries for schedules in the date range
#  hubot load <name> on-call schedule\n<CSV data> - bulk set schedules from CSV of the form <mm/dd/yyyy>,<name>[,<name>]\n - Note: does not remove any intermediate entries
#  hubot check|fix|repair the [name] on-call schedule index
#  hubot who is on-call - list who is currently on-call
#  hubot show me on-call - list who is currently on-call
#  hubot page <name>[, <name>...] message <text> - trigger alert to specified peope/named roles
#  hubot put <name>[ ,<name>...] on-call - add people to the current on-call list
#  hubot remove <name>[ ,<name>...] from on-call - remove people from the current on-call list
#  hubot reset on-call - remove all names from the current on-call list, then apply the current schedule
#  hubot set on-call name for <fuzzy user> to <name> - set the case-sensitive name the on-call server uses for this Hipchat user
#  hubot update the <name> on-call schedule from google docs [uri <uri> docid <docid> sheet <name> range <A1-style range>]
#  hubot create new [ad-hoc] on-call schedule named <name>
#  hubot list on-call schedules [details] - show names of know schedules
#  hubot delete [the] <naem> on-call schedule - purge and remove named schedule
#  hubot cron update( [the] <name> on-call schedule from google  [docs] <Sec> <Min> <Hr> <Day> <Mon> <DoW> (see https://github.com/ncb000gt/node-cron#cron-ranges)
#  hubot set cron apply for <name> on-call schedule to <Sec> <Min> <Hr> <Day> <Mon> <DoW>
#  hubot  set cron update for <name> on-call schedule to <Sec> <Min> <Hr> <Day> <Mon> <DoW>
#
# Author:
#   Those fine folks at Basho Technologies
#

util = require 'util'
cronJob = require('cron').CronJob
HttpClient = require 'scoped-http-client'
_ = require 'underscore'
api = require '../customlib/redirector.coffee'
crypto = require 'crypto'


onCall =
  testing: process.env.TESTING || false
  #placeholder - roles are defined below to permit circular references
  roles: {} 
  url: process.env.ESCALATION_URL
  user: process.env.ESCALATION_USER
  password: process.env.ESCALATION_PASSWORD
  queue: []
  lastqueuerun: 0

  silentMsg: (msg) ->
    silence = () -> 
      return
    m = 
     robot: msg.robot
     reply: silence
     send:  silence
     user: msg.user
     envelope: msg.envelope
    m

  showRole: (msg,role) ->
    old = @getRole msg, role
    if old? and old.length > 0
      @.get msg, (names) ->
        current = _.intersection old,names
        bad = _.difference old,names
        response="#{role} role is occupied by #{current.join ', '}"
        if bad.length > 0
          response="#{response}\n#{bad.join ', '} listed as #{role}, but not on call"
        msg.send response
    else
       msg.send "Role #{role} is unoccupied"

  addToRole: (msg, role, n) ->
    @modifyRole(msg, role, n, _.union, onCall.add)

  removeFromRole: (msg, role, n) ->
    @modifyRole(msg, role, n, _.difference, onCall.remove)

  modifyRole: (msg, role, n, op, action) ->
    if n not instanceof Array
      n = n.trim().split(',')
    names = msg.robot.roleManager.fudgeNames msg,n,"on_call_name"
    old = @getRole msg, role
    current = op old, names
    action? msg, names 
    msg.robot.brain.set "role-#{role.toUpperCase()}", current
    @showRole msg, role

  getRole: (msg, role) ->
      msg.robot.brain.get "role-#{role.toUpperCase()}" ? []

  httpclient: (res) ->
    req_headers = {
      'Authorization': 'Basic ' + new Buffer("#{@user}:#{@password}").toString('base64'),
      'Accept' : 'application/json',
      'Content-Type' : 'application/json'
    }
    HttpClient.create(@url, headers: req_headers).path(res ? "/zdsms/rest/on-call/current")

  list: (msg) ->
    @get msg, (names) -> 
      msg.send "Here's who's on-call: #{names.join(', ')}"

  get: (msg, callback) ->
    onCall.queue.push {'msg':msg,'args':callback,'action':(msg,callback) -> onCall.do_get(msg, callback)}
    onCall.queue_run()

  do_get: (msg, callback) ->
    http = @httpclient()
    http.get() (err, res, body) ->
      if err
        msg.reply "Sorry, I couldn't get the on-call list: #{util.inspect(err)}"
      else
        # JSON will be returned in this form ["Name One","Name Two"]
        names = JSON.parse(body.trim())
        callback(names)
      onCall.queue_run(true)

  showQueue: (msg) ->
    msg.reply util.inspect onCall.queue

  queue_run: (nowait) ->
    now = (new Date).getTime()
    if onCall.queuetimer
        clearTimeout(onCall.queuetimer)
        onCall.queuetimer = null
    if onCall.queue.length > 0
      if (now > (onCall.lastqueuerun + 10000)) or nowait
        Obj = onCall.queue.shift()
        Obj.action?(Obj.msg,Obj.args)
      @queuetimer = setTimeout(onCall.queue_run, 10000)
    @lastqueuerun = now

  add: (msg,people) ->
    onCall.queue.push {'msg':msg,'args':people,'action':(msg,people) -> onCall.do_add(msg,people)}
    onCall.queue_run()

  do_add: (msg, people) ->
    http = @httpclient()
    names = msg.robot.roleManager.fudgeNames(msg, people, "on_call_name")
    if @testing
      msg.send "If I were allowed, I would add #{names.join(", ")} to the on-call list"
      setTimeout(
        () -> 
          onCall.queue_run(true)
        ,500)
    else
      # JSON message like this {"add":["Name One","Name Two"]}
      req =
        add: names
      http.put(JSON.stringify(req)) (err, res, body) ->
        if err
          msg.reply "Error adding #{util.inspect names} #{err}"
        else
          # NB: must re-fetch to get current list
          http.get msg, (newlist) =>
            added = _.intersection names, newlist
            failed = _.difference names, newlist
            msg.send "Added #{added.join(", ")} to on-call" if added.length > 0
            msg.send "Failed to add #{failed.join(", ")} to on-call" if failed.length > 0
        onCall.queue_run(true)

  remove: (msg, people) ->
    onCall.queue.push {'msg':msg,'args':people,'action':(msg,people) -> onCall.do_remove(msg,people)}
    onCall.queue_run()

  do_remove: (msg, people) ->
    http = @httpclient()
    names = msg.robot.roleManager.fudgeNames msg, people, "on_call_name"
    if @testing
      msg.send "If I were allowed, I would remove #{names.join(", ")} from the on-call list"
      setTimeout(
        () -> 
          onCall.queue_run(true)
        ,500)
    else
      # JSON message like this {"remove":["Name One","Name Two"]}
      req =
        remove: names
      http.put(JSON.stringify(req)) (err,res,body) ->
        if err
          msg.reply "Error removing #{names.join(", ")}: #{err}"
        else
          # NB: must re-fetch to get current list
          http.get msg, (newlist) =>
            removed = _.difference names, newlist
            failed = _.intersection names, newlist
            msg.send "Removed #{removed.join(", ")} from on-call" if removed.length > 0
            msg.send "Failed to remove #{failed.join(", ")} from on-call" if failed.length > 0
        onCall.queue_run(true)
  
  modify: (msg, people, op) ->
    http = @httpclient()
    http.get() (err, res, body) =>
      if err
        msg.reply "Sorry, I couldn't get the on-call list: #{util.inspect(err)}"
      else
        names = JSON.parse(body.trim())
        newOnCall = op(names, msg.robot.roleManager.fudgeNames msg, people, 'on_call_name')
        # don't actually set the on-call list while testing
        if @testing
          msg.reply "If I were allowed to set the on-call list, I would set it to: #{newOnCall.join ", "}"
        else
          # JSON message like this {"set":["Name One","Name Two"]}
          req =  
            set: newOnCall
          http.put(JSON.stringify(req)) (err, res, body) =>
            if err
              msg.send "Sorry, I couldn't set the new on-call list to #{newOnCall.join(', ')}: #{util.inspect(err)}"
            else
              msg.send "Ok, I updated the on-call list"
              http.get msg, (names) =>
                diffs = _.difference(newOnCall, names)
                if diffs.length > 0
                  msg.send "Failed to add: #{diffs.join ', '}"
                diffs = _.difference(names, newOnCall)
                if diffs.length > 0
                  msg.send "Failed to remove: #{diffs.join ', '}"
                msg.send "Here's who's on-call: #{names.join ', '}"

  page: (msg, people, text) ->
    message = "Page requested by #{msg.envelope.user.name}"
    message = " #{message} in room #{msg.envelope.room}" if msg.envelope.room?
    message = "#{message}: #{text}"
    http = @httpclient("/zdsms/alert")
    rolenames = msg.robot.roleManager.getNames(msg,people) # convert any roles to names
    ppl = msg.robot.roleManager.fudgeNames msg, rolenames, "on_call_name" # map to on_call_name if available
    req =  
      names: _.uniq(ppl, false)
      message: message
    # JSON: {"names":["Name One","Name Two"],"message":"ALERT MESSAGE"}
    http.post(JSON.stringify(req)) (err, res, body) ->
      if err
        msg.reply "Sorry, I couldn't alert #{req.names.join(", ")}\n#{util.inspect(err)}"
      else
        if res.statusCode is 200 or res.statusCode is 204
          msg.reply "Alert sent to #{req.names.join(", ")}"
        else
          msg.reply "HTTP response code #{res.statusCode} alerting #{req.names.join(", ")}\nerror: #{util.inspect err}\nbody: #{body}"


# All keys added to the hubot brain begin with 'ocs-'
# to allow for targeted removal if necessary
#
# structure of schedule data in robot.brain
# ocs-schedules : [{id:string,idx:integer,type:string}]
#  In these 3, # will be the index of the schedule name in ocs-schedules
# ocs-#-index : [onCasllScheduleIndexEntry]
# ocs-#-<epoch> : onCallScheduleEntry
# ocs-#-lastpurge : auditEntry
# ocs-lastpurge : auditEntry
# onCallScheduleIndexEntry :  {date: epoch,
#                              deleted: boolean,
#                              lastupdated: epoch,
#                              audit: [auditEntry]}
# auditEntry: {date: epoch,
#              user: hipchetUser,
#              action: string}
# onCallScheduleEntry : {date: string(mm/dd/yyyy),
#                        add: [string],
#                        remove: [string],
#                        people: [string]}
# hipchatUser : { id: string,
#                 name: string,
#                 room: string }

  schedule:

    #store cron details here instead of in the brain so they
    #get recreated on startup
    cronjob: []
    schedcron: []

    cronschedule: process.env.ESCALATION_CRONSCHEDULE ? "0 0 9 * * *" # 9am daily
    #cronschedule: "0 */5 * * * *" #every 5 minute


    fuzzyNameToIndex: (msg, name) ->
      schedules = msg.robot.brain.get('ocs-schedules') ? []
      sched = schedules.filter (S) -> S.id is name
      if sched.length is 1
        sched[0].idx
      else
        sched = schedules.filter (S) -> S.id.toLowerCase() is name.toLowerCase()
        if sched.length is 1
          sched[0].idx
        else if sched.length > 1
          msg.reply "Multiple schedules match '#{name}': #{sched.map((S) -> S.id).join ', '}"
          null
        else
          sched = schedules.filter (S) -> S.id.match(name,"i")
          if sched.length is 1
            sched[0].idx
          else if sched.length > 1
            msg.reply "Multiple schedules match '#{name}', #{sched.map((S) -> S.id).join ', '}"
            null
          else
            msg.reply "Schedule '#{name}' not found"
            null

    nameToIndex: (msg, name) ->
      name = name.trim?()
      schedules = msg.robot.brain.get('ocs-schedules') ? []
      sched = schedules.filter (S) -> S.id is name
      if sched.length > 0
        sched[0].idx
      else
        null
 
    updateSchedule: (msg, idxName, data) ->
      if parseInt idxName != idxName
        idx = @nameToIndex msg, idxName
      else
        idx = parseInt(idxName)
      schedules = msg.robot.brain.get('ocs-schedules') ? []
      scheds = schedules.filter (S) -> S.idx is idx
      if scheds.length > 1 
        msg.reply "Error found #{scheds.length} schedules with the same index"
        null
      else
        if data? and data.id? and data.idx? and data.type? and scheds[0].idx is data.idx
          if scheds[0] != data
            for k of scheds[0]
              delete scheds[0][k]
              msg.send "delete #{k}"
            msg.send util.inspect scheds[0]
            msg.send util.inspect data
            for k of data
              msg.send "#{k}"
              msg.send "#{scheds[0][k]}"
              msg.send "#{data[k]}"
              scheds[0][k] = data[k]
          msg.robot.brain.set 'ocs-schedules',schedules
        else
          msg.reply "Invalid schedule metadata for index #{idxName}: #{util.inspect data}"

    getSchedule: (msg, idxName) ->
      if parseInt idxName != idxName
        idx = @nameToIndex msg, idxName
      else
        idx = parseInt(idxName)
      schedules = msg.robot.brain.get('ocs-schedules') ? []
      scheds = schedules.filter (S) -> S.idx is idx
      if scheds.length > 1
        msg.reply "Error found #{sched.length} schedules with the same index"
        null
      else
        scheds[0]

    getScheduleType: (msg, idxName) ->
      if sched = @getSchedule(msg, idxName)
        sched.type
      else
        null

    indexToName: (msg, idx) ->
      if sched = @getSchedule msg, idx
        sched.id ? null
      else
        null

    createSchedule: (msg, type, name) ->
      if name is null or name is ""
        msg.reply "You didn't specify a name"
        return null
      type = type ? "normal"
      schedules = msg.robot.brain.get('ocs-schedules') ? []
      if @nameToIndex(msg, name)?
        msg.reply "Schedule '#{name}' already exists"
      else
        i = 0
        while @indexToName {robot:msg.robot,reply:(txt)->return}, i
            i = i + 1
        schedules.push({'id':name,'idx':i,'type':type})
        msg.robot.brain.set 'ocs-schedules',schedules
        msg.robot.brain.set "ocs-#{i}-index",[]
        msg.reply "#{type} schedule #{name}(#{i}) created"

    deleteSchedule: (msg, sched) ->
        if @purgeSchedule msg, sched
          regex = new RegExp "^ocs-#{sched}-"
          msg.robot.brain.remove k for k in Object.keys(msg.robot.brain.data._private).filter (key) -> key.match(regex)
          schedules = msg.robot.brain.get('ocs-schedules')
          filtered = schedules.filter (obj) -> obj.idx != sched
          if filtered.length + 1 is schedules.length
            msg.robot.brain.set('ocs-schedules',filtered)
            msg.reply "Schedule #{@indexToName msg,sched}(#{sched}) deleted."
          else
            msg.reply "I'm going hurl: \n Schedules: #{util.inspect schedules} \n Filtered: #{util.inspect filtered}"

    linkScheduleToGoogleDoc: (msg, sched, url, docid, sheetName, range) ->
      if sched? && url && docid && sheetName && range
        if entry = @getSchedule msg, sched
          entry.url = url
          entry.docid = docid
          entry.sheet = sheetName
          entry.range = range
          @updateSchedule msg, sched, entry
          msg.reply "Updated schedule #{entry.id} to use URL #{entry.url} Document ID #{entry.docid} '#{entry.sheet}'!#{entry.range}"
      else
        msg.reply "Must specify url, docid, sheetName, and range"

    newAuditEntry: (msg, action) ->
      dNow = new Date
      usr =
        name: msg.message.user["name"] ? "<name missing>"
        id: msg.message.user["jid"] ? "<id missing>"
        room: msg.message["room"] ? "<room missing>"
      audit =
        action: action
        date: dNow.getTime()
        user: usr
      return audit

    newIndexEntry: (msg, dt, deleted, action) ->
      dNow = new Date
      idx =
        date: @makeDate(dt)
        deleted: deleted ? false
        lastupdated: dNow.getTime()
        audit: [
          @newAuditEntry(msg, action ? "create")
          ]

    newScheduleEntry: (date, people) ->
      sched =
        date: @epoch2Date(@makeDate(date))
        people: if people then people else []
      return sched

    getIndex: (msg, deletedok, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to getIndex, aborting"; return null)
      i = msg.robot.brain.get "ocs-#{sched}-index"
      if i instanceof Array
        if deletedok
            return i
        else
            return i.filter (entry) -> not entry["deleted"]
      else
        return []

    getIndexRange: (msg, fromDate, toDate, deletedok, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to getIndexRange, aborting"; return null)
      idx = @getIndex(msg, deletedok, sched)
      if (fromDate or toDate)
        start = @makeDate(fromDate)
        stop = @makeDate(toDate)
        start = stop if not start? or isNaN start
        stop = start if not stop? or isNaN stop
        idx = idx.filter (entry) -> (entry["date"] >= start) and (entry["date"] <= stop)
      if fromDate? and idx? and (idx.length > 0) and (idx[0]['date'] != @makeDate(fromDate))
        i = @getIndexEntry msg, fromDate, false, sched
        idx.unshift i if i and i['date']
      return idx

    saveIndex: (msg, index, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to saveIndex, aborting"; return null)
      if sched != parseInt sched
        msg.reply "Invalid index #{util.inspect sched}"
        return null
      if index instanceof Array
        msg.robot.brain.set "ocs-#{sched}-index", index
      else 
        msg.robot.logger.info "Invalid index submitted: #{util.inspect index} for schedule #{@indexToName msg,sched}"

    insertIndex: (msg, idx, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to insertIndex, aborting"; return null)
      oIndex = @getIndex(msg, true, sched)
      if idx["date"]
        index = oIndex.filter (entry) -> entry['date'] != idx['date']
        index.push idx
        index.sort (a, b) ->
          return -1 if (a["date"] < b["date"])
          return 1 if (a["date"] > b["date"])
          return 0
        @saveIndex(msg, index, sched)

    checkIndex: (msg, schedules) ->
      schedules = schedules ? msg.robot.brain.get('ocs-schedules').map (s) -> s.idx
      if not schedules.length?
        schedules = [schedules]
      #fake message to identify the repair process as actor
      msg.robot.logger.info "Check/Repair index for schedule #{sched} #{util.inspect msg.message.user}"
      fakemsg =
        robot: msg.robot
        message:
          user:
            name: "Auto Repair Process"
            id: "0"
            room: "backroom"
      ocsKeys = Object.keys(msg.robot.brain.data._private)
      for sched in schedules
        index = @getIndex(msg, true, sched)
        response = ["Checking #{@indexToName(msg, sched)} index entries:"]
        for i in index
          if i
            if i['date']
              if not msg.robot.brain.get "ocs-#{sched}-#{i['date']}"
                i['deleted'] = true
                i['audit'].push @newAuditEntry(fakemsg, "delete")
                @insertIndex(msg, i, sched)
                response.push "Index for #{@epoch2Date(i['date'])} points to non-existent schedule entry, deleteing"
            else
              i['deleted'] = true
              i['audit'].push @newAuditEntry(fakemsg, "delete")
              @insertIndex(msg,i, sched)
              response.push "Index entry missing date, deleting:\n #{util.inspect i}"
          else
            response.push "Deleting invalid index entry #{util.inspect i}"
            @purgeIndex(msg, i, sched)
        response.push "Checking #{@indexToName(msg,sched)} schedule entries"
        #get a fresh index with the fixes so far applied
        index = @getIndex(msg, true, sched)
        for k in ocsKeys
          m = (new RegExp "^ocs-#{sched}-([0-9]*)$").exec k
          if m
            sched = msg.robot.brain.get k
            if sched and sched['date']
              sdt = @makeDate(sched['date'])
              kdt = @makeDate(m[1])
              if sdt != kdt
                response.push "Schedule entry date '#{sched['date']}' does not match key '#{k}', deleting"
                idx = @getIndexEntry msg, m[1], true, sched
                if idx?
                  @deleteEntryByIndex(msg, idx, sched)
                else
                  msg.robot.brain.remove k
              else
                idx = @getIndexEntry msg, m[1], true, sched
                if idx and idx['date'] is @makeDate(m[1])
                  if idx['deleted']
                      response.push "Index entry for schedule date '#{sched['date']}' marked deleted, undeleting"
                      idx['deleted'] = false
                      idx['audit'].push @newAuditEntry(fakemsg, 'undelete')
                      @insertIndex(msg, idx, sched)
                else
                  response.push "Index missing for schedule date '#{sched['date']}(#{@makeDate(sched['date'])}), creating"
                  @insertIndex msg, @newIndexEntry(fakemsg,sched['date']), sched
            else
              response.push "Deleting invalid schedule entry #{k}"
              msg.robot.brain.remove k
              idx = @getIndexEntry msg, m[1], false, sched
              if idx
                idx['deleted'] = true
                idx['audit'].push @newAuditEntry(fakemsg, 'delete')
                @insertIndex msg, idx, sched
      response.push "Check complete"
      msg.send response.join("\n")

    purgeIndex: (msg, idx, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to purgeIndex, aborting"; return null)
      index = @getIndex msg, true, sched
      if idx and idx["date"]
        msg.robot.brain.remove "ocs-#{sched}-#{idx['date']}"
      @saveIndex  msg, _.difference(index,[idx]), sched

    makeDate: (str) ->
      dt = null
      return str if typeof str is not 'string'
      dt = Date.parse((new Date).toDateString()) if /today/i.test str
      dt = (new Date).getTime() + 86400000 if /tomorrow/i.test str
      dt = (new Date).getTime() - 86400000 if /yesterday/i.test str
      dt = dt ? Date.parse(str)
      if isNaN dt
        dt = parseInt(str)
      return dt

    epoch2DateTime: (int) ->
      i = int
      if typeof i is 'string'
        i = parseInt(int)
      d = new Date(i)
      return "#{d.getMonth() + 1}/#{d.getDate()}/#{d.getFullYear()} #{d.getHours()}:#{if d.getMinutes() < 10 then '0' else ''}#{d.getMinutes()}"

    epoch2Date: (int) ->
      i = int
      if typeof i is 'string'
        i = parseInt(int)
      d = new Date(i)
      return "#{d.getMonth() + 1}/#{d.getDate()}/#{d.getFullYear()}"

    getIndexEntry: (msg, date, deletedok, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to getIndexEntry, aborting"; return null)
      index = @getIndex msg, false, sched
      d = @makeDate(date)
      if deletedok
        aIndex = index.filter (entry) -> entry["date"] <= d
      else
        aIndex = index.filter (entry) -> (entry["date"] <= d and not entry["deleted"])
      if aIndex.length > 0
        return aIndex[aIndex.length-1]
      else
        return null

    getNextIndexEntry: (msg, date, deletedok, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to getNextIndexEntry, aborting"; return null)
      index = @getIndex msg, false, sched
      d = @makeDate date
      if deletedok
        aIndex = index.filter (entry) -> entry["date"] > d
      else
        aIndex = index.filter (entry) -> (entry["date"] > d and not entry["deleted"])
      if aIndex.length > 0
        return aIndex[0]
      else
        return null

    getEntryByIndex: (msg, idx, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to getEntryByIndex, aborting"; return null)
      if idx and idx['date']
        msg.robot.brain.get "ocs-#{sched}-#{idx['date']}"

    getEntry: (msg, date, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to getEntry, aborting"; return null)
      idx = @getIndexEntry msg, date, false, sched
      @getEntryByIndex msg, idx, sched

    createEntry: (msg, date, ppl, overwrite, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to createEntry, aborting"; return null)
      dt = @makeDate date
      current = @getIndexEntry msg, dt, true, sched
      dNow = new Date
      epochnow = dNow.getTime()
      newSched = @newScheduleEntry dt, ppl
      if not current or (current is []) or (current['date'] != dt)
        idx = @newIndexEntry msg, dt, false, "create - #{ppl}"
        @saveEntry msg, idx, newSched, sched
      else
        if not current.deleted
            old = @getEntryByIndex msg, current, sched
            if old.people.length is ppl.length and _.difference(old.people,newSched.people).length is 0 and _.difference(newSched.people,old.people).length is 0
                return "Schedule for #{@epoch2Date dt} unchanged"
        if overwrite then @deleteEntryByIndex msg, current, sched
        if current['deleted']
            current['deleted'] = false
            current['audit'].push @newAuditEntry(msg, "create - #{ppl}")
            current['lastupdated'] = epochnow
            @saveEntry(msg, current, newSched, sched)
        else
          msg.reply "Schedule entry already exists for #{date}"

    saveEntry: (msg, idx, entry, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to saveEntry, aborting"; return null)
      iDate = @epoch2Date(@makeDate(idx["date"]))
      eDate = @epoch2Date(@makeDate(entry["date"]))
      if iDate != eDate
        return {"error":"index and entry don't match\nIndex: #{util.inspect idx}\nEntry: #{util.inspect entry}"}
      current = @getIndexEntry msg, idx["date"], true, sched
      if current and current['date'] and (current['date'] is idx['date'])
        idx["audit"] = _.union(current["audit"],idx["audit"])
      @insertIndex msg, idx, sched
      msg.robot.brain.set "ocs-#{sched}-#{idx['date']}", entry
      return {"success":"Saved schedule #{@indexToName msg,sched}(#{sched}) entry for #{entry['date']}"}

    deleteEntryByIndex: (msg, idx, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to deleteEntryByIndex, aborting"; return null)
      idx["deleted"] = true
      timenow = new Date
      idx["audit"].push @newAuditEntry(msg, "delete")
      idx["lastupdated"] = timenow.getTime()
      msg.robot.brain.remove "ocs-#{sched}-#{idx['date']}"
      @insertIndex msg, idx, sched

    prettyEntry: (sched) ->
      if sched["date"]
        return "#{sched['date']},#{sched['people'].join ', ' if sched['people'] instanceof Array}"

    cronRemoteSchedules: (msg) ->
      schedules = msg.robot.brain.get('ocs-schedules') ? []
      for s in schedules
        @cronRemoteSchedule msg, null, s.idx

    cronRemoteSchedule: (msg, newcron, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to cronRemoteSchedule, aborting"; return null)
      if schedEntry = @getSchedule msg, sched
        if @schedcron and @schedcron[sched]
          msg.send "cron already set for #{@indexToName msg,sched} schedule"
        schedule = newcron ? schedEntry.remoteCron ? process.env["ESCALATION_REMOTECRONSCHED_#{sched}"] ? "0 0 4 * * *" # 4am daily
        if typeof schedule is 'string' and schedule.match /^[^ ]* [^ ]* [^ ]* [^ ]* [^ ]* [^ ]*$/
          msg.send "Update #{@indexToName msg,sched}(#{sched}) on-call schedule using cron string '#{schedule}'"
          msg.robot.logger.info "Create cronjob '#{schedule} onCall.schedule.remoteSchedule(msg, #{sched})'"
          schedEntry.remoteCron = schedule
          @schedcron[sched].stop?() if @schedcron? and @schedcron[sched]?
          @schedcron[sched] = new cronJob(schedule, =>
            @remoteSchedule(msg, sched)
          )
          @schedcron[sched].start()
          @updateSchedule msg, sched, schedEntry
        else
            msg.send "invalid cron string '#{newcron}'"
            return null
      
    remoteSchedule: (msg, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to remoteSchedule, aborting"; return null)
      md5sum = crypto.createHash('md5')
      schedule = @getSchedule msg, sched
      dt = "#{new Date}"
      if not schedule.docid
        msg.reply "No Document ID for #{@indexToName msg,sched}(#{sched})"
        return null
      if not schedule.url
        msg.reply "No Document URL for #{@indexToName msg,sched}(#{sched})"
        return null
      if not schedule.sheet
        msg.reply "No Document Sheet for #{@indexToName msg,sched}(#{sched})"
        return null
      if not schedule.range
        msg.reply "No Document Range for #{@indexToName msg,sched}(#{sched})"
        return null
      md5sum.update("BashoBot#{dt}#{schedule.docid}")
      data = md5sum.digest('base64')
      request= {
        url: schedule.url
        headers:  { "Content-Type":"application/x-www-form-urlencoded", "Accept":"*/*" }
        method: "post"
        data: {date: "#{dt}", data: "#{data}", id: "#{schedule.docid}", range: "#{schedule.range}", sheet: "#{schedule.sheet}"}
      }
      msg.send "Requesting #{@indexToName msg,sched}(#{sched}) schedule"
      api.do_request request, (err, res, body) =>
        if err
          msg.reply "Error retrieving #{@indexToName msg,sched}(#{sched}) schedule: #{err}"
        else if res.statusCode is 200
          msg.send "#{@indexToName msg,sched}(#{sched}) Schedule retrieved"
          msg.message ||= []
          msg.message.text = body
          @fromCSV(msg, sched)
          @pruneSchedule(msg, sched)
        else
          msg.reply "HTTP status #{res.statusCode} while retrieving #{@indexToName msg,sched}(#{sched}) schedule"
  
    fromCSV: (msg, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to fromCSV, aborting"; return null)
      msg.robot.logger.info "Upload #{@indexToName msg,sched}(#{sched}) schedule from CSV"
      response = []
      if schedule = @getSchedule msg, sched
        if not schedule.type.match /^ad-hoc$|^normal$/
          response.push "Skipping #{schedule.id}(#{schedule.idx}): unknown type #{schedule.type}"
          return null
        lines = "#{msg.message.text}".split("\n")
        for line in lines[1..]
          fields = line.split(",")
          if line != ""
            dt = @makeDate(fields[0])
            if not isNaN dt
              #response.push line
              switch schedule.type
                when 'ad-hoc'
                  for op in fields[1..]
                    action = op.split(':')
                    index = @getIndexRange(msg, dt, dt, true, sched) 
                    entry = @getEntry(msg, dt, sched) ? @newScheduleEntry dt
                    entry = @newScheduleEntry dt unless @makeDate(entry.date) is dt
                    switch action[0]
                      when 'Delete'
                        entry.people = _.difference entry.people, action[1..].join ":"
                      when 'Add','Remove'
                        if (action[1] is "All") or (action[1] is "UTC") or (@nameToIndex onCall.silentMsg(msg), action[1])
                          entry.people = _.union entry.people, op
                        else 
                          response.push "Unknown schedule '#{action[1]}' #{op}"
                      else
                        response.push "Skipping #{op}: unknown action #{action[0]}"
                    if entry.people.length is 0
                      if index.length > 0
                        @deleteEntryByIndex msg, index[0], sched 
                        response.push "delete entry for #{@epoch2Date dt}"
                    else 
                      response.push util.inspect @saveEntry msg, index[0] ? @newIndexEntry(msg, dt),  entry, sched
                when 'normal'
                  response.push util.inspect @createEntry msg, dt, fields[1..], true, sched
            else
              response.push "Invalid data (dt:#{dt}) '#{line}'"
      else
        response.push "Unable to find '#{sched}' schedule."
      msg.send response.join("\n")

    # return the audit history entries for the requestd range
    audit: (msg, fromDate, toDate, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to audit, using #{@issndexToName(0)}"; sched = 0)
      sched ? (msg.reply "Warning, schedule not specified in call to remoteSchedule, aborting"; return null)
      idx = @getIndexRange msg, fromDate, toDate, true, sched
      response = ["Audit entries:"]
      lastPurge = msg.robot.brain.get 'ocs-#{sched}-lastpurge'
      if lastPurge and lastPurge["date"]
        response.push "Schedule last purged #{@epoch2DateTime(lastPurge['date'])} by #{util.inspect lastPurge['user']}"
      else 
        lastFullPurge = msg.robot.brain.get 'ocs-lastpurge'
        if lastFullPurge and lastFullPurge["date"]
          response.push "Schedule last purged #{@epoch2DateTime(lastFullPurge['date'])} by #{util.inspect lastFullPurge['user']}"
      for i in idx
        try
          if i["deleted"]
            item = ["Deleted Entry for #{@epoch2Date(i['date'])}"]
          else
            item = [@prettyEntry @getEntryByIndex(msg, i, sched)]
          for a in i["audit"]
            u = a['user']
            item.push "\t#{@epoch2DateTime(a['date'])}: #{a['action']} by #{u['name'] ? 'name missing'}(#{u['id'] ? '<id missing>'}) #{if u['room'] then 'in ' + u['room'] else ''}"
          response.push item.join("\n")
        catch error
          response.push "Error #{util.inspect error} with index #{util.inspect idx} for schedule #{@indexToName msg,sched}"
      msg.send response.join("\n")

    listSchedules: (msg, detail) ->
      schedules = msg.robot.brain.get('ocs-schedules') ? []
      if schedules.length > 0
        msg.reply "On call schedules: #{schedules.map((O) -> "#{O.id}(#{O.type})").join(", ")}" if not detail
        if detail
          response = schedules.map (O) -> util.inspect O
          response.unshift("On call schedules:")
          msg.reply response.join("\n")
      else
        msg.reply "No schedules configured"

    # return the requested block of entries in CSV format
    toCSV: (msg, fromDate, toDate, indexes) ->
      response = []
      indexes = indexes ? msg.robot.brain.get('ocs-schedules').map (S) -> S.idx
      if not indexes.length?
        indexes = [indexes]
      for sched in indexes
        idx = @getIndexRange msg, fromDate, toDate, false, sched
        response.push "Here is the #{@indexToName msg,sched}(#{sched}) schedule"
        if idx.length < 1
          i = @getIndexEntry msg, fromDate, false, sched
          if i and i['date'] and entry=@getEntryByIndex(msg, i, sched)
            response.push "#{@prettyEntry(entry)}"
          else
            response.push "Schedule empty"
        for a in idx
          if a? and a['date']  
            response.push @prettyEntry(@getEntryByIndex(msg, a, sched))
      msg.send response.join("\n")

    purgeSchedule: (msg, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to purgeSchedule, aborting"; return null)
      if @confirm(msg, "Please repeat command to confirm you want to purge the #{@indexToName msg,sched}(#{sched}) schedule",true)
        @doPurgeSchedule msg, sched
      else
        null

    doPurgeSchedule: (msg, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to purgeSchedule, aborting"; return null)
      msg.send "Purging schedule #{@indexToName msg,sched}(#{sched})"
      @purgeIndex msg, i, sched for i in @getIndex msg, true, sched
      if @getIndex(msg,true,sched).length is 0
        msg.send "Purge successful"
        true
      else
        msg.send "Purge Failed: Remaining index: #{util.inspect @getIndex(msg,true)}"
        false

     #failsafe to remove all traces of on-call schedule from robot.brain in the event of horrific failure
    purge: (msg) ->
      if @confirm(msg, "Please repeat command to confirm you want to purge everything related to on-call schedule",true)
        schedules = msg.robot.brain.get('ocs-schedules') ? []
        for s in schedules
          @doPurgeSchedule(msg, s.idx)
        (msg.robot.brain.remove k for k in Object.keys(msg.robot.brain.data._private).filter (key) -> key.match(/^ocs-/))
        purgeAudit =
          date: (new Date).getTime()
          user: msg.message.user
          action: "Purge"
        msg.robot.brain.set 'ocs-lastpurge', purgeAudit

    # delete schedule entries, but keep the audit history
    clear: (msg, fromDate, toDate, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to clear, aborting"; return null)
      start = @makeDate(fromDate)
      end = @makeDate(toDate)
      if (not (start or end)) and (not @confirm(msg,"Please repeat command to confirm you want to delete the entire #{@indexToName msg,sched}(#{sched}) schedule"))
          return
      idx = @getIndexRange(msg,fromDate,toDate,false, sched)
      response = []
      if idx.length > 0
        response.push "Deleted the following #{@indexToName msg,sched}(#{sched}) schedule entries:"
        for a in idx
          response.push @prettyEntry(@getEntryByIndex(msg,a,sched))
          @deleteEntryByIndex(msg,a,sched)
        msg.send response.join("\n")
      else
        msg.reply "I couldn't find any #{@indexToName msg,sched}(#{sched}) schedule entries between #{fromDate} and #{toDate}"

    cronApplySchedules: (msg) ->
      schedules = msg.robot.brain.get('ocs-schedules') ? []
      for s in schedules
        @cronApplySchedule msg, null, s.idx

    cronApplySchedule: (msg, newcron, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to cronApplySchedule, aborting"; return null)
      if schedEntry = @getSchedule msg, sched
        if schedEntry.type is 'ad-hoc'
            msg.send 'Direct application of ad-hoc schedules not yet supported'
        else
          if @cronjob and @cronjob[sched]
            msg.send "cron already set for #{@indexToName msg,sched} schedule"
          that = this
          oldsched = schedEntry.applyCron
          schedule = newcron ? oldsched ? process.env["ESCALATION_CRONSCHEDULE_#{sched}"] ? "0 0 9 * * *"
          schedule ? (msg.reply "No cron defined for #{@indexToName msg,sched}(#{sched})"; return null)
          msg.robot.logger.info "Create cronjob '#{schedule} onCall.schedule.applySchedule(msg, #{sched})'"
          msg.send "set cron apply for #{@indexToName(msg, sched)} to #{schedule}"
          schedEntry.applyCron = schedule
          @cronjob[sched].stop?() if @cronjob? and @cronjob[sched]?
          @cronjob[sched] = new cronJob(schedule, ->
            that.applySchedule msg, sched
          )
          @updateSchedule msg, sched, schedEntry
          @cronjob[sched].start()

    getAdHocSchedules: (msg) ->
      schedules = msg.robot.brain.get('ocs-schedules') ? []
      schedules.filter (s) -> s.type is 'ad-hoc'

    adHocRemoveYesterday: (msg, sched) ->
      dt = @makeDate('yesterday')
      for adhoc in @getAdHocSchedules msg
        msg.send "Checking #{adhoc.id} schedule for #{@epoch2Date dt}"
        idx = @getIndexEntry msg, dt, false, adhoc.idx
        if idx?
          entry = @getEntryByIndex msg, idx, adhoc.idx
          for p in entry.people
            [action, applyWith, role, name] = p.split(":")
            if action is 'Add' and (applyWith is 'All' or @fuzzyNameToIndex(msg, applyWith) is sched)
                msg.send "Ah-Hoc expired remove #{name} from #{role}"
                msg.robot.roleManager.action msg, 'unset', role, name
        else
          msg.send "No #{adhoc.id} schedule entry found"

    adHocProcessToday: (msg, sched) ->
      dt = @makeDate('today')
      msg.send "Check Ad-Hoc for #{@epoch2Date(dt)}"
      for adhoc in @getAdHocSchedules msg
        if idx = @getIndexEntry msg, dt, false, adhoc.idx
          entry = @getEntryByIndex msg, idx, adhoc.idx
          if dt is @makeDate entry.date
            for p in entry.people
              [action, applyWith, role, name] = p.split(":")
              if applyWith is 'All' or @fuzzyNameToIndex(msg, applyWith) is sched
                msg.send "Ad-Hoc #{action} #{role}:#{name}"
                msg.robot.roleManager.action msg, (if action is 'Add' then 'set' else 'unset'), role, name 

    # locate the schedule entry for today and change who is on-call
    applySchedule: (realmsg, schedIdx) ->
      if @getScheduleType realmsg, schedIdx is 'ad-hoc'
        realmsg.send "Directly applying ad-hoc scheudles is not yet supported."
        return null
      realmsg.send "Applying #{@indexToName realmsg,schedIdx} on-call schedule"
      rmsg = 
        robot: realmsg.robot
        reply: realmsg.reply
        message: realmsg.message
        envelope: realmsg.envelope
        scheduler: true
        delayTimer: []
        response: []
      rmsg.msg = rmsg
      rmsg.send = (txt) ->
          rmsg.response.push txt
      epoch = (new Date).getTime()
      @adHocRemoveYesterday rmsg, schedIdx
      oldppl = []
      idx = @getIndexEntry rmsg, epoch, false, schedIdx
      if (not idx) or (idx is [])
        rmsg.reply "Error: Cannot locate an on-call schedule entry that covers #{@epoch2Date(epoch)}!"
        return
      sched = @getEntryByIndex(rmsg, idx, schedIdx)
      rmsg.send "Updating to the #{@indexToName rmsg,schedIdx} on-call schedule for #{@epoch2Date(epoch)}"
      lastapply = rmsg.robot.brain.get "ocs-#{schedIdx}-lastapplied"
      if not lastapply? or lastapply < idx["date"]
        # start looking for the previous schedule 1 second before the current one
        oldidx = @getIndexEntry rmsg, idx["date"] - 1000, false, schedIdx
        if oldidx
          osched = @getEntryByIndex(rmsg, oldidx, schedIdx)
          rmsg.send "Old schedule: #{@prettyEntry osched}"
          oldppl = _.difference(osched["people"],sched["people"])
      if lastapply? and lastapply is idx["date"]
        rmsg.send "Re-applying schedule #{sched['date']}"
      else
        rmsg.send "New schedule: #{@prettyEntry sched}"
      removenames = []
      removeroles = []
      addnames = []
      addroles = []
      for person in oldppl
            if m = person.match /^[ ]*([^: ]*)[ ]*:[ ]*(.*[^ ])[ ]*$/
                removeroles.push [m[1],m[2]]
            else
                removenames.push person
      for person in sched["people"]
            if m = person.match /^[ ]*([^: ]*)[ ]*:[ ]*(.*[^ ])[ ]*$/
                addroles.push [m[1],m[2]]
            else
                addnames.push person
      rmsg.robot.logger.info "Updating on-call Removing:[#{removeroles},#{removenames}] Adding:[#{addroles},#{addnames}]"
      rmsg.send "Removing roles: #{removeroles.join ","}" if removeroles.length > 0
      for role in removeroles
        #rmsg.send "Remove Role: #{role} - #{rmsg.robot.roleManager.isRole role[0]}"
        rmsg.robot.roleManager.action rmsg, 'unset', role[0], role[1]
      if removenames.length > 0
        rmsg.send "Remove #{removenames.join ', '} Adding #{addroles.join ', '} #{addnames.join ', '}"
        onCall.remove rmsg, removenames
        onCall.add rmsg, addnames
      else
        rmsg.send "Add #{addnames}"
        onCall.add rmsg, addnames
      rmsg.robot.brain.set "ocs-#{schedIdx}-lastapplied", idx["date"]
      autocreate = process.env.ESCALATION_CREATESCHEDROLE
      rmsg.send "Adding roles: #{addroles.join ","}" if addroles.length > 0
      for role in addroles
        #rmsg.send "Add Role: #{role} - #{rmsg.robot.roleManager.isRole role[0]}"
        rmsg.robot.roleManager.createRole rmsg, role[0] if autocreate and not rmsg.robot.roleManager.isRole role[0]
        if rmsg.robot.roleManager.isRole role[0]
          rmsg.robot.roleManager.action rmsg, 'set', role[0], role[1]
        else
          rmsg.send "Unable to set role '#{role[0]}'"
      @adHocProcessToday rmsg, schedIdx
      # allow rate-limited updates to apply before listing results
      delayResult = () =>
        if rmsg.delayTimer.length > 0
          setTimeout delayResult, 1000
        else 
          realmsg.send "on-call schedule application complete."
          realmsg.send rmsg.response.join "\n"
          onCall.list realmsg
          realmsg.robot.roleManager.showAllRoles realmsg
      setTimeout delayResult, 10000

    # modify a range of schedule entries
    # adds an entry at the beginning of the range if necessary
    modify: (msg, people, fromDate, toDate, op, sched) ->
      sched ? (msg.reply "Warning, schedule not specified in call to modify, aborting"; return null)
      dFrom = @makeDate(fromDate)
      dTo = @makeDate(toDate)
      if toDate
        if dFrom > dTo then return
      else
        dTo = dFrom
      dNow = new Date
      idx = @getIndexRange(msg, dFrom, dTo, false, sched)
      response = []
      fromIdx = idx.filter (entry) -> entry['date'] is dFrom
      if fromIdx.length is 0
        # there's no entry for the first date in the range
        # figure out if this change is different than the previous entry
        prev = @getIndexEntry msg, dFrom, false, sched
        prevppl = []
        if prev and prev['date']
            prevsched = @getEntryByIndex(msg, prev)
            if prevsched and prevsched['people'] then prevppl = prevsched['people']
        newppl = op(prevppl, people)
        newdiff = _.union(_.difference(newppl, prevppl), _.difference(prevppl, newppl))
        # only add a new entry if the list of names changes
        if newdiff.length != 0
          response.push @createEntry(msg, dFrom, newppl)
          response.push {"success":"Created new schedule entry for #{@epoch2Date(dFrom)}"}
      #update every pre-existing entry in the date range
      for i in idx
        sched = @getEntryByIndex(msg, i, sched)
        newlist = op(sched["people"], people)
        i["audit"].push @newAuditEntry(msg, "modify - #{newlist.join ', '}")
        if sched
            sched["people"] = newlist
            response.push @saveEntry(msg, i, sched)
        else
            response.push {"error":"Could not find schedule entry corresponding to index #{util.inspect idx}"}
      errors = (s["error"] for s in response when s["error"])
      success = (s["success"] for s in response when s["success"])
      msg.reply "#{errors.join('\n')}\n#{success.join('\n')}"

    pruneSchedule: (msg, sched) ->
    # prune old entries, keeping only 30 expired schedules
      idx = @getIndexEntry msg, (new Date).getTime(), false, sched
      if idx and idx['date']
        cutoff = idx['date'] - 86400000 # cutoff 24 hours prior to the current schedule entry
        index = @getIndexRange(msg,0,idx['date'] - 1000,true, sched)
        while index.length > 30
          @purgeIndex(msg,index[0],sched)
          index = index[1..]

    #startup initialization
    bootstrap: (robot) ->
      if not robot
        process.stdout.write "No robot, cannot initialize. Bad human! Bad!"
        return
      fakemsg=
        robot: robot
        message: 
          user: 
            reply_to: '20796_99195@chat.hipchat.com'
            name: 'Basho Bot'
            mention_name: 'BashoBot'
            jid: '20796_99195@chat.hipchat.com' 
          text: 'bootstrap process'
          id: undefined
          done: false
          room: undefined
        reply: (text) ->
          @robot.messageRoom process.env.ESCALATION_NOTIFICATIONROOM ? "Shell", text
        send: (text) ->
          @robot.messageRoom process.env.ESCALATION_NOTIFICATIONROOM ? "Shell", text
      @cronApplySchedules fakemsg
      @cronRemoteSchedules fakemsg

    # confirmation - on the first pass, store an entry in the brain
    # ignore confirmation for 5 seconds to accomodate Hipchate duplicating messages
    # ignore confirmation entries older than 5 minutes
    confirm: (msg, note) ->
      userid = msg.message.user.jid
      room = msg.message.room
      cmd = msg.message.text
      confmsg = msg.robot.brain.get "ocs-confirm-#{userid}-#{room}"
      conftime = new Date
      conftime = conftime.getTime()
      haveMatch = (confmsg and (note is confmsg["msg"]) and (cmd is confmsg["cmd"]))
      # confirmation must match user id, room, message(user command), note(request confirmation), and be within 5-300 seconds of the initial command
      if haveMatch and (confmsg["time"] + 5000 <= conftime) and ((confmsg["time"] + 300000) >= conftime)
          msg.robot.brain.remove "ocs-confirm-#{userid}-#{room}"
          return true
      else
        msg.reply note
        if not haveMatch or (haveMatch and ((confmsg["time"] + 300000) < conftime))
            msg.robot.brain.set "ocs-confirm-#{userid}-#{room}", {"msg":note, "time": conftime, "cmd":cmd}
        return false

onCall.roles = {
    DATA: 
      name: "Data"
      show: (msg) ->
        onCall.showRole msg, 'Data'    
      set: (msg,name) ->
        onCall.addToRole msg, 'Data', name
      unset: (msg,name) ->
        onCall.removeFromRole msg, 'Data', name
      get: (msg, fun) ->
          fun(onCall.getRole msg, 'Data')
    
    RIKER: 
      name: "Riker"
      show: (msg) ->
        onCall.showRole msg, 'Riker'    
      set: (msg,name) ->
        onCall.addToRole msg, 'Riker', name
      unset: (msg,name) ->
        onCall.removeFromRole msg, 'Riker', name
      get: (msg, fun) ->
          fun(onCall.getRole msg, 'Riker')

    REDSHIRT:
      name: "Redshirt"
      show: (msg) ->
        onCall.showRole msg, 'Redshirt'    
      set: (msg,name) ->
        onCall.addToRole msg, 'Redshirt', name
      unset: (msg,name) ->
        onCall.removeFromRole msg, 'Redshirt', name
      get: (msg, fun) ->
          fun(onCall.getRole msg, 'Redshirt')

}

module.exports = (robot) ->

  robot.logger.info "Escalation/OnCall module loading"
  robot.onCall = onCall
  
  robot.brain.once "loaded", () =>
   if "roleManager" of robot
     for role of onCall.roles
       robot.logger.info "Register #{role}: #{robot.roleManager.register(role,onCall.roles[role])}"
   else
     robot.logger.info "defer roles"
     robot.roleHook ||= []
     robot.roleHook.push (robot) ->
       robot.logger.info "Deferred Register #{role}: #{robot.roleManager.register role, robot.onCall.roles[role]}" for own role of robot.onCall.roles
   onCall.schedule.bootstrap robot
  
  # This is extremely dangerous, but very useful while debugging
  # It will permit anyone who can talk to the robot to execute
  # arbitrary javascript
  robot.respond /inspect (.*)/, (msg) ->
    eval "obj=#{msg.match[1]}"
    msg.reply "#{util.inspect obj}"

  robot.respond /purge \s*(?:the )?on[- ]?call schedule$/, (msg) ->
    msg.send "purge all"
    onCall.schedule.purge msg

  robot.respond /purge \s*(?:the )?(.*) on[- ]?call schedule$/, (msg) ->
    msg.send "purge by name #{msg.match[1]}"
    idx = onCall.schedule.fuzzyNameToIndex msg, msg.match[1].trim()
    if idx != null
      onCall.schedule.purgeSchedule msg,idx 

  robot.respond /delete \s*(?:the )?(.*) on[- ]?call schedule$/, (msg) ->
    idx = onCall.schedule.fuzzyNameToIndex msg, msg.match[1].trim()
    if idx != null
      onCall.schedule.deleteSchedule msg,idx 

  robot.respond /(?:check|repair|fix|unfuck) *(?:the )?(.*) \s*on[- ]?call schedule index\s*/, (msg) ->
    if not msg.match[1]? or msg.match[1] is ""
        idx = null
    else
        idx = onCall.schedule.fuzzyNameToIndex msg, msg.match[1].trim()
    onCall.schedule.checkIndex msg, idx

  robot.respond /load \s*on[- ]?call \s*schedule\s*\n?(.*)/i, (msg) ->
    onCall.schedule.fromCSV msg

  robot.respond /apply \s*(?:the )?(.*) on[- ]?call \s*schedule\s*/i, (msg) ->
    idx = onCall.schedule.fuzzyNameToIndex msg, msg.match[1].trim?()
    onCall.schedule.applySchedule msg, idx if idx?

  robot.respond /set (?:the )?\s*on[- ]?call \s*schedule (?:for |on )?\s*(today|tomorrow|\d+\/\d+\/\d\d\d\d) \s*to \s*(.*)/i, (msg) ->
    people = msg.match[2].split(",")
    msg.robot.logger.info "Create schedule for #{msg.match[1]} - #{msg.match[2]}"
    msg.send util.inspect onCall.schedule.createEntry(msg, msg.match[1], people, true)

  robot.respond /add \s*(.*) \s*to \s*(?:the )?(.*)\s*on[- ]?call \s*schedule \s*(?:for |on |from )?\s*(today|tomorrow|\d+\/\d+\/\d\d\d\d)\s*(?:until |thru |through |to )?\s*(today|tomorrow|\d+\/\d+\/\d\d\d\d)?\s*/i, (msg) ->
    if idx = onCall.schedule.fuzzyNameToIndex msg, msg.match[2].trim()
      people = msg.match[1].split(",")
      msg.robot.logger.info "Add #{people.toString()} to #{msg.match[2]} schedule for #{msg.match[3]} #{msg.match[4]}"
      onCall.schedule.modify msg, people, msg.match[2], msg.match[3], _.union

  robot.respond /unschedule \s*(.*) \s*from (?:the )?(.*)\s*on[- ]?call \s*(?:for |on |from )?\s*(today|tomorrow|\d+\/\d+\/\d\d\d\d)\s*(?:until |thru |through |to )?\s*(today|tomorrow|\d+\/\d+\/\d\d\d\d)?\s*/i, (msg) ->
    if idx = onCall.schedule.fuzzyNameToIndex msg, msg.match[2].trim()
      people = msg.match[1].split(",")
      msg.robot.logger.info "Remove #{people.toString()} from on-call for #{msg.match[3]}"
      onCall.schedule.modify msg,people, msg.match[3], msg.match[4], _.difference, idx

  robot.respond /clear \s*(?:the )?(.*)\s*on[- ]?call \s*schedule\s*(?:for |on |from )?\s*(today|tomorrow|\d+\/\d+\/\d\d\d\d)?\s*(?:until |to |through |thru )?\s*(today|tomorrow|\d+\/\d+\/\d\d\d\d)?\s*/i, (msg) ->
    if idx = onCall.schedule.fuzzyNameToIndex msg, msg.match[1].trim()
      msg.robot.logger.info "Clear the #{msg.match[1]} on-call schedule from #{msg.match[2]} to #{msg.match[3]}"
      onCall.schedule.clear msg, msg.match[2], msg.match[3], idx

  robot.respond /list \s*(?:the )?\s*on[- ]?call\s*schedules?\s*(details?)?/i, (msg) ->
    onCall.schedule.listSchedules msg, msg.match[1]?

  robot.respond /(?:export|display|show) (?:the)?\s*(next|current|tomorrow[']?s?|today[']?s?) \s*(.*)?\s*on[- ]?call \s*schedule\s*/i, (msg) ->
    today = new Date
    if not msg.match[2]? or msg.match[2] is ""
        schedules = msg.robot.brain.get('ocs-schedules').map (s) -> s.idx
    else
        schedules = onCall.schedule.fuzzyNameToIndex(msg, msg.match[2].trim())
    for s in schedules
      msg.send "#{onCall.schedule.indexToName(s)}(#{s}):"
      if /next|tomorrow/i.test msg.match[1]
        idx = onCall.schedule.getNextIndexEntry msg, today.getTime(), false, s
      else
        idx = onCall.schedule.getIndexEntry msg, today.getTime(), false, s
      if idx? and idx['date']
        onCall.schedule.toCSV msg, idx['date'], idx['date'], s
      else
        msg.reply "No more schedules found"

  robot.respond /(?:export|display|show) \s*(?:the)?(.*)?\s*on[- ]?call \s*schedule\s*(?:for |on |from )?\s*(yesterday|today|tomorrow|\d+\/\d+\/\d\d\d\d)?\s*(?:until |to |through |thru )?\s*(yesterday|today|tomorrow|\d+\/\d+\/\d\d\d\d)?\s*/i, (msg) ->
    if not msg.match[1]? or msg.match[1] is ""
      idx = null
    else
      idx = onCall.schedule.fuzzyNameToIndex msg, msg.match[1].trim()
    onCall.schedule.toCSV msg, msg.match[2], msg.match[3], idx

  robot.respond /audit \s*(?:the )?(.*)\s*\s*on[- ]?call \s*schedule\s*(?:for |on |from )?\s*(yesterday|today|tomorrow|\d+\/\d+\/\d\d\d\d)?\s*(?:through |thru |to |until )?\s*(yesterday|today|tomorrow|\d+\/\d+\/\d\d\d\d)?\s*/i, (msg) ->
    if not msg.match[1]
      msg.send "Please specify a schedule to audit"
      onCall.schedule.listSchedules msg, null
    else
      if idx = onCall.schedule.fuzzyNameToIndex msg, msg.match[1].trim()
        msg.robot.logger.info "Display #{msg.match[1]} audit records #{util.inspect msg.message.user}"
        onCall.schedule.audit msg, msg.match[2], msg.match[3], idx

  robot.respond /(?:who is|show me) on[- ]?call\??/i, (msg) ->
    msg.robot.logger.info "Checking on-call."
    onCall.list(msg)

  robot.respond /put (.*) on[- ]?call\s*/i, (msg) ->
    people = msg.match[1].trim().split(/\s*,\s*/)
    msg.robot.logger.info "Adding #{util.inspect people} to on-call list"
    onCall.add msg, people

  robot.respond  /remove (.*) from on[- ]?call\s*/i, (msg) ->
    people = msg.match[1].trim().split(/\s*,\s*/)
    msg.robot.logger.info "Removing #{util.inspect people} from on-call list"
    onCall.remove msg, people

  robot.respond  /reset on[- ]?call\s*/i, (msg) ->
# Needs love here
    msg.reply "Reset functionality needs some work, so I have disabled it for now."
    return
    msg.robot.logger.info "Resetting the on-call list"
    onCall.modify msg, [""], _.intersection
    onCall.schedule.applySchedule msg

  robot.respond /set (?:on[- ]?call name|on_call_name) for (.*) to (.*)$/i, (msg) ->
    msg.robot.roleManager.mapUserName msg, 'on_call_name', msg.match[1], msg.match[2]

  robot.respond /update(?: the)* (.*)\s*on[ -]?call schedule from google(?: docs?)*\s*uri (.*) doci?d? ([^ ]*) sheet (.*) range (.*)/i, (msg) ->
    idx = onCall.schedule.fuzzyNameToIndex msg, msg.match[1].trim()
    if (idx? && msg.match[2] && msg.match[3] && msg.match[4] && msg.match[5])
      onCall.schedule.linkScheduleToGoogleDoc msg, idx, "https://script.google.com/#{msg.match[2]}", msg.match[3], msg.match[4], msg.match[5]

  robot.respond /update(?: the)* (.*)\s*on[ -]?call schedule from google(?: docs?)?\s*$/i, (msg) ->
    idx = onCall.schedule.fuzzyNameToIndex msg, msg.match[1].trim()
    if idx != null
      onCall.schedule.remoteSchedule msg, idx

  robot.respond /create new (ad[ -]?hoc|normal|regular)*\s*on-call schedule (?:named )*\s*(.*)/i, (msg) ->
    msg.send "onCall.schedule.createSchedule msg, #{msg.match[1]}, #{msg.match[2]}"
    onCall.schedule.createSchedule msg, msg.match[1], msg.match[2]

  robot.respond /show the on[- ]?call queue/i, (msg) -> 
    onCall.showQueue(msg)

  robot.respond /set cron apply for (.*) on[- ]?call schedule to (.*)/i, (msg) ->
    idx = onCall.schedule.fuzzyNameToIndex msg, msg.match[1].trim()
    onCall.schedule.cronApplySchedule(msg, msg.match[2].trim(), idx) if idx?

  robot.respond /set cron update for (.*) on[- ]?call schedule to (.*)/i, (msg) ->
    idx = onCall.schedule.fuzzyNameToIndex msg, msg.match[1].trim()
    onCall.schedule.cronRemoteSchedule(msg, msg.match[2].trim(), idx) if idx?

  robot.respond /cron update(?: the)* (.*)\s*on[ -]?call schedule from google(?: docs)* ([^ ]* [^ ]* [^ ]* [^ ]* [^ ]* [^ ]*)/i, (msg) ->
    idx = onCall.schedule.fuzzyNameToIndex msg, msg.match[1].trim()
    if idx != null
      onCall.schedule.cronRemoteSchedule msg, msg.match[2], idx 

  robot.respond /page (.*) message (.*)/i, (msg) ->
    onCall.page msg, msg.match[1].split(","), msg.match[2]

  robot.respond /page (.*)/i, (msg) ->
    if not msg.match[1].match /.* message .*/
      msg.reply "please include a message - `page <name> message <text>`"
