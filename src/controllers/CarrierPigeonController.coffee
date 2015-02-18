_ = require 'underscore'
{EventEmitter} = require 'events'

Controller = require './framework/Controller.coffee'

module.exports = class CarrierPigeonController extends Controller

	# @expose:
	# 	subscribe: (event, listener) ->
	# 		@realtime.debug 'status', 'statusSubscribe', personId, ns
	# 		key = "#{personId}:#{ns}"
			
	# 		if @_listeners(key).length
	# 			process.nextTick => listener(_.values(@_statuses[key]))
	# 		else 
	# 			@realtime.sendEvent 'subscribe', event
			
	# 		@_events.on event, listener

	# 		return

	# 	unsubscribe: (event, listener) ->
	# 		@realtime.debug 'status', 'statusUnsubscribe', personId, ns
	# 		key = "#{personId}:#{ns}"
	# 		@realtime.sendEvent 'unsubscribe', personId, ns
	# 		@_events.removeListener key, listener

	# 		return

	# constructor: ->
	# 	super
	# 	@_events = new EventEmitter()

	# 	@realtime.on 'sioConnect', =>
	# 		# @realtime.
	# 		@realtime.onEvent 'status', (statuses) =>
	# 			@realtime.debug 'status', 'got statuses', statuses
	# 			unless statuses.length and statuses[0].personId and statuses[0].ns
	# 				return @realtime.debug 'status', 'invalid status message', statuses
	# 			key = "#{statuses[0].personId}:#{statuses[0].ns}"
	# 			@_statuses[key] ?= {}
	# 			for status in statuses
	# 				@_statuses[key][status.key] = status
	# 			@emit key, statuses
			
	# 		for key of @_events
	# 			[personId, ns] = key.split(':')
	# 			@realtime.emit 'statusSubscribe', personId, ns
