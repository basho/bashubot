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
    if @robot.brain.data?.projects?
      callback null, {"items": @robot.brain.data.projects}
    else
      @request({"path":"/api/v1/projects?with=members"}, null, (err, data) =>
        console.log "Got some projects."
        @robot.brain.data.projects = data.items unless err?
        callback err, data
      )

  cards: (project, query, callback) ->
    query = '' unless query?
    @request {"path":"/api/v1/projects/#{project.id}/stories?#{query}"}, null, callback

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
    new RegExp("#{string}\\s*(?:from|on)?\\s*(.*)?", "i")

  setup: ->
    @robot.respond /kanban( me)?/i, (msg) =>
      new AgileZen.ListBoards(msg, this)

    @robot.respond @boardMatcher("what can i pull"), (msg) =>
      new AgileZen.ReadyToPull(msg, this)

    @robot.respond @boardMatcher("what are my (?:cards|stories)"), (msg) =>
      new AgileZen.Owned(msg, this)

    @robot.respond @boardMatcher("what is blocked"), (msg) =>
      new AgileZen.Blocked(msg, this)

    @robot.respond /(clear|refresh)\s+kanban(s)?/i, (msg) =>
      delete @robot.brain.data.projects
      msg.send "Ok, I cleared the kanban boards."

class AgileZen.Action
  constructor: (@msg, @az) ->
    try
      @process()
    catch err
      @msg.send "Woops, I had an error: #{err.message}\n#{err.stack}"

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
    console.log "Matching project '#{@msg.match[1]}'"
    matcher = new RegExp(@msg.match[1]?.trim() || process.env.AGILEZEN_DEFAULT_PROJECT, "i")
    @az.projects @dataCallback("I don't see any projects. Is my API Key right?", (projects) =>
        foundProject = _.find projects, (project) ->
          project? && matcher.test project.name
        if foundProject?
          callback(foundProject)
        else
          @msg.send "Woops, I can't find any project that matches #{matcher}."
      )

  isMember: (project) ->
    @findMember(project)?

  findMember: (project) ->
    lastName = new RegExp(_.last(@msg.message.user.name.split(/\s+/)), "i")
    _.find project.members, (member) ->
      lastName.test member.name

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
  sendCards: (header, cards) ->
    messages = [header, @formatCards(cards)...]
    @msg.send messages...

  formatCards: (cards) ->
    cards.map (card) ->
      "[##{card.id}] #{card.text.replace(/\s+/g, ' ')}"

class AgileZen.ReadyToPull extends AgileZen.CardAction
  process: ->
    @requestedProject (project) =>
      @az.cards(project, "where=ready:true",
        @dataCallback("There's nothing to pull on '#{project.name}'. Maybe you could check the Ready column.", (cards) =>
          @sendCards("Ready to pull on '#{project.name}':", cards)
        )
      )

class AgileZen.Owned extends AgileZen.CardAction
  process: ->
    @requestedProject (project) =>
      requestor = @findMember(project)
      unless requestor?
        @msg.send "Sorry, you don't seem to be a member of '#{project.name}'."
        return
      @az.cards(project, "where=owner:#{requestor.id}+and+not(status:finished)",
        @dataCallback("You don't have any unfinished stories on '#{project.name}'. Maybe you could check the Ready column.",
          (cards) => @sendCards("Your stories on '#{project.name}':", cards)
        )
      )

class AgileZen.Blocked extends AgileZen.CardAction
  process: ->
    @requestedProject (project) =>
      @az.cards(project, "where=blocked:true",
        @dataCallback("There's nothing blocked on '#{project.name}'. Good work!",
          (cards) => @sendCards("Blocked on '#{project.name}'", cards)
        )
      )

module.exports = (robot) ->
  new AgileZen(robot)
