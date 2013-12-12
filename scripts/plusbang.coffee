#description:
# plusbang - randomly nag to track time when +1 is seen
#
#commands:
# +1/+! - 20% chance of nag

module.exports = (robot) ->
  robot.respond /plus(1|one|bang) (date )*check/i, (msg) ->
    ticket = msg.robot.brain.get 'last-ticket-mention'
    if "date" of ticket
        msg.reply "Last ticket link: epoch:#{ticket.date} User:#{ticket.user} Ticket:#{ticket.ticket}"
        if Date.now() - ticket.date < 600000
            msg.send "#{Date.now() - ticket.date} ms ago"
        else
            msg.send "#{Date.now() - ticket.date} ms ago (too long for nagging)"
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
            if Date.now() - ticket.date < 600000
              mention = "@#{ticket.user}"
          if mention != "@all"
            msg.send "#{mention} Remember to track your time!"

