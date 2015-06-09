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
	Dom.text 'There are ' + (Db.shared.get('registeredPlugins') || 0 )+ ' plugins registered'
	Dom.br()

	if Db.shared.get('updating')? and Db.shared.get('updating') == 'true'
		Ui.button "Updating databases... ("+Db.shared.get('updated')+'/'+Db.shared.get('registeredPlugins')+')',  !-> 
			Modal.show "Databases already updating", !->
				Dom.div !->
					Dom.text "The databases are already updating, wait a while until the update is finished or force update them now."
					Dom.style maxWidth: '300px', textAlign: 'left'
			, (choice)->
				if choice is 'do'
					Server.sync 'gatherHistory', !->
						Db.shared.set 'updating', 'true'
						Db.shared.set 'updated', 0
			,['cancel', "Cancel", 'do', "Force update"]
	else
		Ui.button "Update database",  !-> 
			Server.sync 'gatherHistory', !->
				Db.shared.set 'updating', 'true'
				Db.shared.set 'updated', 0
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


