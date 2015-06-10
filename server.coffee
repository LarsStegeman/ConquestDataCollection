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
	Timer.set 1000*30, 'checkRegistered', {}
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
		recalculateStatistics()

updateNumberOfPlugins = ->
	numberOfRegisters = 0
	Db.backend.iterate 'pluginInfo', () !->
		numberOfRegisters++
	Db.shared.set 'registeredPlugins', numberOfRegisters

# Statistic calculations
recalculateStatistics = ->
	log "[recalculateStatistics()]"
	totalPlayers = 0
	Db.backend.iterate 'recievedData', (group) !->
		totalPlayers += parseInt(group.peek('players'))||0
	Db.shared.set 'statistic', 'totalPlayers', totalPlayers
	Db.shared.set 'statistic', 'averagePlayers', totalPlayers / parseInt(Db.shared.peek('registeredPlugins'))
	Db.shared.set 'lastStatisticUpdate', new Date()/1000