import os, strutils, osproc, parseutils, deques, terminal

const
  VERSION = "1.0"
  MAX_HISTORY = 100

var 
  history = initDeque[string]()
  lastExitCode = 0

# ---------- ВСТРОЕННЫЕ КОМАНДЫ ----------
proc builtinExit(args: seq[string]) = quit(0)

proc builtinCd(args: seq[string]) =
  let target = if args.len > 1: args[1] else: getEnv("USERPROFILE")
  try: setCurrentDir(target)
  except: echo "cd: ", getCurrentExceptionMsg()

proc builtinPwd(args: seq[string]) = echo getCurrentDir()
proc builtinEcho(args: seq[string]) = echo args[1..^1].join(" ")

proc builtinHistory(args: seq[string]) =
  for i, cmd in history:
    echo i, "  ", cmd

proc builtinHelp(args: seq[string]) =
  echo """
MiceShell v1.0 - Встроенные команды:
  cd [dir]    - сменить директорию
  pwd         - показать текущую папку
  echo ...    - вывести текст
  exit        - выход
  history     - показать историю
  help        - эта справка
  clear       - очистить экран
  """

proc builtinClear(args: seq[string]) =
  eraseScreen()
  setCursorPos(0, 0)

# ---------- ДИСПЕТЧЕР ----------
proc executeBuiltin(cmd: string, args: seq[string]): bool =
  case cmd.toLowerAscii()
  of "exit": builtinExit(args); return true
  of "cd": builtinCd(args); return true
  of "pwd": builtinPwd(args); return true
  of "echo": builtinEcho(args); return true
  of "history": builtinHistory(args); return true
  of "help": builtinHelp(args); return true
  of "clear": builtinClear(args); return true
  else: return false

# ---------- ЗАПУСК ВНЕШНИХ КОМАНД ----------
proc findExecutable(cmd: string): string =
  if fileExists(cmd): return cmd
  for ext in [".exe", ".bat", ".cmd"]:
    if fileExists(cmd & ext): return cmd & ext
  
  let path = getEnv("PATH")
  for dir in path.split(';'):
    let candidate = dir / cmd
    if fileExists(candidate): return candidate
    for ext in [".exe", ".bat", ".cmd"]:
      if fileExists(candidate & ext): return candidate & ext
  return ""

# ---------- ВОТ ЭТОТ ВАРИАНТ РАБОТАЕТ 100% ----------
proc executeExternal(cmdLine: string): int =
  let args = cmdLine.parseCmdLine()
  if args.len == 0: return 0
  
  let exe = findExecutable(args[0])
  if exe == "":
    echo "micesh: ", args[0], ": команда не найдена"
    return 1
  
  # Самый простой способ - просто выполнить команду как в cmd
  return execCmd(cmdLine)

# ---------- ГЛАВНЫЙ ЦИКЛ ----------
proc processLine(input: string) =
  let cmdLine = input.strip()
  if cmdLine.len == 0: return
  history.addLast(cmdLine)
  if history.len > MAX_HISTORY:
    history.popFirst()
  
  # Проверяем пайпы (пока заглушка)
  if "|" in cmdLine:
    echo "Пайпы в разработке..."
    return
  
  let args = cmdLine.parseCmdLine()
  if args.len == 0: return
  
  if not executeBuiltin(args[0], args):
    lastExitCode = executeExternal(cmdLine)

# ---------- ПРИГЛАШЕНИЕ ----------
proc prompt(): string =
  if isatty(stdout):
    let 
      user = getEnv("USERNAME")
      host = getEnv("COMPUTERNAME")
      dir = getCurrentDir().extractFilename()
      colorGreen = "\e[32m"
      colorYellow = "\e[33m"
      colorReset = "\e[0m"
    return colorGreen & user & "@" & host & colorReset & 
           ":" & colorYellow & dir & colorReset & "> "
  else:
    return "micesh> "

# ---------- ENTRY POINT ----------
when isMainModule:
  echo "MiceShell v", VERSION, " (Nim) - Введите 'help' для справки"
  
  while true:
    stdout.write(prompt())
    stdout.flushFile()
    try:
      let input = stdin.readLine()
      processLine(input)
    except EOFError:
      echo "\nВыход"
      break
    except:
      echo "Ошибка: ", getCurrentExceptionMsg()