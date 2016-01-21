# Description
#   Collection point for mildly humorous memes and inside jokes in chat form
#
# Dependencies
#
# Configuration
#
# Commands
#
#

alottaimg = [ "https://s3.amazonaws.com/uploads.hipchat.com/20796/153248/759HTqDHz5pX67e/ALOT.png",
              "https://s3.amazonaws.com/uploads.hipchat.com/20796/153248/BAkerNjmyWC11KL/ALOT2.png",
              "https://s3.amazonaws.com/uploads.hipchat.com/20796/153248/iFpc5H1CzTvL2ds/92361_orig.png",
              "https://s3.amazonaws.com/uploads.hipchat.com/20796/153248/GQueULCcGyngBjz/ALOT4.png"
]


module.exports = (robot) ->
  robot.hear /@here/i, (msg)->
    if Math.random() < 0.1
        if Math.random() < 0.1
            msg.send "https://media.giphy.com/media/sW6P26sp3HFvy/giphy.gif"
        else
            msg.send "Bueller ... Bueller?"
  robot.hear /alot/i, (msg) ->
    msg.send msg.random alottaimg
    


