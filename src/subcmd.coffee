fs = require 'fs'
path = require 'path'
which = require 'which'
subproc = require 'child_process'
loglet = require 'loglet'

split = (program) ->
  [ path.dirname(program), path.basename(program) ]

isOption = (arg) ->
  first = arg[0]
  first == '-' or first == '/'

normalize = (argv) ->
  program = fs.realpathSync argv[1]
  command = [] 
  rest = [] 
  done = false
  for i in [2...argv.length]
    if done 
      rest.push argv[i]
    else if isOption(argv[i])
      done = true
      rest.push argv[i]
    else
      command.push argv[i]
  if command.length > 0 and command[0] == 'help'
    command.shift()
    rest.push '--help'
  return [ program, command , rest ] 

isHelp = (command) ->
  command[0] == 'help'

spawn = (program, argv, cb) ->
  loglet.debug 'spawn.search', program, argv
  search program, argv, (err, res) ->
    loglet.debug 'spawn.search', err, res
    if err
      cb err
    else if res?.program
      child = subproc.spawn res.program, res.args, { stdio: 'inherit' }
      child.on 'exit', (code) ->
        process.exit code
      cb null, child
    else
      cb {error: 'subcommand_not_found', args: res.args}

searchHelper = (dirPath, cb) ->
  whichHelper = 
    if dirPath 
      (name, cb) ->
        filePath = path.join dirPath, name 
        fs.stat filePath, (err, stat) ->
          if err?.code == 'ENOENT'
            cb {file_not_found: filePath}
          else if err # not found... 
            cb err
          else
            cb null, filePath 
    else
      (name, cb) ->
        which name, (err, cmd) ->
          loglet.debug 'which.result', name, err, cmd, JSON.stringify(err)
          if err?.message.match /not found\:/
            loglet.debug 'which.result.not_found'
            cb {file_not_found: name}
          else if err
            cb err
          else
            cb err, cmd
  helper = (program, rest, prev) ->
    loglet.debug 'searchHelper.helper', program, rest, prev
    if rest.length == 0 
      return cb null, {program: prev, args: rest}
    seg = rest.shift() 
    name = [ program, seg].join('-')
    whichHelper name, (err, cmd) ->
      loglet.debug 'whichHelper', name, err, cmd
      if err?.file_not_found 
        loglet.debug 'whichHelper.not_found', name, prev
        if prev 
          rest.unshift(seg)
          cb null, {program: prev, args: rest}
        else
          cb err
      else if err 
        cb err
      else 
        helper name, rest, cmd
  helper

_whichPath = (program, commands, cb) ->
  [ programDir, programName ] = split program
  loglet.debug '_whichPath.split', programDir, programName
  helper = searchHelper null, cb
  helper programName, [].concat(commands), null

_localPath = (program, commands, cb) ->
  [ programDir, programName ] = split program
  loglet.debug '_localPath.split', programDir, programName
  helper = searchHelper programDir, cb
  helper programName, [].concat(commands), null 

search = (program, argv, cb) ->
  [ program, commands , rest ] = normalize argv 
  if commands.length == 0 
    cb {no_sub_command: program, args: rest}
  _localPath program, commands, (err, result) ->
    if err?.file_not_found 
      _whichPath program, commands, (err, result) ->
        if err 
          cb err
        else
          cb null, {program: result.program, args: result.args.concat(rest)}
    else if err
      cb err
    else 
      cb null, {program: result.program, args: result.args.concat(rest)}

getSubCommands = (programPath, cb) ->
  dirname = path.dirname(programPath)
  program = path.basename programPath
  fs.readdir dirname, (err, files) ->
    if err
      cb err
    else
      commands = {}
      for file in files 
        if file != program and file.indexOf(program + '-') == 0
          commands[file.substring(program.length + 1)] = path.join dirname, file 
      cb null, commands

module.exports = 
  which: search
  spawn: spawn
