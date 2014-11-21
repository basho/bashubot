# Description:
#  hipchat_rooms - support creating, opening, closing, and capturing history from  rooms
#
# Commands:
#  hubot find room for ticket #<ticket number>
#  hubot open room for ticket #<ticket number>
#  hubot close room for ticket #<ticket number>
#  hubot create room for ticket #<ticket number>
#  hubot attach chat log to ticket #<ticket number>
#  hubot list open rooms
#  hubot usurp room <room name> for ticket #<ticket number>
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

  setGuestFromTicketAndTag: (msg,ticketnum,access) ->
    @roomFromTicket(msg,ticketnum) (err,room) =>
      if err isnt null
        msg.reply err
      else
        @setGuest(msg,room.id,access) (err,resp) =>
          if err is null
            @tagChat(msg,room.id,ticketnum,access) (err) =>
              if err is null
                msg.reply "#{resp}\nChat tagged"
                if access
                  @summon(msg,room.id) (err,msg) ->
                    #does anything need to happen here?
              else
                msg.reply "#{resp}\nError tagging chat: #{err}"

  setGuest: (msg,roomid,access) ->
    (callback) ->
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
              params ={"is_guest_accessible":allow}
              (params[k] = data[k] for k in ["name","privacy","is_archived","topic","owner","id"])
              hipchatter.update_room params, (error,newdata,code) =>
                if error isnt null
                  callback("Unable to update room #{data.name}: #{error}",null)
                else
                  if code is 204
                    hipchatter.get_room roomid, (err,newdata) ->
                      if err is null
                        callback(null,"Updated room #{data.name}, guest access is now #{allow}#{if allow then "\nGuest access URL is #{newdata.guest_access_url}" else ""}")
                      else
                        callback(null,"Updated room #{newdata.name}, guest access is now #{allow}#{if allow then "Error retreiving guest URL: #{err}" else ""}")
                  else
                    callback("Unexpected code #{code} updating room #{data.name}",null)

  listRooms: (msg,index=0,roomlist=[]) ->
   (callback) =>
     hipchatter.request 'get','room', {'max-results':100,'start-index':index}, (err,response) =>
       if err isnt null
         callback "Error getting room list: #{err}"
       else
          newlist = response.items
          roomlist = roomlist.concat newlist
          if newlist.length < 100
            callback?(null, roomlist)
          else
            @listRooms(msg,index + 100,roomlist) callback

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
          @updateLocalRoom(msg,{id:r.id,name:r.name}) for r in roomlist when r.name.match(/^Cust:/i) and not r.name.match(/internal/i)
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
              callback("Multiple matches",r)

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

  listOpenRooms: (msg) ->
    @updateCustRooms(msg) (err,rooms) =>
      if err isnt null
        msg.reply "Error getting room list: #{err}"
      else 
        roomlist = (rooms[r].id for r of rooms)
        msg.send "Checking #{roomlist.length} rooms"
        @findOpen(msg, roomlist) (err, openlist) ->
          if err is null or err is []
            if openlist.length > 0
              msg.reply "Open rooms: #{openlist.join "\n"}"
            else
              msg.reply "No open rooms"
          else
            msg.reply "Error getting data for: #{err.join "\n"}"
            msg.reply "Open rooms: #{openlist.join "\n"}" if openlist?.length > 0

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

  robot.respond /(?:attach|quote|chat)*\s*log to ticket [#]?([0-9]*)\s*$/i, (msg) ->
    msg.reply "not yet implemented"

  robot.respond /(?:list |show |all )*(?:open|guest|accessible|public) rooms/i, (msg) ->
    hipchatApi.listOpenRooms msg

  robot.respond /(?:usurp|commandeer|take over|hijack|use) (?:hipchat|customer)*\s*room (.*) for ticket [#]?([0-9]*)\s*$/, (msg) ->
    hipchatApi.usurpRoom(msg, msg.match[1], msg.match[2]) (err,result) ->
      msg.reply err if err?
      msg.reply result if result?

  robot.respond /get org for ticket (.*)$/i, (msg) ->
    msg.robot.zenDesk.getOrgNameFromTicket(msg, msg.match[1]) (Org) ->
      msg.reply Org

  robot.respond /get list of rooms/i, (msg) ->
    hipchatApi.updateCustRooms(msg) (err,list) ->
      msg.reply util.inspect err if err isnt null
      msg.reply util.inspect list

  robot.respond /group test (.*)/i, (msg) ->
    eval "obj=#{msg.match[1]}"
    msg.reply "#{util.inspect obj}"
