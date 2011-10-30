# Interacts with kanban boards you have in AgileZen. Set the AGILEZEN_APIKEY environment variable.
#
# kanban[ me] - Lists your kanban boards by name
# what can i pull[ from|on][ <project>] - finds ready-to-pull cards on your project
# what is blocked[ from|on][ <project>] - finds blocked cards on your project
#

HTTPS = require 'https'
_ = require 'underscore'

class AgileZen
  constructor: (@robot) ->
    @apikey = process.env.AGILEZEN_APIKEY
    @defaultOptions =
      "agent"  : false
      "host"   : "agilezen.com"
      "port"   : 443
      "method" : "GET"
      "headers" :
        "Accept" : "application/json"
        "X-Zen-ApiKey": @apikey
    @setup()

  projects: (callback) ->
    if @robot.brain.data.projects
      callback null, @robot.brain.data.projects
    else
      @request({"path":"/api/v1/projects?with=members"}, null, (err, data) =>
        @robot.brain.data.projects = data.items unless err
        callback err, data
      )

  cards: (project, query, callback) ->
    query = '' unless query?
    @request {"path":"/api/v1/projects/#{project.id}/stories?#{encodeURIComponent query}"}, null, callback

  request: (options, body, callback) ->
    _.defaults(options, @defaultOptions)

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
        catch err
          console.log err
          callback "Woops, couldn't parse AgileZen's response!", null
          return

        callback null, data

    request.on 'error', (err) ->
      console.log err
      callback "Sorry, I had trouble talking to AgileZen. Check my logs.", null

    if body
      request.end body
    else
      request.end()

  boardMatcher: (string) ->
    new RegExp("#{string}(?:\s*(?:from|to)\s*)?(.*)?", "i")

  setup: ->
    @robot.respond /kanban( me)?/i, (msg) =>
      new AgileZen.ListBoards(msg, this)

    @robot.respond @boardMatcher("what can i pull"), (msg) =>
      new AgileZen.ReadyToPull(msg, this)

    @robot.respond @boardMatcher("what is blocked"), (msg) =>
      new AgileZen.Blocked(msg, this)

class AgileZen.Action
  constructor: (@msg, @az) ->
    @process()

  dataCallback: (emptyMessage, cb) ->
    (err, data) =>
      if err
        @msg.send err
      else
        if data.items.length > 0
          cb data.items
        else
          @msg.send emptyMessage

  requestedProject: (callback) ->
    matcher = new RegExp(@msg.match[1]?.trim() || process.env.AGILEZEN_DEFAULT_PROJECT, "i")
    @az.projects @dataCallback("I don't see any projects. Is my API Key right?", (projects) ->
        callback(
          _.find projects, (project) ->
            matcher.test project.name
        )
      )

  isMember: (project) ->
    lastName = _.last @msg.message.user.name.split(/\s+/)
    project.members.some (member) ->
      _.last(member.name.split(/\s+/)) is lastName

  process: ->
    @msg.send "Woops, someone didn't implement this action!"
    # Subclasses implement this

class AgileZen.ListBoards extends AgileZen.Action
  process: ->
    console.log "Checking kanban boards."
    @az.projects(@dataCallback("I don't see any projects. Is my API Key right?", (projects) =>
        projectNames = _.pluck projects.filter((project) => @isMember project), 'name'
        @msg.send "Here are your kanban boards: #{projectNames.join ', '}"
      )
    )

class AgileZen.CardAction extends AgileZen.Action
  formatCards: (cards) ->
    cards.map (card) ->
      "[##{card.id}] #{card.text.replace(/\s+/g, ' ')}"


class AgileZen.ReadyToPull extends AgileZen.CardAction
  process: ->
    @requestedProject (project) =>
      @az.cards project, "where=status:ready",
        @dataCallback "There's nothing to pull on '#{project.name}'. Maybe you could check the Ready column.", (cards) =>
          messages = [ "Ready to pull on '#{project.name}':" ] + formatCards cards
          @msg.send messages...

class AgileZen.Blocked extends AgileZen.CardAction
  process: ->
    @requestedProject (project) =>
      @az.cards project, "where=status:blocked",
        @dataCallback "There's nothing to blocked on '#{project.name}'. Good work!", (cards) =>
          messages = [ "Blocked on '#{project.name}':" ] + formatCards cards
          @msg.send messages...

module.exports = (robot) ->
  new AgileZen(robot)
