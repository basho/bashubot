#Description:
# ZenDesk Linker 
# Attempts to naively build a link to a zendesk ticket whenever the
# word ticket or request is followed with a # and a number.
#
#Commands:
#  Ticket/response/review #n - link to Zendesk ticket n
#
#

module.exports = (robot) ->
  robot.hear /(ticket|response|review)[^#]*?#\s*(\d+)/i, (msg)->
  	if msg.message.user.name isnt "Zendesk"
      ticketNum = escape(msg.match[2])
      msg.send "https://basho.zendesk.com/agent/#/tickets/"+ticketNum+"    "+msg.message.user.name
