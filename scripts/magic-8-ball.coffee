# Magic 8 Ball
#
# magic 8 ball - respond to queries with the traditional answers
#                from that one plastic novelty toy thing
#

response = [
  "It is certain",
  "It is decidedly so",
  "Without a doubt",
  "Yes – definitely",
  "You may rely on it",
  "As I see it, yes",
  "Most likely",
  "Outlook good",
  "Yes",
  "Signs point to yes",
  "Reply hazy, try again",
  "Ask again later",
  "Better not tell you now",
  "Cannot predict now",
  "Concentrate and ask again",
  "Don't count on it",
  "My reply is no",
  "My sources say no",
  "Outlook not so good",
  "Very doubtful"
]

module.exports = (robot) ->
  robot.respond /('magic eight ball'|'magic 8 ball'|'m8b'|)( me)? (.*)/i, (msg) ->
    msg.send msg.random response
