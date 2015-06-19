Db = require 'db'
Dom = require 'dom'
Modal = require 'modal'
Obs = require 'obs'
Plugin = require 'plugin'
Server = require 'server'
Ui = require 'ui'
Time = require 'time'

Config = {
		startTimestamp: 1434405600.0			# Timestamp which is used as day 0 for the statistics
	}

exports.render = ->
	log "FULL RENDER"
	renderUpdateInfo()
	renderGeneral()
	renderGameEndCauses()
	renderGeneralGameEvents()
	renderGameSetup()
	renderCapturesPerDay()
	renderGroupsPerGroupsize()
	Dom.br()

renderUpdateInfo = !->
	# Cause full update when databases get or statistics updated
	Db.shared.get('latestUpdate')
	Db.shared.get('lastStatisticUpdate')

	Obs.observe ->
		Dom.h2 "Data info and updates"
		Dom.div !->
			numberOfRegisters = Db.shared.get('registeredPlugins')-Db.shared.get('removedPlugins')
			Dom.style marginLeft: '-4px', display: 'inline-block'
			if Db.shared.get('updating')? and Db.shared.get('updating') == 'true'
				doneCount = Db.shared.get('doneCount')
				buttonText = ""
				if Db.shared.get('doneSendingRequests') == 'no'
					buttonText = "Updating"
				else
					buttonText = "Waiting"
				buttonText += "... (" + doneCount + "/" + numberOfRegisters + ")"
				Ui.button buttonText, !-> 
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
		Dom.div !->
			Dom.style display: 'inline-block'
			Dom.text 'Last updated: '
			Time.deltaText (Db.shared.get('latestUpdate') || 0)
		Dom.br()

		Dom.div !->
			Dom.style marginLeft: '-4px', display: 'inline-block'
			if Db.shared.get('updatingStatistics')? and Db.shared.get('updatingStatistics') == 'true'
				Ui.button "Updating statistics...", !->
					Modal.show "Statistics already updating", !->
						Dom.div !->
							Dom.text "The statistics are already updating, wait a while until the update is finished or force update them now."
							Dom.style maxWidth: '300px', textAlign: 'left'
					, (choice)->
						if choice is 'do'
							Server.sync 'updateStatistics', !->
								Db.shared.set 'updatingStatistics', 'true'
					,['cancel', "Cancel", 'do', "Force update"]
			else
				Ui.button "Update statistics", !->
					Server.sync 'updateStatistics', !->
						Db.shared.set 'updatingStatistics', 'true'
		Dom.div !->
			Dom.style display: 'inline-block'
			Dom.text 'Last updated: '
			Time.deltaText (Db.shared.get('lastStatisticUpdate') || 0)
		Dom.br()

		Dom.div !->
			Dom.style clear: 'both'
			Dom.text "Last deploy: "+Db.shared.get('lastDeploy')
		Dom.br()

renderGeneral = !->
	Obs.observe ->
		Dom.h2 "General"
		display("Plugins: ", Db.shared.get('registeredPlugins'))
		display("Removed plugins: ", Db.shared.get('removedPlugins'))
		display("Players: ", Db.shared.get('totalPlayers'))
		displayRound("Average players: ", Db.shared.get('averagePlayers'))
		display("Games: ", Db.shared.get('totalGames'))
		Dom.br()

renderGameEndCauses = !->
	Obs.observe ->
		Dom.h2 "Game end causes"
		total = Db.shared.get('totalGames')
		display("Reset in setup: ", Db.shared.get('gamesSetup'))
		display("Reset while running: ", Db.shared.get('gamesRunning'))
		display("Ended with winner: ", Db.shared.get('gamesEnded'))
		Dom.div !->
			Dom.style width: '100%', height: '20px', backgroundColor: '#CCCCCC', color: '#FFFFFF', lineHeight: '20px', textAlign: 'center', fontSize: '12px'
			Dom.div !->
				Dom.style width: ((Db.shared.get('gamesSetup')/total)*100)+'%', backgroundColor: '#E84242', height: '100%', float: 'left', textShadow: '0 0 3px rgba(0,0,0,0.9)'
				Dom.text "setup"
			Dom.div !->
				Dom.style width: ((Db.shared.get('gamesRunning')/total)*100)+'%', backgroundColor: '#FDBA3E', height: '100%', float: 'left', textShadow: '0 0 3px rgba(0,0,0,0.9)'
				Dom.text "running"
			Dom.div !->
				Dom.style width: ((Db.shared.get('gamesEnded')/total)*100)+'%', backgroundColor: '#1E981E', height: '100%', float: 'left', textShadow: '0 0 3px rgba(0,0,0,0.9)'
				Dom.text "end"
		Dom.br()

renderGeneralGameEvents = !->
	Obs.observe ->
		Dom.h2 "General game events"
		display("Events: ", Db.shared.get('totalEvents'))
		displayRound("Events/game: ", Db.shared.get('totalEvents')/Db.shared.get('totalGames'))
		display("Captures: ", Db.shared.get('totalCaptures'))
		displayRound("Captures/game: ", Db.shared.get('totalCaptures')/Db.shared.get('totalGames'))
		display("Neutralizes: ", Db.shared.get('totalNeutralizes'))
		displayRound("Neutralizes/game: ", Db.shared.get('totalNeutralizes')/Db.shared.get('totalGames'))
		Dom.br()

renderCapturesPerDay = !->
	Obs.observe ->
		Dom.h2 'Captures per day'
		maxEvents=0
		rows = 0
		Db.shared.iterate 'eventsPerDay', (day) !->
			if day.peek() > maxEvents
				maxEvents = day.peek()
		Dom.div !->
			Dom.style width: '100px', position: 'absolute', left: '8px'
			Db.shared.iterate 'eventsPerDay', (day) !->
				rows++
				Dom.div !->
					d = new Date((Config.startTimestamp+ day.key()*86400)*1000)
					Dom.text d.getDate() + '-' + d.getMonth() + '-' + d.getFullYear()
					Dom.style height: '20px', lineHeight: '20px', marginBottom: '3px'
		Dom.div !->
			Dom.style width: 'auto', right: '8px', left: '100px', position: 'absolute'		
			Db.shared.iterate 'eventsPerDay', (day) !->
				Dom.div !->
					Dom.style width: (day.get()/maxEvents*100) + '%',height: '20px', backgroundColor: '#1E981E',  color: '#FFFFFF', textAlign: 'right', fontSize: '12px', paddingRight: '7px', lineHeight: '20px', marginBottom: '3px', textShadow: '0 0 3px rgba(0,0,0,0.9)'
					Dom.style _boxSizing: 'border-box'
					Dom.text day.get()
		Dom.div !->
			Dom.style marginBottom: (rows*23) + 'px'
		Dom.br()

renderGroupsPerGroupsize = !->
	Obs.observe ->
		Dom.h2 'Groups per groupsize'
		maxCount=0
		rows = 0
		keys = []
		Db.shared.iterate 'groupsPerGroupSize', (groupsize) !->
			keys.push(parseInt(groupsize.key()))
			if groupsize.peek() > maxCount
				maxCount = groupsize.peek()
		keys.sort((a, b) -> return a-b)
		Dom.div !->
			Dom.style width: '100px', position: 'absolute', left: '8px'
			for key in keys
				rows++
				Dom.div !->
					Dom.style height: '20px', lineHeight: '20px', marginBottom: '3px'
					Dom.text key + ' players:'
		Dom.div !->
			Dom.style width: 'auto', right: '8px', left: '100px', position: 'absolute'
			for key in keys
				Dom.div !->
					Dom.style width: (Db.shared.get('groupsPerGroupSize', key+'')/maxCount*100) + '%',height: '20px', backgroundColor: '#0077cf',  color: '#FFFFFF', textAlign: 'right', fontSize: '12px', paddingRight: '7px', lineHeight: '20px', marginBottom: '3px', textShadow: '0 0 3px rgba(0,0,0,0.9)'
					Dom.style _boxSizing: 'border-box'
					Dom.text Db.shared.get('groupsPerGroupSize', key+'')
		Dom.div !->
			Dom.style marginBottom: (rows*23) + 'px'
		Dom.br()

renderGameSetup = !->
	Obs.observe ->
		Dom.h2 'Game setup'
		display("Beacons", Db.shared.get('beacons'))
		displayRound("Average beacons", Db.shared.get('beacons') / (Db.shared.get('gamesRunning') + Db.shared.get('gamesEnded')))
		display("Valid bounds", Db.shared.get('validBounds'))
		x = Db.shared.get('boundsX')
		y = Db.shared.get('boundsY')
		if x >= 1000
			displayRoundSuffix("Average play width", x/1000, 'km')
		else
			displayRoundSuffix("Average play width", x, 'm')
		if y >= 1000
			displayRoundSuffix("Average play width", y/1000, 'km')
		else
			displayRoundSuffix("Average play width", y, 'm')
		Dom.br()


# ========== Functions ==========
display = (text, result) !->
	Dom.div !->
		Dom.text text
		Dom.style minWidth: '180px', float: 'left'
	Dom.text result
	Dom.br()
displayRound = (text, result) !->
	display(text, Math.round(result*1000)/1000)
displayRoundSuffix = (text, result, suffix) !->
	display(text, (Math.round(result*1000)/1000) + suffix)
