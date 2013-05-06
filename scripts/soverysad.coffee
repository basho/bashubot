# Display a sad MLP gif
#
# so very sad - Displays a sad MLP gif
#
#

pony = [
  "http://i.imgur.com/fmFGU.gif",
  "http://i.imgur.com/WwfYK.jpg",
  "http://i.imgur.com/EwvR1.gif",
  "http://i.imgur.com/IjuCj.jpg",
  "http://i.imgur.com/BaILN.gif",
  "http://i.imgur.com/aFYtC.jpg",
  "http://i.imgur.com/DzuKm.gif",
  "http://i.imgur.com/7h1Sq.jpg",
  "http://i.imgur.com/t26on.gif",
  "http://i.imgur.com/KyZMh.jpg",
  "http://i.imgur.com/8a2qC.gif",
  "http://i.imgur.com/gvVLR.jpg",
  "http://i.imgur.com/j09Sw.jpg",
  "http://i.imgur.com/qZPbw.jpg",
  "http://i.imgur.com/cDqRl9k.jpg"
]

module.exports = (robot) ->
  robot.hear /so very sad/i, (msg)->
    msg.send msg.random pony
