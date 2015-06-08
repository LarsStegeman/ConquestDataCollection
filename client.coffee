Db = require 'db'
Dom = require 'dom'
Modal = require 'modal'
Obs = require 'obs'
Plugin = require 'plugin'
Page = require 'page'
Server = require 'server'
Ui = require 'ui'
Time = require 'time'


exports.render = ->
	Ui.bigButton "Update database",  !-> 
		Server.send 'gatherHistory'


	Dom.div !->
		Dom.text 'Last updated: '
		Time.deltaText (Db.shared.get('latestUpdate') || 0)
		Dom.br()
		Dom.text 'There are ' + (Db.shared.get('registeredPlugins') || 0 )+ ' plugins registered' 

