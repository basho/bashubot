HTTPS = require 'https'
_ = require 'underscore'

apikey = process.env.AGILEZEN_APIKEY

defaultOptions =
  "agent"  : false
  "host"   : "agilezen.com"
  "port"   : 443
  "method" : "GET"
  "headers" :
    "Accept" : "application/json"
    "X-Zen-ApiKey": apikey

fetchProjects = (callback) ->
  makeRequest {"path":"/api/v1/projects"}, callback

fetchCards = (project, query, callback) ->
  query ?= ''
  makeRequest {"path":"/api/v1/projects/#{project.id}/stories#{query}"}, callback

makeRequest = (options, callback) ->
  _.defaults(options, defaultOptions)

  request = HTTPS.request options, (response) ->
    if response.statusCode >= 300
      callback "Got #{response.statusCode} code from AgileZen while trying to #{options.method} #{options.path}, sorry.", null
      return

    buf = ''

    response.on 'data', (chunk) ->
      buf += chunk

    response.on 'end', ->
      try
        data = JSON.parse(buf)
        callback null, data
      catch err
        console.log err
        callback "Woops, couldn't parse AZ's response!", null

  request.on 'error', (err) ->
    console.log err
    callback "Sorry, I had trouble talking to AZ. Check my logs.", null

  request.end()


module.exports = (robot) ->
  robot.respond /kanban( me)?/i, (msg) ->
    console.log "Checking kanban boards."

    fetchProjects (err, data) ->
      if err
        msg.send err
      else
        if data.items.length > 0
          lines = data.items.map (i) ->
            i.name
          msg.send "Here are your kanban boards: #{lines.join(', ')}"
        else
          msg.send "I don't see any projects. Is my API Key right?"

  robot.respond /what can i pull(?:\s*(?:from|on)\s*)?(.*)?/i, (msg) ->
    matcher = new RegExp(msg.match[1]?.trim() || "services", "i")
    console.log "Finding project: #{matcher}"
    fetchProjects (err, data) ->
      if err
        msg.send err
      else
        project = _.find data.items, (p) ->
          p.name.match matcher
        console.log "Matching project #{project.name}, fetching R2P cards"
        fetchCards project, "?where=ready:true", (err, data) ->
          if err
            msg.send err
          else
            if data.items.length > 0
              msg.send "R2P on '#{project.name}':"
              msg.send "[##{card.id}] #{card.text.replace(/\s+/g, ' ')}" for card in data.items
            else
              msg.send "There's nothing ready to pull. Maybe you could check the Ready column."

  # robot.respond /what are my cards(?:\s*(?:from|on)\s*)?(.*)?/i, (msg) ->
  #   matcher = new RegExp(msg.match[1]?.trim() || "services", "i")
  #   console.log "Finding project: #{matcher}"
  #   fetchProjects (err, data) ->
  #     if err
  #       msg.send err
  #     else
  #       project = _.find data.items, (p) ->
  #         p.name.match matcher
  #       console.log "Matching project #{project.name}, fetching cards for #{msg.message.user.email_address}"
  #       query = "owner:#{msg.message.user.email_address} and not(status:finished)"
  #       fetchCards project, "?where=#{encodeURIComponent query}", (err, data) ->
  #         if err
  #           msg.send err
  #         else
  #           if data.items.length > 0
  #             msg.send "Here are your cards on '#{project.name}':"
  #             msg.send "[##{card.id}] #{card.text.replace(/\s+/g, ' ')}" for card in data.items
  #           else
  #             msg.send "You don't own any cards on '#{project.name}'. Maybe you should get to work!"

  robot.respond /what is blocked(?:\s*(?:from|on)\s*)?(.*)?/i, (msg) ->
    matcher = new RegExp(msg.match[1]?.trim() || "services", "i")
    console.log "Finding project: #{matcher}"
    fetchProjects (err, data) ->
      if err
        msg.send err
      else
        project = _.find data.items, (p) ->
          p.name.match matcher
        console.log "Matching project #{project.name}, fetching blocked cards"
        fetchCards project, "?where=status:blocked", (err, data) ->
          if err
            msg.send err
          else
            if data.items.length > 0
              msg.send "These stories are blocked on '#{project.name}':"
              msg.send "[##{card.id}] #{card.text.replace(/\s+/g, ' ')}" for card in data.items
            else
              msg.send "There's nothing blocked on '#{project.name}'. Good work!"
