Db = require 'db'
Http = require 'http'

exports.onHttp = (request) ->
	# special entrypoint for the Http API: called whenever a request is made to our plugin's inbound URL
	log 'recieved onHTTP from: ' + request.data 
	Db.backend.set 'recievedData', request.data,{'updateNumber': 0, 'lastUpdate': 0}
	plugins = 0
	Db.backend.iterate 'recievedData', () !->
		plugins++
	Db.shared.set 'registeredPlugins', plugins
	request.respond 200, 'Registered successfully'


exports.client_gatherHistory = ->
	Db.backend.iterate 'recievedData' , (group) !->
		Http.post 
			url: 'https://happening.im/x/' + group.key()
			data: '64foNwpEfn3LQrTQC2q5NijPqG92Nv2xYi65gFz6uTJjPJS2stN7MbyNygtvKvNS'
			name: 'historyResult'
	log 'done gathering history'
	Db.shared.set('latestUpdate', new Date()/1000)
	return 0


exports.historyResult = (data) !->
	result = JSON.parse(data)
	log 'recieved history from plugin2: ' + result.groupCode
	if result.groupCode? and result.groupCode isnt ''
		updateNumber = (Db.backend.peek('recievedData', result.groupCode, 'updateNumber')||0)+1
		Db.backend.set('recievedData', result.groupCode, result)
		Db.backend.set('recievedData', result.groupCode, 'updateNumber', updateNumber)
		Db.backend.set('recievedData', result.groupCode, 'lastUpdate', new Date() + '')