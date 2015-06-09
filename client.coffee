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
	numberOfRegisters = 0
	Db.shared.iterate 'registered', (group) !->
		numberOfRegisters++
	Dom.h1 "Data updating"
	Dom.div !->
		Dom.style marginLeft: '-4px', display: 'inline-block'
		if Db.shared.get('updating')? and Db.shared.get('updating') == 'true'
			doneCount = Db.shared.get('doneCount')
			Ui.button "Updating... (" + doneCount + "/" + numberOfRegisters + ")", !-> 
				Modal.show "Databases already updating", !->
					Dom.div !->
						Dom.text "The databases are already updating, wait a while until the update is finished or force update them now."
						Dom.style maxWidth: '300px', textAlign: 'left'
				, (choice)->
					if choice is 'do'
						Server.sync 'gatherHistory', !->
							Db.shared.set 'updating', 'true'
							Db.shared.set 'doneCount', 0
				,['cancel', "Cancel", 'do', "Force update"]
		else
			Ui.button "Update database", !-> 
				Server.sync 'gatherHistory', !->
					Db.shared.set 'updating', 'true'
					Db.shared.set 'doneCount', 0
	Dom.text 'Last updated: '
	Time.deltaText (Db.shared.get('latestUpdate') || 0)
	Dom.br()

	Dom.div !->
		Dom.style marginLeft: '-4px', display: 'inline-block'
		Ui.button "Update statistics", !->
			Server.send 'updateStatistics'
	Dom.text 'Last updated: '
	Time.deltaText (Db.shared.get('lastStatisticUpdate') || 0)

	Dom.div !->
		Dom.style clear: 'both'
		Dom.text "Last deploy: "+Db.shared.get('lastDeploy')
		Dom.br()
		Dom.br()

	renderMembersPerHappening()

renderMembersPerHappening = !->
	Dom.h1 "General numbers"
	numberOfRegisters = 0
	Db.shared.iterate 'registered', (group) !->
		numberOfRegisters++
	displayResult("Registered plugins: ", numberOfRegisters)
	displayResult("Total players in all games: ", Db.shared.get('statistic', 'totalPlayers'))
	displayResult("Average players: ", Db.shared.get('statistic', 'averagePlayers'))

displayResult = (text, result) !->
	Dom.div !->
		Dom.text text
		Dom.style minWidth: '200px', float: 'left'
	Dom.text result
	Dom.br()


