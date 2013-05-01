helpers = require('enkihelpers')

Q = require('q')

EventEmitter = require('eemitterport').EventEmitter

module.exports = class Protocol extends EventEmitter
  constructor: (@engine_server, @connection, @pce) ->
    @connection.stumpify(@, @_get_obj_desc)

  _get_obj_desc: =>
    return 'Protocol ' + @connection.conncounter

  start: =>
    @info 'STARTING PROTOCOL'
    @connection.on('parsed_data', @handle_parsed_data)

  handle_parsed_data: (parsed_data) =>
    @info 'RECEIVED', parsed_data
    @pce.forward_operation( parsed_data ).then (result) =>
      @info 'PCE COMPLETED', result.toString()
      
      @engine_server.send_all( {result: result.toString()} )
    .done()