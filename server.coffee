Db = require 'db'
Http = require 'http'
Timer = require 'timer'

exports.onUpgrade = ->
	log '[onUpgrade()] at '+new Date()
	Db.shared.set 'lastDeploy', new Date()+''

exports.onHttp = (request) ->
	# special entrypoint for the Http API: called whenever a request is made to our plugin's inbound URL
	log '[onHTTP()] Plugin ' + request.data + ' registered'
	Db.backend.set 'pluginInfo', request.data, {'updateNumber': 0, 'active': 'true', 'upToDate': 'true'}
	request.respond 200, 'Registered successfully'
	updateNumberOfPlugins()
	return 0

exports.client_gatherHistory = ->
	Db.shared.set 'doneCount', 0
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
	Timer.set 30*1000, 'checkRegistered', {}
	return 0

exports.client_updateStatistics = ->
	recalculateStatistics()

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
					checkUpdating()
			else
				log "[historyResult()] NO groupcode!"
		else 
			log "[historyResult()] JSON parsing failed!"
	else
		log '[historyResult()] Data not available'

exports.checkRegistered = (args) ->
	Db.backend.iterate 'pluginInfo', (group) !->
		if Db.backend.peek('pluginInfo', group.key(), 'upToDate') is 'false'
			Db.backend.set 'pluginInfo', group.key(), 'active', 'false'

checkUpdating = ->
	done = true
	doneCount = 0
	Db.backend.iterate 'pluginInfo', (group) !->
		if Db.backend.peek('pluginInfo', group.key(), 'upToDate') is 'false' and Db.backend.peek('pluginInfo', 'active') isnt 'false'
			done = false
		else
			doneCount++
	Db.shared.set 'doneCount', doneCount
	if done
		Db.shared.set('latestUpdate', new Date()/1000)
		Db.shared.set 'updating', 'false'
		Timer.cancel 'checkRegistered', {}
		recalculateStatistics()


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
	# THE BIG LOOP
	Db.backend.iterate 'recievedData', (group) !->
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
	# Team statistics
	Db.shared.set('totalNeutralizes', totalNeutralizes)
	# Eventlist statistics
	Db.shared.set('totalGames', totalGames)
	Db.shared.set('totalCaptures', totalCaptures)
	Db.shared.set('totalEvents', totalEvents)


	# Update to current time, will only update if above went okey
	Db.shared.set 'lastStatisticUpdate', new Date()/1000
	Db.shared.set('updatingStatistics', 'false')

