# Invoke fearless leader J2 upon mention of his cherished mantra
#
# no excuses - Displays a J2 admonishment, reminding us all that:
#
#              THERE IS NO EXCUSES
#

j2 = [
    "https://s3.amazonaws.com/uploads.hipchat.com/20796/99833/zgjj4h7hi0uypd4/pease2.jpg",
    "https://s3.amazonaws.com/uploads.hipchat.com/20796/99031/4bm2hbpjifwd7rw/jpease_no_excuses_2.jpg"
]

module.exports = (robot) ->
  robot.hear /there is no excuses/i, (msg)->
    msg.send msg.random j2
