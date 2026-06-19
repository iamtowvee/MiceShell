import os, osproc, strutils, sequtils, times, parseutils, httpclient, terminal

const VERSION = "0.1.0"
const MAX_HISTORY = 100

# ---------- ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ----------
var history: seq[string] = @[]
var historyIndex = -1

# ---------- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ----------
proc getFileSizeStr(path: string): string =
  try:
    let size = getFileSize(path)
    if size < 1024:
      return $size & "B"
    elif size < 1024 * 1024:
      return $(size div 1024) & "KB"
    else:
      return $(size div (1024 * 1024)) & "MB"
  except:
    return "0B"

proc getRights(path: string): string =
  if fileExists(path):
    try:
      let f = open(path, fmReadWriteExisting)
      f.close()
      return "RW"
    except:
      return "RO"
  elif dirExists(path):
    return "DIR"
  else:
    return "---"

proc formatDate(time: Time): string =
  return time.format("yyyy-MM-dd HH:mm:ss")

proc addHistory(cmd: string) =
  if cmd.strip().len == 0: return
  if history.len > 0 and history[^1] == cmd:
    return
  history.add(cmd)
  if history.len > MAX_HISTORY:
    history.delete(0)

proc clearHistory() =
  history.setLen(0)
  historyIndex = -1

proc showHistory() =
  if history.len == 0:
    echo "> History is empty"
    return
  for i, cmd in history:
    echo "> ", i+1, "  ", cmd

# ---------- ВВОД С ИСТОРИЕЙ ----------
proc readLineWithHistory(): string =
  var input = ""
  var pos = 0
  
  while true:
    # Позиционируем курсор
    let promptLen = 2  # "* "
    stdout.write("\r* ")
    stdout.write(input)
    stdout.write(" " * 10)  # очищаем лишнее
    stdout.flushFile()
    
    # Перемещаем курсор на позицию ввода
    stdout.write("\r* ")
    for i in 0..<pos:
      stdout.write(input[i])
    stdout.flushFile()
    
    let key = stdin.getch()
    
    if key == '\r' or key == '\n':  # Enter
      echo ""
      return input
    
    elif key == '\x7f' or key == '\x08':  # Backspace
      if pos > 0:
        input.delete(pos-1, pos-1)
        pos -= 1
    
    elif key == '\x1b':  # Escape sequence
      let next = stdin.getch()
      if next == '[':
        let arrow = stdin.getch()
        case arrow
        of 'A':  # Up arrow
          if history.len > 0 and historyIndex < history.len - 1:
            historyIndex += 1
            input = history[^ (historyIndex + 1)]
            pos = input.len
        of 'B':  # Down arrow
          if historyIndex > -1:
            historyIndex -= 1
            if historyIndex >= 0:
              input = history[^ (historyIndex + 1)]
              pos = input.len
            else:
              input = ""
              pos = 0
        of 'C':  # Right arrow
          if pos < input.len:
            pos += 1
        of 'D':  # Left arrow
          if pos > 0:
            pos -= 1
        else:
          discard
    
    elif key.isPrintable:
      input.insert($key, pos)
      pos += 1
    else:
      discard

# cls - очистка экрана
proc cmdCls() =
  eraseScreen()
  setCursorPos(0, 0)

# ping - через системную команду (Windows)
proc cmdPing(args: seq[string]) =
  if args.len == 0:
    echo "> Error: specify host"
    return
  try:
    let host = args[0]
    # Запускаем ping и парсим вывод
    let output = execProcess("ping -n 1 " & host)
    let lines = output.splitLines()
    for line in lines:
      # Ищем время в ответе
      if "time=" in line:
        let parts = line.split("time=")
        if parts.len > 1:
          let timeStr = parts[1].split("ms")[0].strip()
          echo "> ", timeStr, "ms"
          return
      # Альтернативный формат (если нет time=)
      if "time<" in line:
        echo "> <1ms"
        return
    echo "> Error: could not parse ping response"
  except:
    echo "> Error: ", getCurrentExceptionMsg()

# ip - через системную команду (Windows)
proc cmdIp() =
  try:
    let output = execProcess("ipconfig")
    let lines = output.splitLines()
    for line in lines:
      # Ищем IPv4 адрес
      if "IPv4" in line or "IPv4-адрес" in line:
        let parts = line.split(":")
        if parts.len > 1:
          let ip = parts[1].strip()
          if ip.len > 0 and ip != "0.0.0.0":
            echo "> ", ip
            return
    echo "> Error: IP not found"
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdFch(args: seq[string]) =
  if args.len < 2:
    echo "> Error: specify URL and variable name"
    return
  
  let cmdLine = args.join(" ")
  let parts = cmdLine.split(" : ")
  if parts.len < 2:
    echo "> Error: use 'url : variable' format"
    return
  
  let url = parts[0].strip()
  let varName = parts[1].strip()
  
  try:
    let client = newHttpClient()
    let response = client.get(url)
    if response.code == Http200:
      putEnv(varName, response.body)
      echo "> Ok. Content saved to ", varName, "."
    else:
      echo "> Error: HTTP ", response.code
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdDwn(args: seq[string]) =
  if args.len < 2:
    echo "> Error: specify URL and path"
    return
  
  let cmdLine = args.join(" ")
  let parts = cmdLine.split(" : ")
  if parts.len < 2:
    echo "> Error: use 'url : path' format"
    return
  
  let url = parts[0].strip()
  let filePath = parts[1].strip()
  
  try:
    let client = newHttpClient()
    let response = client.get(url)
    if response.code == Http200:
      writeFile(filePath, response.body)
      echo "> Ok. [", filePath, "]"
    else:
      echo "> Error: HTTP ", response.code
  except:
    echo "> Error: ", getCurrentExceptionMsg()

# outln с поддержкой переменных
proc cmdOutln(args: seq[string]) =
  if args.len == 0:
    echo ""
    return
  
  let text = args.join(" ")
  if text.startsWith("$"):
    let varName = text[1..^1]
    let value = getEnv(varName)
    if value.len > 0:
      echo value
    else:
      echo "> Error: variable not found"
  else:
    echo text

# ---------- ОСТАЛЬНЫЕ КОМАНДЫ ----------
proc cmdHelp() =
  echo "> help              Output help message"
  echo "  exit              Exit program"
  echo "  outln             Output line"
  echo "  cd                Change path"
  echo "  ft                Files & Folders tree"
  echo "  tree              Folders tree"
  echo "  fl                Files list"
  echo "  win               Where I now"
  echo "  crt               Create folder"
  echo "  rmf               Delete folder"
  echo "  new               Create file"
  echo "  dlf               Delete file"
  echo "  efl               Edit file line"
  echo "  anl               Add new line"
  echo "  gls               Get file lines"
  echo "  chg               Change file / folder name"
  echo "  dwn               Download file"
  echo "  fch               Take response"
  echo "  ping              Pinging server"
  echo "  ip                PC IP"
  echo "  cls               Clear screen"
  echo "  history           Show command history"
  echo "  clear-history     Clear command history"
  echo "  mice              Nothing... <3"

proc cmdExit() =
  echo "> Exited with Code::0"
  quit(0)

proc cmdCd(args: seq[string]) =
  if args.len == 0:
    echo "> Error: specify path"
    return
  try:
    setCurrentDir(args[0])
    echo "> Ok [", getCurrentDir(), "]"
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdWin() =
  echo "> ", getCurrentDir()

proc cmdCrt(args: seq[string]) =
  if args.len == 0:
    echo "> Error: specify folder name"
    return
  try:
    createDir(args[0])
    echo "> Ok. [", getCurrentDir() / args[0], "]"
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdRmf(args: seq[string]) =
  if args.len == 0:
    echo "> Error: specify folder name"
    return
  try:
    removeDir(args[0])
    echo "> Ok. [", getCurrentDir() / args[0], "]"
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdNew(args: seq[string]) =
  if args.len == 0:
    echo "> Error: specify file name"
    return
  try:
    writeFile(args[0], "")
    echo "> Ok. [", getCurrentDir() / args[0], "]"
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdDlf(args: seq[string]) =
  if args.len == 0:
    echo "> Error: specify file name"
    return
  try:
    removeFile(args[0])
    echo "> Ok. [", getCurrentDir() / args[0], "]"
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdGls(args: seq[string]) =
  if args.len == 0:
    echo "> Error: specify file name"
    return
  try:
    let lines = readFile(args[0]).splitLines()
    for i, line in lines:
      if line.len > 0 or i < lines.len - 1:
        echo i+1, " | ", line
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdAnl(args: seq[string]) =
  if args.len < 2:
    echo "> Error: specify file name and text"
    return
  
  let cmdLine = args.join(" ")
  let parts = cmdLine.split(" : ")
  if parts.len < 2:
    echo "> Error: use 'filename : text' format"
    return
  
  let fileName = parts[0].strip()
  var text = parts[1].strip()
  
  if text.startsWith("{") and text.endsWith("}"):
    text = text[1..^2]
  
  try:
    var lines = readFile(fileName).splitLines()
    if lines.len > 0 and lines[^1] == "":
      lines.delete(lines.len-1)
    
    for line in text.split("\\n"):
      lines.add(line)
    
    writeFile(fileName, lines.join("\n"))
    echo "> Ok. [", getCurrentDir() / fileName, "]"
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdEfl(args: seq[string]) =
  if args.len < 2:
    echo "> Error: specify file name, line number and text"
    return
  
  let cmdLine = args.join(" ")
  let parts = cmdLine.split(" : ")
  if parts.len < 2:
    echo "> Error: use 'filename lineNum : text' format"
    return
  
  let fileParts = parts[0].splitWhitespace()
  if fileParts.len < 2:
    echo "> Error: specify filename and line number"
    return
  
  let fileName = fileParts[0]
  let lineNum = parseInt(fileParts[1])
  var text = parts[1].strip()
  
  if text.startsWith("{") and text.endsWith("}"):
    text = text[1..^2]
  
  try:
    var lines = readFile(fileName).splitLines()
    if lines.len > 0 and lines[^1] == "":
      lines.delete(lines.len-1)
    
    if lineNum < 1 or lineNum > lines.len:
      echo "> Error: line number out of range"
      return
    
    lines[lineNum-1] = text
    writeFile(fileName, lines.join("\n"))
    echo "> Ok. [", getCurrentDir() / fileName, "]"
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdChg(args: seq[string]) =
  if args.len < 2:
    echo "> Error: specify old and new name"
    return
  try:
    let oldName = args[0]
    let newName = args[1..^1].join(" ")
    if fileExists(oldName):
      moveFile(oldName, newName)
    elif dirExists(oldName):
      moveDir(oldName, newName)
    else:
      echo "> Error: file or folder not found"
      return
    echo "> Ok. [", getCurrentDir() / newName, "]"
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdFl(args: seq[string]) =
  let path = if args.len > 0: args[0] else: "."
  try:
    # Собираем данные
    var rows: seq[seq[string]] = @[]
    var maxNameLen = 4  # "FILE"
    var maxSizeLen = 4  # "SIZE"
    var maxRightsLen = 6 # "RIGHTS"
    var maxDateLen = 19  # "DATE (yyyy-mm-dd HH:mm:ss)"
    
    for kind, path2 in walkDir(path):
      let name = extractFilename(path2)
      let size = getFileSizeStr(path2)
      let rights = getRights(path2)
      let date = formatDate(getLastModificationTime(path2))
      
      rows.add(@[name, size, rights, date])
      
      maxNameLen = max(maxNameLen, name.len)
      maxSizeLen = max(maxSizeLen, size.len)
      maxRightsLen = max(maxRightsLen, rights.len)
      maxDateLen = max(maxDateLen, date.len)
    
    # Рисуем таблицу
    let sepLine = "+" & "-".repeat(maxNameLen + 2) & "+" &
                  "-".repeat(maxSizeLen + 2) & "+" &
                  "-".repeat(maxRightsLen + 2) & "+" &
                  "-".repeat(maxDateLen + 2) & "+"
    
    # Заголовок (только здесь >)
    echo "> ", sepLine
    echo "> | ", "FILE".alignLeft(maxNameLen), " | ",
                "SIZE".alignLeft(maxSizeLen), " | ",
                "RIGHTS".alignLeft(maxRightsLen), " | ",
                "DATE".alignLeft(maxDateLen), " |"
    echo "> ", sepLine
    
    # Данные (без >)
    for row in rows:
      echo "  | ", row[0].alignLeft(maxNameLen), " | ",
                  row[1].alignLeft(maxSizeLen), " | ",
                  row[2].alignLeft(maxRightsLen), " | ",
                  row[3].alignLeft(maxDateLen), " |"
    
    echo "  ", sepLine
    
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdTree(args: seq[string]) =
  let path = if args.len > 0: args[0] else: "."
  try:
    for kind, dir in walkDir(path):
      if kind == pcDir:
        echo "> 📁 ", extractFilename(dir)
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdFt(args: seq[string]) =
  let path = if args.len > 0: args[0] else: "."
  try:
    for kind, item in walkDir(path):
      if kind == pcDir:
        echo "> 📁 ", extractFilename(item)
      else:
        echo "> 📄 ", extractFilename(item)
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdMice() =
  echo "> on venus"

# ---------- ВЫПОЛНЕНИЕ КОМАНД ----------
proc executeCommand(input: string) =
  let commands = input.split(" & ")
  for cmd in commands:
    let parts = cmd.strip().splitWhitespace()
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
    of "mice": cmdMice()
    of "cls": cmdCls()
    of "ping": cmdPing(args)
    of "ip": cmdIp()
    of "fch": cmdFch(args)
    of "dwn": cmdDwn(args)
    of "history": showHistory()
    of "ch": clearHistory(); echo "> History cleared"
    else:
      echo "> Unknown command: ", command

# ---------- ГЛАВНЫЙ ЦИКЛ ----------
when isMainModule:
  echo "MiceShell v", VERSION
  echo "Distributed under Apache-2.0"
  echo ""
  echo "  ↑↓ - navigate history, Tab - autocomplete (soon)"
  echo ""
  
  while true:
    stdout.write("* ")
    stdout.flushFile()
    
    let input = readLineWithHistory()
    
    if input.strip().len > 0:
      addHistory(input)
      historyIndex = -1
      executeCommand(input)