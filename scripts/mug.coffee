lumbergs = [
  "http://www.mamapop.com/wp-content/uploads/2010/06/bill-lumbergh-office-space1.jpg",
  "http://static8.businessinsider.com/image/437a6c79736bca485dbe6e00/office-space-lumberg.jpg",
  "http://ambroselerma.files.wordpress.com/2011/06/bill-lumbergh.jpg"
  ]

greetings = [
  "what\'s happening?",
  "how\'s it going?",
  "what\'s up?"
  ]

yeahs = [
  "Yeahhh, did you get the memo? See, there are these new cover sheets for your TPS report.",
  "Yeahhh, I'm gonna have to go ahead and disagree with you.",
  "Yeahhh, I'm gonna have to go ahead and ask you to come in on Saturday."
  ]

mug = (msg) ->
  unless msg.message.user.name == msg.robot.name
    msg.send "Hey #{msg.message.user.name}, #{msg.random greetings}"
    lumberg(msg)

lumberg = (msg) ->
  unless msg.message.user.name == 'bashobot'
    if Math.random() > 0.8
      msg.send msg.random(lumbergs)

module.exports = (robot) ->
  robot.respond /mug( me)?/i, (msg) ->
    mug msg

  robot.hear /^\*.*mug.*\*$/i, (msg) ->
    lumberg(msg)
    msg.send "*sips* *raises mug toward #{msg.message.user.name}*"

  robot.hear /lumberg/i, (msg) ->
    lumberg(msg)
    msg.send("Hey #{msg.message.user.name}, #{msg.random greetings} #{msg.random yeahs}")

  robot.hear /has entered the room/i, (msg) ->
    mug msg
