# crypto = require 'crypto'

increment = Math.floor Math.random() * 32767

exports.generate = ->
  # time + pid + increment + random
  if increment++ >= 32767 then increment = 0
  uuid = ""
  uuid += Math.round(new Date().getTime() / 1000.0).toString(16)

  # this is for when this gets executed in the browser
  process.pid ?= Math.floor(Math.random()*99999)

  inc = process.pid.toString(16)+increment.toString(16)
  while inc.length < 12 then inc = "0"+inc
  uuid += inc.substr(0,12)
  uuid += Math.floor((1 + Math.random()) * 0x10000).toString(16).substring(1)

  return uuid.substr(0,24)

