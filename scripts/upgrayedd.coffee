#Description:
# Upgrayedd
#
#Commands:
# hubot upgrayedd - Which he spells thusly, with two D's, as he says, "for a double dose of this pimping".
# upgrade

upgrayedds = [
  "http://codinghorror.typepad.com/.a/6a0120a85dcdae970b01287770a775970c-pi",
  "http://b.vimeocdn.com/ps/824/82420_300.jpg"
]

module.exports = (robot) ->
  robot.hear /.*(upgrade).*/i, (msg) ->
    r = Math.random()
    if r <= 01
      msg.send "Did you mean Upgrayedd?"
      msg.send  msg.random upgrayedds

  robot.respond /upgrayedd/i, (msg) ->
    msg.send  msg.random upgrayedds
