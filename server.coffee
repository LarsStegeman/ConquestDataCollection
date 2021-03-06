Db = require 'db'
Http = require 'http'
Timer = require 'timer'

Config = {
		updateCompletionDelay: 500				# milliseconds between updating the doneCount for the client while gathering data
		gatheringTimeout: 120*1000				# timeout of the gathering (time after receiving last result) non-updated plugins will be marked as inactive after this
		gatherRequestsPerSecond: 100			# how many HTTP data gather requests will be send each second
		startTimestamp: 1434405600.0			# Timestamp which is used as day 0 for the statistics
	}

eventsPerDay = {}
groupsPerGroupSize = {}

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
	log '[gatherHistory()] Starting to request'
	Timer.cancel 'gatheringTimeout', {}
	Timer.cancel 'updateCompletion', {}
	Db.shared.set 'doneCount', 0
	Db.shared.set 'lastDoneCount', 0
	Db.shared.set 'updating', 'true'
	Db.shared.set "doneSendingRequests", 'no'
	Db.backend.set 'pluginInfoCopy', Db.backend.peek('pluginInfo')
	currentRequest = 0
	Db.backend.iterate 'pluginInfo' , (group) !->
		if group.peek('active') == 'true'
			Db.backend.set 'pluginInfoCopy', group.key(), Db.backend.peek('pluginInfo', group.key())
			Db.backend.set 'pluginInfoCopy', group.key(), 'upToDate', 'false'
			currentRequest++
	Db.shared.set 'currentRequest', currentRequest
	Timer.set 0, 'doGatherStep', {}
	Timer.set Config.gatheringTimeout, 'gatheringTimeout', {}
	Timer.set Config.updateCompletionDelay, 'updateCompletion', {}
	return 0

exports.doGatherStep = (args) ->
	current = 0
	currentRequest = Db.shared.peek('currentRequest')
	Db.backend.iterate 'pluginInfoCopy' , (group) !->
		if current >= currentRequest and current < (currentRequest+Config.gatherRequestsPerSecond)
			log '  Requesting from: '+group.key()
			Http.post
				url: 'https://happening.im/x/' + group.key()
				data: '64foNwpEfn3LQrTQC2q5NijPqG92Nv2xYi65gFz6uTJjPJS2stN7MbyNygtvKvNS'
				name: 'historyResult'
		current++
	currentRequest = currentRequest-Config.gatherRequestsPerSecond
	Db.shared.set 'currentRequest', currentRequest
	if currentRequest > 0
		Timer.set 1000, 'doGatherStep', {}
	else
		Db.shared.set "doneSendingRequests", 'yes'
		log '[doGatherStep()] Done sending requests'
	return 0


# Client call for updating statistics
exports.client_updateStatistics = ->
	recalculateStatistics()

# Update the donecount to be shown to the client, finishes the gathering if done
exports.updateCompletion = (args) ->
	done = true
	doneCount = 0
	Db.backend.iterate 'pluginInfoCopy', (group) !->
		if Db.backend.peek('pluginInfoCopy', group.key(), 'upToDate') is 'false'
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
	Db.backend.remove 'pluginInfoCopy'
	recalculateStatistics()

exports.historyResult = (data) !->
	if data? and data isnt ''
		if data.indexOf("<html><head><title>404 no such group app</title></head>") <= -1
			result = JSON.parse(data)
			if result?
				log '[historyResult()] Recieved history from plugin: code='+result.groupCode
				if result.groupCode? and result.groupCode isnt ''
					Db.backend.remove 'recievedData', result.groupCode
					Db.backend.set('recievedData', result.groupCode, 'history', result)
					Db.backend.remove('recievedData', result.groupCode, 'history', 'groupCode')
					Db.backend.set('recievedData', result.groupCode, 'players', result.players)
					Db.backend.remove('recievedData', result.groupCode, 'history', 'players')
					if Db.backend.peek('pluginInfoCopy', result.groupCode, 'upToDate') is 'false'
						Db.backend.set 'pluginInfoCopy', result.groupCode, 'upToDate', 'true'
						Db.backend.incr 'pluginInfo', result.groupCode, 'updateNumber'
				else
					log "[historyResult()] NO groupcode!"
			else 
				log "[historyResult()] JSON parsing failed!"
		else
			log "[historyResult()] Group app not found!"
	else
		log '[historyResult()] Data not available!'

# Triggers when not all plugins responded in time, sets plugins to inactive
exports.gatheringTimeout = (args) ->
	#Db.backend.iterate 'pluginInfo', (group) !-> TODO reenable
	#	if Db.backend.peek('pluginInfo', group.key(), 'upToDate') is 'false'
	#		Db.backend.set 'pluginInfo', group.key(), 'active', 'false'
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
	totalEvents = 0
	totalCaptures = 0
	totalNeutralizes = 0
	totalGames = 0
	endedSetup = 0
	endedRunning = 0
	endedProper = 0
	inactive = 0
	beacons = 0
	validBounds = 0
	boundsTotalX = 0
	boundsTotalY = 0
	Db.shared.remove('eventsPerDay')
	#allLatLng = '' # lat/lng string
	eventsPerDay = {}
	groupsPerGroupSize = {}
	# THE BIG LOOP
	Db.backend.iterate 'recievedData', (group) !->
		players = group.peek('players')
		if players?
			players = parseInt(players)
			totalPlayers += players
			playersString = players + ''
			if groupsPerGroupSize[playersString]?
				groupsPerGroupSize[playersString] = groupsPerGroupSize[playersString]+1
			else
				groupsPerGroupSize[playersString] = 1
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
				else if gameState == 2
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
						timestampToDay(gameEvent.peek('timestamp'))
					else if type == 'captureAll'
						totalCaptures++ 
						timestampToDay(gameEvent.peek('timestamp'))
			# Beacon statistics
			game.iterate 'game', 'beacons', (beacon) !->
				if gameState == 1 or gameState == 2
					beacons++
				#allLatLng += beacon.peek('location', 'lat') + ',' + beacon.peek('location', 'lng') + ';' # lat/lng string
			if gameState == 1 or gameState == 2
				lat1 = game.peek('game', 'bounds', 'one', 'lat')
				lat2 = game.peek('game', 'bounds', 'two', 'lat')
				lng1 = game.peek('game', 'bounds', 'one', 'lng')
				lng2 = game.peek('game', 'bounds', 'two', 'lng')
				if lat1? and lat2? and lng1? and lng2?
					validBounds++
					distY = distance(lat1, lng1, lat2, lng1)
					if distY? and distY != NaN
						boundsTotalY += distY
					distX = distance(lat1, lng1, lat1, lng2)
					if distX? and distX != NaN
						boundsTotalX += distX

	
	# Beacon statistics
	Db.shared.set('beacons', beacons)
	Db.shared.set('validBounds', validBounds)
	Db.shared.set('boundsX', boundsTotalX/validBounds)
	Db.shared.set('boundsY', boundsTotalY/validBounds)
	#Db.shared.set 'allLatLng', allLatLng # lat/lng string

	# General statistics
	Db.shared.set('totalPlayers', totalPlayers)
	Db.shared.set('averagePlayers', totalPlayers / parseInt(Db.shared.peek('registeredPlugins')))
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

	# Update number of events per day
	for day, number of eventsPerDay
		if day? and number? and day >= 0 
			Db.shared.set('eventsPerDay', day, number)
	# Update groups per groupsize
	for groupsize, count of groupsPerGroupSize
		if groupsize? and count?
			Db.shared.set('groupsPerGroupSize', groupsize, count)



	# Update to current time, will only update if above went okey
	Db.shared.set 'lastStatisticUpdate', new Date()/1000
	Db.shared.set('updatingStatistics', 'false')

# Add one point to the captures for the day of the timestamp
timestampToDay = (timestamp) ->
	if timestamp?
		timestamp = timestamp - Config.startTimestamp
		days = Math.floor(Math.round(timestamp) / 86400) + ''
		events = eventsPerDay[days]
		if events isnt undefined and events? and events isnt null
			eventsPerDay[days] = events+1
		else
			eventsPerDay[days] = 1
	return 0

# Calculate distance
distance = (inputLat1, inputLng1, inputLat2, inputLng2) ->
	r = 6378137
	rad = 3.141592653589793 / 180
	lat1 = inputLat1 * rad
	lat2 = inputLat2 * rad
	a = Math.sin(lat1) * Math.sin(lat2) + Math.cos(lat1) * Math.cos(lat2) * Math.cos((inputLng2 - inputLng1) * rad);
	return r * Math.acos(Math.min(a, 1));