_ = require 'underscore'

Controller = require './framework/Controller.coffee'

module.exports = class StatusController extends Controller

	@expose:
		statusSubscribe: (personId, ns, listener) ->
			@realtime.debug 'status', 'statusSubscribe', personId, ns
			key = "#{personId}:#{ns}"
			
			if @listeners(key).length
				if _.has @_statuses, key
					process.nextTick => listener(_.values(@_statuses[key]))
			else 
				@realtime.sendEvent 'statusSubscribe', personId, ns
			
			@on key, listener

			return

		statusUnsubscribe: (personId, ns, listener) ->
			@realtime.debug 'status', 'statusUnsubscribe', personId, ns
			key = "#{personId}:#{ns}"
			@realtime.sendEvent 'statusUnsubscribe', personId, ns
			@removeListener key, listener

			return

	constructor: ->
		super
		@_statuses = {}

		@realtime.on 'disconnect', =>
			# On a disconnect any previously cached statuses are stale
			@_statuses = {}

		@realtime.on 'sioConnect', =>
			# On a new connection any previously cached statuses are stale
			@_statuses = {}
			
			@realtime.onEvent 'status', (statuses) =>
				@realtime.debug 'status', 'got statuses', statuses
				unless statuses.length and statuses[0].personId and statuses[0].ns
					return @realtime.debug 'status', 'invalid status message', statuses
				key = "#{statuses[0].personId}:#{statuses[0].ns}"
				@_statuses[key] ?= {}
				for status in statuses
					@_statuses[key][status.key] = status
				@emit key, statuses
			
			# Re-subscribe to previous statuses on reconnect
			for key of @_events
				[personId, ns] = key.split(':')
				@realtime.sendEvent 'statusSubscribe', personId, ns
