# Description:
#   Display a "deal with it" gif
#
# Commands:
#   deal with it - display a "deal with it" gif
#

deal = [
  "http://i.imgur.com/452Pe.gif",
  "http://i.imgur.com/Wj3Do.gif",
  "http://i.imgur.com/3PWHn.gif",
  "http://i.imgur.com/To8mu.gif",
  "http://i.imgur.com/kRI0y.gif",
  "http://i.imgur.com/ZTHtv.gif",
  "http://i.imgur.com/dSof9.gif",
  "http://i.imgur.com/GxYr5.gif",
  "http://i.imgur.com/UHww5.gif",
  "http://i.imgur.com/qp0eh.gif",
  "http://i.imgur.com/JnhJU.png",
  "http://joecaswell.info/deal.gif",
  "http://i.imgur.com/olWiANT.jpg"
]

module.exports = (robot) ->
  robot.hear /deal with it/i, (msg)->
    msg.send msg.random deal
