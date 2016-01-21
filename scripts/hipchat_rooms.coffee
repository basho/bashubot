# Description:
#  hipchat_rooms - support creating, opening, closing, and capturing history from  rooms
#
# Commands:
#  hubot find room for ticket <ticket number>
#  hubot open room for ticket <ticket number>
#  hubot close room for ticket <ticket number>
#  hubot create room for ticket <ticket number>
#  hubot attach|quote chat log to ticket <ticket number>
#  hubot list open rooms
#  hubot list all rooms
#  hubot get list of rooms
#  hubot show all rooms
#  hubot show rooms like <pattern>
#  hubot list rooms like <pattern>
#  hubot archive room <name>
#  hubot unarchive room <name>
#  hubot archive rooms <name, name, name>
#  hubot unarchive rooms <name, name, name>
#  hubot usurp room <room name> for ticket <ticket number>
#
# Dependencies:
#  util
#  fuzzy
#  hipchatter
#  underscore
#
# Configuration
#  HUBOT_HIPCHAT_TOKEN
#

util = require 'util'
fuzzy = require 'fuzzy'
_ = require 'underscore'
Hipchatter = require 'hipchatter'
hipchatter = new Hipchatter(process.env.HUBOT_HIPCHAT_TOKEN)

# if infinite modules were infinitely monkey patched ...
#hipchatter.roomsPayload = (payload,callback) ->
#  @request 'get', 'room', payload, (err, results) ->
#    if (err) 
#        callback err
#    else 
#        callback err, results.items

hipchatApi = 

  getRoom: (msg,name) ->
    hipchatter.get_room name, (err,data) ->
      if err is null
        msg.reply util.inspect data
      else
        msg.reply err

  setGuestFromTicket: (msg,ticketnum,access) ->
      @roomFromTicket(msg,ticketnum) (err,room) =>
        if err isnt null
          msg.reply err
        else
          @setGuest(msg,room.id,access) (err,resp) ->
            msg.reply err if err?
            msg.reply resp if resp?

  printTranscript: (msg, ticketnum) ->
    (callback) =>
      @roomFromTicket(msg, ticketnum) (err, room) =>
        if err isnt null
          msg.reply err
        else
          hipchatter.request 'get', "room/#{room.id}/history/latest", {'max-results':1000}, (err, data) =>
          #hipchatter.history room.id, (err, data) =>
            if err isnt null
              msg.reply err
            else
              startMessage = "Begin support session for ticket #{ticketnum}"
              replyArray = []
              printout = false
              for item in data.items
                printout = true if item.message is startMessage
                #if we are at the current ticket session, start gathering transcript
                if printout
                  d = new Date(parseInt(Date.parse(item.date)))
                  formattedDate = "#{d.getMonth() + 1}/#{d.getDate()}/#{d.getFullYear()} #{d.getHours()}:#{if d.getMinutes() < 10 then '0' else ''}#{d.getMinutes()}"
                  #filter out BashoBot and HipChat messages
                  item.message = "File - #{item.file.name} - #{item.file.url}.  " + item.message if item.file isnt undefined
                  replyArray.push "[#{formattedDate}] #{item.from.name}: #{item.message}" if item.from.name? and (item.from.name isnt "Basho Bot")
                  replyArray.push "[#{formattedDate}] #{item.from}: #{item.message}" if (typeof item.from is "string") and (item.from isnt "Basho Bot")
              pnote = "#{replyArray.join("\n")}"
              msg.robot.zenDesk.uploadComment msg, ticketnum, "Adding chat transcript from recent HipChat conversation.", true, "ticket_#{ticketnum}_transcript.txt","text/plain", pnote, (retObj) ->
                msg.reply("Updated ticket #{ticketnum}")

  setGuestFromTicketAndTag: (msg,ticketnum,access) ->
    @roomFromTicket(msg,ticketnum) (err,room) =>
      if err isnt null
        msg.reply err
      else
        @setGuest(msg,room.id,access) (err,resp) =>
          if err isnt null
            msg.reply err
          else
            @tagChat(msg,room.id,ticketnum,access) (err) =>
              if err is null
                msg.reply "#{resp}\nChat tagged"
                if access
                  @summon(msg,room.id) (err,msg) ->
                    #does anything need to happen here?
              else
                msg.reply "#{resp}\nError tagging chat: #{err}"

  setGuest: (msg, roomid, access) ->
    (callback) =>
      allow = access? and access isnt false
      hipchatter.get_room roomid, (err,data) =>
        if err isnt null
          callback("Unable to retrieve room #{msg.robot.brain.data.hipchatrooms[roomid].name}: #{err}",null)
        else 
          if allow and not (data.name.match(/^Cust:/i) and not data.name.match(/internal/i))
            callback("Room name must begin with 'Cust:' and not contain 'internal'",null)
          else
            if data['is_guest_accessible'] == allow
              callback("Room #{data.name} guest access is already #{allow}#{if allow then "\nGuest access URL is #{data.guest_access_url}" else ""}",null)
            else
              params={}
              (params[k] = data[k] for k in ["name","privacy","is_archived","topic","owner","id","is_guest_accessible"])
              archived = params['is_archived']
              params['is_archived'] = false
              if archived
                @setArchived(msg, data.id, false) (error, newdata) =>
                  if error isnt null
                    msg.reply "failed to set room #{params['name']} to unarchived: #{error}"
                  else
                    @setGuest(msg, roomid, access) (err, resp) =>
                      params['is_archived'] = true
                      @setArchived(msg, params.id, true) (error,newdata) =>
                        if error isnt null
                          msg.reply "failed to set room #{params['name']} back to archived: #{error}"
                        else 
                          callback err, resp 
              else
                params['is_guest_accessible'] = allow
                hipchatter.update_room params, (error,newdata,code) =>
                  if error isnt null
                    callback("Unable to update room #{data.name}: #{error}",null)
                  else
                    if code is 204
                      hipchatter.get_room roomid, (err,newerdata) ->
                        if err is null
                          callback(null,"Updated room #{newerdata.name}, guest access is now #{allow}#{if allow then "\nGuest access URL is #{newerdata.guest_access_url}" else ""}")
                        else
                          callback("Updated room #{newdata.name}, guest access is now #{allow}#{if allow then "Error retreiving guest URL: #{err}" else ""}")
                    else
                      callback("Unexpected code #{code} updating room #{data.name}",null)

  setArchived: (msg, roomid, value) ->
    (callback) =>
      hipchatter.get_room roomid, (err, data) ->
        if err isnt null
          callback err
        else
          data.is_archived = value
          hipchatter.update_room data, (error, newdata, code) ->
            if error isnt null
              callback(error)
            else
              callback null, newdata

  archiveRoom: (msg, roomname, bool) ->
      @fuzzyMatchRoom(msg, roomname, false) (err, room) =>
        if err isnt null
          msg.reply "#{err}"
        else
          if room.length is 1
            @setArchived(msg, room[0].id, bool) (err, newdata) ->
              if err isnt null 
                msg.reply "Error #{if !bool then 'un' else ''}archiving #{roomname}: #{err}"
              else
                msg.reply "#{if !bool then 'un' else ''}archived #{roomname}"
          else
            msg.reply "Found #{room.length} matching '#{roomname}':#{_.map(room, (r) -> r.name).join(", ")}"

  listRooms: (msg,index=0,roomlist=[]) ->
   (callback) =>
     hipchatter.request 'get','room', {'max-results':100,'start-index':index,'expand':'items.self','include-archived':true}, (err,response) =>
       if err isnt null
         callback "Error getting room list: #{err}"
       else
          newlist = response.items
          roomlist = roomlist.concat newlist
          if newlist.length < 100
            callback?(null, roomlist)
          else
            @listRooms(msg,index + 100,roomlist) callback

  printRoomList: (msg, like) ->
    @listRooms(msg) (err,list) ->
      if err isnt null
        msg.reply util.inspect err
      else
        if like
            fuzzynames = fuzzy.filter like, list, {caseSensitive: false; extract: (e) -> e.name}
            minScore = 10 #for search strings longer than 3 chars, 10 points is a fairly confident match
            minScore = 5 if like.length < 4 # shorter search strings can't generate as many points
            warmfuzzy = _.filter fuzzynames, (e) -> e.score >= minScore          
            filtered = _.map warmfuzzy, (e) -> e.original
        else 
            filtered = list
        sorted = _.sortBy filtered, "name"
        res = ["ga Name[ID]"]
        _.map sorted, (room) -> res.push "#{if room.is_guest_accessible then 'g' else '-'}#{if room.is_archived then 'a' else '-'} #{room.name}   [#{room.id}]"
        if res.length > 1
            msg.send res.join("\n")
        else
            msg.send "Unable to get room list"

  updateLocalRoom: (msg, data) ->
    room = msg.robot.brain.data.hipchatrooms[data.id] || {}
    (room[k] = data[k] for k of data)
    msg.robot.brain.data.hipchatrooms[room.id] = room

  updateCustRooms: (msg) ->
    (callback) =>
      @listRooms(msg) (err, roomlist) =>
        if err isnt null
          callback(err,null)
        else
          @updateLocalRoom(msg,{id:r.id, name:r.name, archived:r.is_archived, open:r.is_guest_accessible}) for r in roomlist when r.name.match(/^Cust:/i) and not r.name.match(/internal/i)
          callback(null,msg.robot.brain.data.hipchatrooms) 

  pairedRoom: (msg,orgid) ->
      knownrooms = msg.robot.brain.data.hipchatrooms
      (room for room of knownrooms when knownrooms[room].orgid is orgid)

  findRoomFromOrgName: (msg, orgname) ->
    (callback) =>
        @fuzzyMatchRoom(msg, orgname.slice(0,35)) (err,r) ->
          switch r?.length || 0
            when 1
              callback(null,r[0])
            when 0
              if err is null
                callback("Not found",null)
              else
                callback("Error: #{err}",null)
            else
              callback("Multiple matches: #{util.inspect r}",r)

  makeRoomNameFromOrgId: (msg, orgid) ->
    (callback) =>
      msg.robot.zenDesk.getOrganization(msg,orgid) (org) =>
        if org?.name? and org.id?
          callback(null,"Cust: #{org.name.slice(0,40)}")
        else
          callback("Error get org data for #{orgid}:#{org}",null)

  roomFromOrgId: (msg, orgid) ->
    (callback) =>
      error = null
      room = null
      paired = @pairedRoom msg, orgid
      if paired.length == 0 
        msg.robot.zenDesk.getOrganization(msg,orgid) (org) =>
          if org?.name? and org.id?
            @findRoomFromOrgName(msg, org.name) callback
          else
            callback("Error getting orgname from id: #{org}",null)
      else
        room = msg.robot.brain.data.hipchatrooms[paired[0]]
        callback(error,room)

  orgIdFromTicket: (msg, ticketnum) ->
    (callback) ->
       msg.robot.zenDesk.ticketData(msg, ticketnum) (ticket) ->
          if ticket?.organization_id?
            callback(null, ticket.organization_id)
          else
            callback("Error getting orgig from ticket #{ticketnum}:#{ticket}",null)

  roomFromTicket: (msg, ticketnum) ->
    (callback) =>
        @orgIdFromTicket(msg,ticketnum) (err,orgid) =>
          if err is null
            @roomFromOrgId(msg, orgid) (err, room) ->
              if err is null and room?.id?
                callback(null,room)
              else
                if err
                  callback(err,null) 
                else
                  callback("No Room Found",null)
          else
            callback(err,null)

  roomNameFromTicket: (msg, ticketnum) ->
    (callback) =>
      @roomFromTicket(msg,ticketnum) (err,room) ->
        if err is null
            callback(null,room.name)
        else
            callback(err,null)

  findInternalRoom: (msg, roomid) ->
    (callback) =>
      @listRooms(msg) (err,roomlist) ->
        if err isnt null
            callback?(err,null)
        else
         roomname = (_.filter roomlist, (e) -> e.id == roomid)[0].name
         internal = _.filter roomlist, (e) -> e.name.match(/^Cust:/i) and e.name.match(/internal/i)
         exact = _.filter internal, (e) -> e.name.toUpperCase() == "#{roomname} (internal)".toUpperCase() or e.name.toUpperCase() == "#{roomname}(internal)".toUpperCase()
         switch exact?.length || 0
            when 1
              callback(null,exact[0])
            else
              close = _.filter internal, (e) -> fuzzy.test roomname, e.name
              switch close?.length || 0
                when 1
                  callback(null,close[0])
                else
                  callback("No Match",null)
         

  fuzzyMatchRoom: (msg, roomname, nofetch) ->
  # check first for exact match, then case-insensitive, then fuzzy
  # update the room list once if no match is found
    (callback) =>
      list = msg.robot.brain.data.hipchatrooms
      exact = (list[roomid] for roomid of list when list[roomid].name == roomname)
      matched = false
      switch exact?.length || 0
        when 0
          upper = (list[roomid] for roomid of list when list[roomid].name.toUpperCase() == roomname.toUpperCase())
          switch upper?.length || 0
            when 0
              fuzzymat = (list[roomid] for roomid of list when fuzzy.test roomname.toUpperCase(), list[roomid].name.toUpperCase())
              if fuzzymat.length > 0
                matched = true
                callback null, fuzzymat
            else
              matched = true
              callback null, upper
        else
          matched = true
          callback null, exact
      if not matched
        if nofetch
          callback("No match found",null)
        else
          @updateCustRooms(msg) (err,roomlist) =>
            if err isnt null
              callback("Error retrieving room list: #{err}",null)
            else 
              @fuzzyMatchRoom(msg,roomname,true) callback

  usurpRoom: (msg, roomname, ticketnum) ->
    (callback) =>
       msg.robot.zenDesk.ticketData(msg,ticketnum) (ticket) =>
         if typeof ticket is 'object' and 'organization_id' of ticket
           msg.robot.zenDesk.getOrganization(msg,ticket.organization_id) (org) =>
             paired = @pairedRoom msg, org.id
             if paired.length == 0
               @fuzzyMatchRoom(msg, roomname) (err,matchedlist) ->
                 if err isnt null or matchedlist is null
                   callback err, null
                 else
                   if matchedlist.length > 1
                     callback "Multiple rooms match #{roomname}: #{util.inspect (r.name for r in matchedlist)}", null
                   else 
                     matchedroom = matchedlist[0]
                     if matchedroom.name.match(/^Cust:/i) and not matchedroom.name.match(/internal/i)
                       if matchedroom.orgid? 
                         msg.robot.zenDesk.getOrgName(msg, matchedroom.orgid) (orgname) ->
                           callback("Room #{matchedroom.name} already belongs to #{orgname}",null)
                       else
                         hipchatter.get_room matchedroom.id, (err,data) ->
                           if err is null
                            params = 
                              owner: 
                                mention_name:"@bashobot"
                                id: 99195
                              is_guest_accessible: false
                            (params[k] = data[k] for k in ["name","privacy","is_archived","topic","id"])
                            hipchatter.update_room params, (err, newdata) ->
                              if err is null
                                msg.robot.brain.data.hipchatrooms[matchedroom.id].orgid = org.id
                                callback(null,"Room #{matchedroom.name} paired with #{org.name}")
                              else
                                callback("Error updating room #{data.name}: #{err}",null)
                           else
                            callback("Error fetching room #{matchedroom.name} for update:#{err}",null)
                     else
                       callback("Room name must begin with 'Cust:' and not contain 'internal'",null)
             else
               callback("Organization #{org.name} already paired with room: #{(room.name for room in paired).join ", "}",null)
         else
           callback("Error getting ticket #{ticketnum}: #{util.inspect ticket}",null)

  createRoom: (msg, ticketnum) ->
    (callback) =>
      @orgIdFromTicket(msg,ticketnum) (err,orgid) =>
        if err is null
          @roomFromTicket(msg, ticketnum) (err, room) =>
            if err is null
              callback("Room already exists: #{util.inspect room}",null)
            else
              @makeRoomNameFromOrgId(msg, orgid) (err,roomname) ->
                if err is null
                  hipchatter.room_exists roomname, (err,exists) ->

                    # hipchatter expects "Room not found"
                    # HipChat API now returns "Room '<roomname>' not found"
                    # so until PR https://github.com/charltoons/hipchatter/pull/25 is accepted
                    exists = false if "#{err}" == "Error: Room '#{roomname}' not found"
                    
                    if exists is false 
                      msg.robot.zenDesk.getOrgName(msg, orgid) (orgname) ->
                        newroom = 
                          name: roomname
                          topic: "#{orgname} support"
                          privacy: "public"
                          #owner_user_id: "@bashobot"
                          guest_access: false
                        hipchatter.create_room newroom, (err,body,code) ->
                          if err is null
                            newroom.name = "#{roomname} (internal)"
                            hipchatter.create_room newroom, (err,body,code) ->
                              if err is null
                                callback(null,"Created room #{roomname} and #{newroom.name}") 
                              else
                                callback("Error creating #{newroom.name}: #{err}","Created room #{roomname}")
                          else
                            callback("Error creating room #{roomname}: #{err}",null)
                    else if exists is true
                      callback("Room #{roomname} already exists, try 'usurp room #{roomname} for ticket #{ticketnum}'",null)
                    else
                      callback("Error checking room #{roomname} exists: #{util.inspect err}",null)
                else
                  callback("Error building room name: #{err}",null)
        else
          callback(err,null)

  findOpen: (msg, roomlist, openlist=[], errorlist=[]) ->
    (callback) =>
      if roomlist.length == 0
        callback(errorlist,openlist)
      else
        roomname = roomlist.shift()
        hipchatter.get_room roomname, (err,room,code) =>
          if code == 429
            errorlist.push("Aborting due to HipChat API rate limit")
            @findOpen(msg,[],openlist,errorlist) callback
          else
            if err is null and room?.is_guest_accessible?
              openlist.push(room.name) if room.is_guest_accessible
            else
              errorlist.push([roomname,err])
            @findOpen(msg, roomlist, openlist, errorlist) callback

#  listOpenRooms: (msg) ->
#    @updateCustRooms(msg) (err,rooms) =>
#      if err isnt null
#        msg.reply "Error getting room list: #{err}"
#      else 
#        roomlist = (rooms[r].id for r of rooms)
#        msg.send "Checking #{roomlist.length} rooms"
#        @findOpen(msg, roomlist) (err, openlist) ->
#          if err is null or err is []
#            if openlist.length > 0
#              msg.reply "Open rooms: #{openlist.join "\n"}"
#            else
#              msg.reply "No open rooms"
#          else
#            msg.reply "Error getting data for: #{err.join "\n"}"
#            msg.reply "Open rooms: #{openlist.join "\n"}" if openlist?.length > 0

  listOpenRooms: (msg) ->
    @updateCustRooms(msg) (err,rooms) ->
      if err isnt null
        msg.reply "Error getting room list: #{err}"
      else
        openRooms = _.filter rooms, (r) -> r.open and !r.archived
        names = _.map openRooms, (r) -> r.name
        msg.reply names.join("\n")
  
  closeArchived: (msg) ->
    @updateCustRooms(msg) (err, rooms) =>
      if err isnt null
        msg.reply "Error getting room list: #{err}"
      else
        openArchived = _.filter rooms, (r) => r.open and r.archived
        _.each openArchived, (r) =>
          @setGuest(msg, r.id, false) (err, resp) ->
            msg.send err if err?
            msg.send resp if resp?

  tagChat: (msg, roomid, ticketnum, access) ->
    (callback) ->
      message="#{if access then 'Begin' else 'End' } support session for ticket #{ticketnum}"
      hipchatter.request 'post', 'room/'+roomid+'/notification', {message: message}, (err,body) -> 
        callback?(err,body)

  summon: (msg, roomid) ->
    (callback) =>
      message="@#{msg.envelope.user.mention_name}"
      hipchatter.request 'post', 'room/'+roomid+'/notification', {message: message,message_format:'text'}, (err,body) => 
        if err is null
          @findInternalRoom(msg, roomid) (err1,room1) ->
            if err is null
              hipchatter.request 'post', 'room/'+room1.id+'/notification', {message: message,message_format:'text'}, (err,body) =>
                callback?(err,body)
            else
              callback?(err1,room1)
        else
          callback?(err,body)

module.exports = (robot) ->
  if not robot.brain.data.hipchatrooms
    robot.brain.data.hipchatrooms = {}
  robot.respond /(?:get|show) room (.*)\s*$/i, (msg) ->
    msg.send msg.match[1]
    hipchatApi.getRoom msg, msg.match[1]

  robot.respond /(?:find|locate|which|where is) (?:the|hipchat)*\s*room (?:for |in )*ticket [#]?([0-9]*)\s*$/i, (msg) ->
    hipchatApi.roomNameFromTicket(msg,msg.match[1]) (err,room) ->
      msg.reply "Error: #{err}" if err?
      msg.reply room if room?

  robot.respond /(?:open|permit|allow|guest|turn on) (?:the |access |guest |to |for |hipchat )*room (?:for|in) ticket [#]?([0-9]*)\s*$/i, (msg) ->
    hipchatApi.setGuestFromTicketAndTag msg,msg.match[1], true

  robot.respond /(?:close|deny|disallow|reject|turn off) (?:the |guest |access |to |for |hipchat )*room (?:for|in) ticket [#]?([0-9]*)\s*$/i, (msg) ->
    hipchatApi.setGuestFromTicketAndTag msg,msg.match[1], false

  robot.respond /(?:create|make) (?:new |hipchat |a )*room (?:for|in)*\s*ticket [#]?([0-9]*)\s*$/i, (msg) ->
    hipchatApi.createRoom(msg,msg.match[1]) (err,created) ->
      msg.reply err if err?
      msg.reply created if created?

  robot.respond /(?:attach |quote |chat )*\s*log to ticket [#]?([0-9]*)\s*$/i, (msg) ->
    hipchatApi.printTranscript(msg, msg.match[1]) (err, generated) ->
      msg.reply err if err?
      msg.reply generated if generated?

  robot.respond /(?:list |show |all )*(?:open|guest|accessible|public) rooms/i, (msg) ->
    hipchatApi.listOpenRooms msg

  robot.respond /close archive[sd]? rooms/i, (msg) ->
    hipchatApi.closeArchived msg

  robot.respond /archive room (.*)/i, (msg) ->
    msg.robot.logger.info "archive #{msg.match[1]}"
    hipchatApi.archiveRoom msg, msg.match[1], true
  
  robot.respond /unarchive room (.*)/i, (msg) ->
    msg.robot.logger.info "unarchive #{msg.match[1]}"
    hipchatApi.archiveRoom msg, msg.match[1], false
  
  robot.respond /archive rooms (.*)/i, (msg) ->
    _.each msg.match[1].split(","), (room) ->
      msg.robot.logger.info "archive #{room}"
      hipchatApi.archiveRoom msg, room.trim(), true
  
  robot.respond /unarchive rooms (.*)/i, (msg) ->
    _.each msg.match[1].split(","), (room) ->
      msg.robot.logger.info "unarchive #{room}"
      hipchatApi.archiveRoom msg, room.trim(), false

  robot.respond /(?:usurp|commandeer|take over|hijack|use) (?:hipchat|customer)*\s*room (.*) for ticket [#]?([0-9]*)\s*$/, (msg) ->
    hipchatApi.usurpRoom(msg, msg.match[1], msg.match[2]) (err,result) ->
      msg.reply err if err?
      msg.reply result if result?

  robot.respond /get org for ticket #]? (.*)$/i, (msg) ->
    msg.robot.zenDesk.getOrgNameFromTicket(msg, msg.match[1]) (Org) ->
      msg.reply Org

  robot.respond /(get )*(list|show) (of |all )rooms/i, (msg) ->
    msg.robot.logger.info "show all rooms"
    hipchatApi.printRoomList msg

  robot.respond /(?:list|show) rooms like (.*)$/i, (msg) ->
    msg.robot.logger.info "show like #{msg.match[1]}"
    hipchatApi.printRoomList msg, msg.match[1]

  robot.respond /group test (.*)/i, (msg) ->
    eval "obj=#{msg.match[1]}"
    msg.reply "#{util.inspect obj}"
