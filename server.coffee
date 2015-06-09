Db = require 'db'
Http = require 'http'

exports.onUpgrade = ->
	log '[onUpgrade()] at '+new Date()
	Db.shared.set 'lastDeploy', new Date()+''

exports.onHttp = (request) ->
	# special entrypoint for the Http API: called whenever a request is made to our plugin's inbound URL
	log 'recieved onHTTP from: ' + request.data 
	Db.backend.set 'recievedData', request.data, {'updateNumber': 0, 'lastUpdate': 0}
	plugins = 0
	Db.backend.iterate 'recievedData', () !->
		plugins++
	Db.shared.set 'registeredPlugins', plugins
	request.respond 200, 'Registered successfully'


exports.client_gatherHistory = ->
	log '[gatherHistory()] Starting to request'
	toDo = Db.shared.peek('registeredPlugins')
	Db.shared.set 'updated', 0
	Db.shared.set 'updating', 'true'
	Db.backend.iterate 'recievedData' , (group) !->
		log '  Requesting from: '+group.key()
		Http.post 
			url: 'https://happening.im/x/' + group.key()
			data: '64foNwpEfn3LQrTQC2q5NijPqG92Nv2xYi65gFz6uTJjPJS2stN7MbyNygtvKvNS'
			name: 'historyResult'
	log '[gatherHistory()] Done sending requests'
	Db.shared.set('latestUpdate', new Date()/1000)
	return 0

exports.client_updateStatistics = ->
	recalculateStatistics()

exports.historyResult = (data) !->
	result = JSON.parse(data)
	if result?
		log 'Recieved history from plugin: code='+result.groupCode
		if result.groupCode? and result.groupCode isnt ''
			if result.groupCode is '153664d'
				Db.shared.remove '153664d'
			updateNumber = (Db.backend.peek('recievedData', result.groupCode, 'updateNumber')||0)+1
			Db.backend.remove 'recievedData', result.groupCode
			Db.backend.set('recievedData', result.groupCode, 'history', result)
			Db.backend.remove('recievedData', result.groupCode, 'history', 'groupCode')
			Db.backend.set('recievedData', result.groupCode, 'players', result.players)
			Db.backend.remove('recievedData', result.groupCode, 'history', 'players')
			Db.backend.set('recievedData', result.groupCode, 'updateNumber', updateNumber)
			Db.backend.set('recievedData', result.groupCode, 'lastUpdate', new Date() + '')
			updated = Db.shared.peek('updated')
			Db.shared.incr('updated')
			log 'updated='+updated+', will be='+(updated+1)
			if (updated+1) is Db.shared.peek('registeredPlugins')
				log "Received last result"
				Db.shared.set 'updating', 'false'
				recalculateStatistics()
		else
			log "NO groupcode!"
	else 
		log "JSON parsing failed!"

recalculateStatistics = ->
	totalPlayers = 0
	Db.backend.iterate 'recievedData', (group) !->
		log 'checking group '+group.key()
		groupPlayers = 0
		foundGame = false
		group.iterate 'history', (game) !->
			if !foundGame
				log 'FoundGame: '+game
				foundGame = true
				game.iterate 'teams', (team) !->
					log 'checking team '+team.key()
					team.iterate 'users', (user) !->
						log 'checking user '+user.key()
						groupPlayers++
		totalPlayers += groupPlayers
	Db.shared.set 'statistic', 'totalPlayers', totalPlayers
	Db.shared.set 'statistic', 'averagePlayers', totalPlayers / parseInt(Db.shared.peek('registeredPlugins'))
	Db.shared.set 'lastStatisticUpdate', new Date()/1000
