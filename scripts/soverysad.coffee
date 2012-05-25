# Display a sad MLP gif
#
# so very sad - Displays a sad MLP gif
#
#

pony = [
  "http://i.imgur.com/fmFGU.gif",
  "http://i.imgur.com/EwvR1.gif",
  "http://i.imgur.com/BaILN.gif",
  "http://i.imgur.com/DzuKm.gif",
  "http://i.imgur.com/t26on.gif",
  "http://i.imgur.com/8a2qC.gif"
]

module.exports = (robot) ->
  robot.hear /so very sad/i, (msg)->
    msg.send msg.random pony
