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
  "Yeahhh, I'm gonna have to go ahead and disagree with you on that one.",
  "Yeahhh, I'm gonna have to go ahead and ask you to come in on Saturday."
  ]

mug = (msg) ->
  lumberg(msg, "Hey #{msg.message.user.name}, #{msg.random greetings}")

lumberg = (msg, say) ->
  unless msg.message.user.name.match /bashobot/i
    msg.send msg.random lumbergs if Math.random() > 0.8
    msg.send say if say

module.exports = (robot) ->
  robot.respond /mug(\s+me)?/i, mug

  robot.hear /^\*.*mug.*\*$/i, (msg) ->
    lumberg(msg, "*sips* *raises mug toward #{msg.message.user.name}*")

  robot.hear /lumberg/i, (msg) ->
    lumberg(msg, "Hey #{msg.message.user.name}, #{msg.random greetings} #{msg.random yeahs}")

  robot.enter mug
