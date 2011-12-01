# Upgrayedd
#
# upgrayedd - Which he spells thusly, with two D's, as he says, "for a double dose of this pimping".
#

upgrayedds = [
  "http://dcs905.ca/dubcomm/wp-content/uploads/2010/03/upgrayedd-575x377.jpg",
  "http://b.vimeocdn.com/ps/824/82420_300.jpg"
]

module.exports = (robot) ->
  robot.hear /.*(upgrade).*/i, (msg) ->
    msg.send "Did you mean Upgrayedd?"
    msg.send  msg.random upgrayedds

  robot.respond /upgrayedd/i, (msg) ->
    msg.send  msg.random upgrayedds