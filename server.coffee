Db = require 'db'
Http = require 'http'
Timer = require 'timer'

exports.onUpgrade = ->
	log '[onUpgrade()] at '+new Date()
	Db.shared.set 'lastDeploy', new Date()+''




exports.onHttp = (request) ->
	# special entrypoint for the Http API: called whenever a request is made to our plugin's inbound URL
	log '[onHTTP()] Plugin ' + request.data + ' registered'
	Db.shared.set 'registered', request.data, {'updateNumber': 0, 'active': 'true', 'upToDate': 'true'}
	request.respond 200, 'Registered successfully'
	return 0


exports.client_gatherHistory = ->
	Db.shared.set 'doneCount', 0
	Db.shared.set 'updating', 'true'
	log '[gatherHistory()] Starting to request'
	Db.shared.iterate 'registered' , (group) !->
		Db.shared.set 'registered', group.key(), 'upToDate', 'false'
		if Db.shared.peek('registered', group.key(), 'active') is 'true'
			log '  Requesting from: '+group.key()
			Http.post 
				url: 'https://happening.im/x/' + group.key()
				data: '64foNwpEfn3LQrTQC2q5NijPqG92Nv2xYi65gFz6uTJjPJS2stN7MbyNygtvKvNS'
				name: 'historyResult'
	log '[gatherHistory()] Done sending requests'
	Db.shared.set('latestUpdate', new Date()/1000)
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
				if Db.shared.peek('registered', result.groupCode, 'upToDate') is 'false'
					Db.shared.set 'registered', result.groupCode, 'upToDate', 'true'
					Db.shared.incr 'registered', result.groupCode, 'updateNumber'
					checkUpdating()
			else
				log "[historyResult()] NO groupcode!"
		else 
			log "[historyResult()] JSON parsing failed!"
	else
		log '[historyResult()] Data not available'

exports.checkRegistered = (args) ->
	Db.shared.iterate 'registered', (group) !->
		if Db.shared.peek('registered', group.key(), 'upToDate') is 'false'
			Db.shared.set 'registered', group.key(), 'active', 'false'

checkUpdating = ->
	done = true
	doneCount = 0
	Db.shared.iterate 'registered', (group) !->
		if Db.shared.peek('registered', group.key(), 'upToDate') is 'false' and Db.shared.peek('registered', 'active') isnt 'false'
			done = false
		else
			doneCount++
	Db.shared.set 'doneCount', doneCount
	if done
		Db.shared.set 'updating', 'false'
		recalculateStatistics()

recalculateStatistics = ->
	log "[recalculateStatistics()]"
	totalPlayers = 0
	Db.backend.iterate 'recievedData', (group) !->
		totalPlayers += parseInt(group.peek('players'))||0
	Db.shared.set 'statistic', 'totalPlayers', totalPlayers
	registerCount = 0
	Db.shared.iterate 'registered', (group) !->
		registerCount++
	Db.shared.set 'statistic', 'averagePlayers', totalPlayers / registerCount
	Db.shared.set 'lastStatisticUpdate', new Date()/1000