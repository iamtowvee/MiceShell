import os, strutils, terminal
import commands
import parser

const VERSION = "0.1.0"
const MAX_HISTORY = 100

# ---------- ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ----------
var history: seq[string] = @[]

proc executeCommand(input: string)

# ---------- ИСТОРИЯ ----------
proc addHistory(cmd: string) =
  if cmd.strip().len == 0: return
  if history.len > 0 and history[^1] == cmd: return
  history.add(cmd)
  if history.len > MAX_HISTORY: history.delete(0)

proc clearHistory() =
  history.setLen(0)

proc showHistory() =
  if history.len == 0:
    echo "> History is empty"
    return
  for i, cmd in history:
    echo "> ", i+1, "  ", cmd

# ---------- LOAD ----------
proc cmdLoad(args: seq[string]) =
  if args.len == 0:
    echo "> Error: specify script file"
    return
  
  let scriptFile = args[0]
  if not fileExists(scriptFile):
    echo "> Error: script file not found: ", scriptFile
    return
  
  try:
    let content = readFile(scriptFile)
    let lines = content.splitLines()
    
    for line in lines:
      let trimmed = line.strip()
      if trimmed.len == 0: continue
      if trimmed.startsWith("~"): continue
      
      let isSilent = trimmed.startsWith("#")
      var cmd = trimmed
      
      # Убираем ВСЕ символы # и ^ в начале
      while cmd.len > 0 and (cmd[0] == '#' or cmd[0] == '^'):
        cmd = cmd[1..^1]
      
      # Дополнительно убираем пробелы
      cmd = cmd.strip()
      
      if not isSilent:
        echo "> [script] ", cmd
      
      if cmd.startsWith("takes"):
        let nodes = parseScript(cmd)
        execScript(nodes)
      else:
        executeCommand(cmd)
      
  except:
    echo "> Error: ", getCurrentExceptionMsg()

# ---------- ВЫПОЛНЕНИЕ КОМАНД ----------
proc executeCommand(input: string) =
  let commands = input.split(" & ")
  for cmd in commands:
    let parts = strutils.splitWhitespace(cmd.strip())
    if parts.len == 0: continue
    
    let command = parts[0]
    let args = parts[1..^1]
    
    case command
    of "help": cmdHelp()
    of "exit": cmdExit()
    of "outln": cmdOutln(args)
    of "cd": cmdCd(args)
    of "win": cmdWin()
    of "crt": cmdCrt(args)
    of "rmf": cmdRmf(args)
    of "new": cmdNew(args)
    of "dlf": cmdDlf(args)
    of "gls": cmdGls(args)
    of "anl": cmdAnl(args)
    of "efl": cmdEfl(args)
    of "chg": cmdChg(args)
    of "fl": cmdFl(args)
    of "tree": cmdTree(args)
    of "ft": cmdFt(args)
    of "sys": cmdSys()
    of "mice": cmdMice()
    of "!:kill::java::user::Notch:.<3.OOPS..#!": cmdNotch()
    of "@Technoblade...#!NOOOOOOOO!...:(...#;": cmdTechno()
    of "cls": cmdCls()
    of "ping": cmdPing(args)
    of "ip": cmdIp()
    of "enc": cmdEnc(args)
    of "fch": cmdFch(args)
    of "dwn": cmdDwn(args)
    of "history": showHistory()
    of "ch": clearHistory(); echo "> History cleared"
    of "load": cmdLoad(args)
    else:
      echo "> Unknown command: ", command

# ---------- ГЛАВНЫЙ ЦИКЛ ----------
when isMainModule:
  execCommand = executeCommand  # <-- передаём функцию в парсер

  echo "MiceShell v", VERSION
  echo "Distributed under Apache-2.0"
  echo ""
  echo "  Tip: use ↑↓ for history, Tab for completion"
  echo ""
  
  while true:
    stdout.write("* ")
    stdout.flushFile()
    
    try:
      let input = stdin.readLine()
      if input.strip().len > 0:
        addHistory(input)
        executeCommand(input)
    except EOFError:
      echo ""
      echo "> Exited with Code::0"
      break
    except:
      echo "> Error: ", getCurrentExceptionMsg()