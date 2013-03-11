# ZenDesk Linker 
#
# Attempts to naively build a link to a zendesk ticket whenever the
# word ticket or request is followed with a # and a number.
#
#

module.exports = (robot) ->
  robot.hear /(ticket|response|review)[^#]*?#\s*(\d+)/i, (msg)->
    ticketNum = escape(msg.match[2])
    msg.send "https://basho.zendesk.com/agent/#/tickets/"+ticketNum
