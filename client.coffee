Db = require 'db'
Dom = require 'dom'
Modal = require 'modal'
Obs = require 'obs'
Plugin = require 'plugin'
Server = require 'server'
Ui = require 'ui'
Time = require 'time'


exports.render = ->
	log "FULL RENDER"
	numberOfRegisters = (Db.shared.count('registered').get() || 0 )
	Dom.text 'There are ' + numberOfRegisters + ' plugins registered'
	Dom.br()

	if Db.shared.get('updating')? and Db.shared.get('updating') == 'true'
		counter = Obs.create(0)
		Db.shared.iterate 'registered', (group) !->
			log Db.shared.get('registered', group.key(), 'upToDate')
			if Db.shared.get('registered', group.key(), 'upToDate') is 'true'
				counter.incr()
		Ui.button "Updating databases... ("+ counter.get() +'/'+ numberOfRegisters+')',  !-> 
			Modal.show "Databases already updating", !->
				Dom.div !->
					Dom.text "The databases are already updating, wait a while until the update is finished or force update them now."
					Dom.style maxWidth: '300px', textAlign: 'left'
			, (choice)->
				if choice is 'do'
					Server.sync 'gatherHistory', !->
						Db.shared.set 'updating', 'true'
			,['cancel', "Cancel", 'do', "Force update"]
	else
		Ui.button "Update database",  !-> 
			Server.sync 'gatherHistory', !->
				Db.shared.set 'updating', 'true'
	Dom.text 'Last updated: '
	Time.deltaText (Db.shared.get('latestUpdate') || 0)
	Dom.br()

	Ui.button "Update statistics", !->
		Server.send 'updateStatistics'
	Dom.text 'Last updated: '
	Time.deltaText (Db.shared.get('lastStatisticUpdate') || 0)
	Dom.br()

	Dom.text "Last deploy: "+Db.shared.get('lastDeploy')
	Dom.br()
	Dom.br()

	renderMembersPerHappening()

renderMembersPerHappening = !->
	Dom.h1 "Player numbers"
	Dom.text "Total players in all games: "+Db.shared.get('statistic', 'totalPlayers')
	Dom.br()
	Dom.text "Average players: "+Db.shared.get('statistic', 'averagePlayers')


