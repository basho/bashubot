#Description:
# plusbang - randomly nag to track time when +1 is seen
#
#Commands:
# +1/+! - 20% chance of nag

module.exports = (robot) ->
  robot.hear /[+][1!]/, (msg) ->
    if Math.random() > 0.8
      mat = msg.message.text.match("(@[^ ]*)")
      mention = ""
      if mat
        mention = mat[0]
      else 
        ticket = msg.robot.brain.get 'last-ticket-mention'
        if ticket
          if ticket.date and ticket.user
            if ticket.date < Date.now() - 600
              mention = "@#{ticket.user}"
      msg.send "#{mention} Remember to track your time!"

