Db = require 'db'
Http = require 'http'
Timer = require 'timer'

Config = {
		updateCompletionDelay: 500				# milliseconds between updating the doneCount for the client while gathering data
		gatheringTimeout: 120*1000				# timeout of the gathering (time after receiving last result) non-updated plugins will be marked as inactive after this
	}

# Upgrade of the plugin
exports.onUpgrade = ->
	log '[onUpgrade()] at '+new Date()
	Db.shared.set 'lastDeploy', new Date()+''

# Call from Conquest plugin for registering itself to this Data plugin
exports.onHttp = (request) ->
	# special entrypoint for the Http API: called whenever a request is made to our plugin's inbound URL
	log '[onHTTP()] Plugin ' + request.data + ' registered'
	Db.backend.set 'pluginInfo', request.data, {'updateNumber': 0, 'active': 'true', 'upToDate': 'true'}
	request.respond 200, 'Registered successfully'
	updateNumberOfPlugins()
	return 0

# Client call to update databases
exports.client_gatherHistory = ->
	Timer.cancel 'gatheringTimeout', {}
	Timer.cancel 'updateCompletion', {}
	Db.shared.set 'doneCount', 0
	Db.shared.set 'lastDoneCount', 0
	Db.shared.set 'updating', 'true'
	log '[gatherHistory()] Starting to request'
	Db.backend.iterate 'pluginInfo' , (group) !->
		Db.backend.set 'pluginInfo', group.key(), 'upToDate', 'false'
		if Db.backend.peek('pluginInfo', group.key(), 'active') is 'true'
			log '  Requesting from: '+group.key()
			Http.post 
				url: 'https://happening.im/x/' + group.key()
				data: '64foNwpEfn3LQrTQC2q5NijPqG92Nv2xYi65gFz6uTJjPJS2stN7MbyNygtvKvNS'
				name: 'historyResult'
	log '[gatherHistory()] Done sending requests'
	Timer.set Config.gatheringTimeout, 'gatheringTimeout', {}
	Timer.set Config.updateCompletionDelay, 'updateCompletion', {}
	return 0

# Client call for updating statistics
exports.client_updateStatistics = ->
	recalculateStatistics()

# Update the donecount to be shown to the client, finishes the gathering if done
exports.updateCompletion = (args) ->
	done = true
	doneCount = 0
	Db.backend.iterate 'pluginInfo', (group) !->
		if Db.backend.peek('pluginInfo', group.key(), 'active') isnt 'false'
			if Db.backend.peek('pluginInfo', group.key(), 'upToDate') is 'false'
				done = false
			else
				doneCount++
	Db.shared.set 'doneCount', doneCount
	if done
		finishGathering()
	else
		if Db.shared.peek('lastDoneCount') != doneCount
			Timer.cancel 'gatheringTimeout', {}
			Timer.set Config.gatheringTimeout, 'gatheringTimeout', {}
		Timer.set Config.updateCompletionDelay, 'updateCompletion', {}
		Db.shared.set 'lastDoneCount', doneCount

# End the gathring, trigger statistics update
finishGathering = ->
	Timer.cancel 'gatheringTimeout', {}
	Timer.cancel 'updateCompletion', {}
	Db.shared.set('latestUpdate', new Date()/1000)
	Db.shared.set 'updating', 'false'
	recalculateStatistics()

# A callback result from a Conquest plugin after asked for database
exports.historyResult = (data) !->
	if data? and data isnt ''
		result = JSON.parse(data)
		if result?
			log '[historyResult()] Recieved history from plugin: code='+result.groupCode
			if result.groupCode? and result.groupCode isnt ''
				Db.backend.remove 'recievedData', result.groupCode
				Db.backend.set('recievedData', result.groupCode, 'history', result)
				Db.backend.remove('recievedData', result.groupCode, 'history', 'groupCode')
				Db.backend.set('recievedData', result.groupCode, 'players', result.players)
				Db.backend.remove('recievedData', result.groupCode, 'history', 'players')
				if Db.backend.peek('pluginInfo', result.groupCode, 'upToDate') is 'false'
					Db.backend.set 'pluginInfo', result.groupCode, 'upToDate', 'true'
					Db.backend.incr 'pluginInfo', result.groupCode, 'updateNumber'
			else
				log "[historyResult()] NO groupcode!"
		else 
			log "[historyResult()] JSON parsing failed!"
	else
		log '[historyResult()] Data not available'

# Triggers when not all plugins responded in time, sets plugins to inactive
exports.gatheringTimeout = (args) ->
	Db.backend.iterate 'pluginInfo', (group) !->
		if Db.backend.peek('pluginInfo', group.key(), 'upToDate') is 'false'
			Db.backend.set 'pluginInfo', group.key(), 'active', 'false'
	finishGathering()

# Update number of plugins registered
updateNumberOfPlugins = ->
	numberOfRegisters = 0
	Db.backend.iterate 'pluginInfo', () !->
		numberOfRegisters++
	Db.shared.set 'registeredPlugins', numberOfRegisters

# Statistic calculations
recalculateStatistics = ->
	log "[recalculateStatistics()]"
	Db.shared.set('updatingStatistics', 'true')

	# Set general numbers
	totalPlayers = 0
	Db.backend.iterate 'recievedData', (group) !->
		totalPlayers += parseInt(group.peek('players'))||0
	Db.shared.set 'totalPlayers', totalPlayers
	Db.shared.set 'averagePlayers', totalPlayers / parseInt(Db.shared.peek('registeredPlugins'))

	# Initialize statistics
	totalEvents = 0
	totalCaptures = 0
	totalNeutralizes = 0
	totalGames = 0
	endedSetup = 0
	endedRunning = 0
	endedProper = 0
	inactive = 0
	# THE BIG LOOP
	Db.backend.iterate 'recievedData', (group) !->
		if Db.backend.peek('pluginInfo', group.key(), 'active') is 'false'
			inactive++
		group.iterate 'history', (game) !->
			# Game statistics
			totalGames++
			gameState = game.peek('gameState')
			if gameState?
				if gameState == 0
					endedSetup++
				else if gameState == 1
					endedRunning++
				else if gameState ==2
					endedProper++
			# Team statistics
			game.iterate 'game', 'teams', (team) !->
				neutralized = team.peek('neutralized')
				if neutralized?
					totalNeutralizes += neutralized
			# Eventlist statistics
			game.iterate 'game', 'eventlist', (gameEvent) !->
				totalEvents++
				if gameEvent.key() isnt 'maxId' 
					type = gameEvent.peek('type')
					if type == 'capture'
						totalCaptures++
					else if type == 'captureAll'
						totalCaptures++ 
	# Game statistics
	Db.shared.set('gamesSetup', endedSetup)
	Db.shared.set('gamesRunning', endedRunning)
	Db.shared.set('gamesEnded', endedProper)
	Db.shared.set('removedPlugins', inactive)
	# Team statistics
	Db.shared.set('totalNeutralizes', totalNeutralizes)
	# Eventlist statistics
	Db.shared.set('totalGames', totalGames)
	Db.shared.set('totalCaptures', totalCaptures)
	Db.shared.set('totalEvents', totalEvents)


	# Update to current time, will only update if above went okey
	Db.shared.set 'lastStatisticUpdate', new Date()/1000
	Db.shared.set('updatingStatistics', 'false')

