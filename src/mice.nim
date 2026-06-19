import os, osproc, strutils, sequtils, times, parseutils, httpclient, terminal
import unicode as uni
import winim/lean

const VERSION = "0.1.0"
const MAX_HISTORY = 100

# ---------- ГЛОБАЛЬНЫЕ ПЕРЕМЕННЫЕ ----------
var history: seq[string] = @[]
var currentEncoding = "UTF-8"

proc executeCommand(input: string)

# ---------- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ----------
proc cmdEnc(args: seq[string]) =
  if args.len == 0:
    echo "> Current encoding: ", currentEncoding
    return
  
  let codePage = args[0]
  
  let validPages = ["65001", "1251", "866", "437"]
  if codePage notin validPages:
    echo "> Error: unknown code page. Use: 65001, 1251, 866, 437"
    return
  
  try:
    let (output, exitCode) = execCmdEx("cmd /c chcp " & codePage)
    
    if exitCode == 0:
      case codePage
      of "65001": currentEncoding = "UTF-8"
      of "1251": currentEncoding = "Windows-1251"
      of "866": currentEncoding = "DOS-866"
      of "437": currentEncoding = "US-ASCII"
      echo "> Ok. ", currentEncoding, " used."
    else:
      echo "> Error: could not change code page (exit code: ", exitCode, ")"
  except:
    echo "> Error: ", getCurrentExceptionMsg()

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

# ---------- ФУНКЦИИ ИСТОРИИ ----------
proc addHistory(cmd: string) =
  if cmd.strip().len == 0: return
  if history.len > 0 and history[^1] == cmd:
    return
  history.add(cmd)
  if history.len > MAX_HISTORY:
    history.delete(0)

proc clearHistory() =
  history.setLen(0)

proc showHistory() =
  if history.len == 0:
    echo "> History is empty"
    return
  for i, cmd in history:
    echo "> ", i+1, "  ", cmd

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
    let output = execProcess("ping -n 1 " & host)
    let lines = output.splitLines()
    for line in lines:
      if "time=" in line:
        let parts = line.split("time=")
        if parts.len > 1:
          let timeStr = parts[1].split("ms")[0].strip()
          echo "> ", timeStr, "ms"
          return
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
  echo "  enc               Change encoding (65001, 1251, 866, 437)"
  echo "  cls               Clear screen"
  echo "  history           Show command history"
  echo "  ch                Clear command history"
  echo "  load              Execute script file (.mc)"
  echo "  takes             Conditional execution"
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
  
  let fileParts = strutils.splitWhitespace(parts[0])
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
    var rows: seq[seq[string]] = @[]
    var maxNameLen = 4
    var maxSizeLen = 4
    var maxRightsLen = 6
    var maxDateLen = 19
    
    for kind, path2 in walkDir(path):
      let name = extractFilename(path2)
      let size = getFileSizeStr(path2)
      let rights = getRights(path2)
      let date = formatDate(getLastModificationTime(path2))
      
      rows.add(@[name, size, rights, date])
      
      maxNameLen = max(maxNameLen, uni.runeLen(name))
      maxSizeLen = max(maxSizeLen, uni.runeLen(size))
      maxRightsLen = max(maxRightsLen, uni.runeLen(rights))
      maxDateLen = max(maxDateLen, uni.runeLen(date))
    
    let sepLine = "+" & "-".repeat(maxNameLen + 2) & "+" &
                  "-".repeat(maxSizeLen + 2) & "+" &
                  "-".repeat(maxRightsLen + 2) & "+" &
                  "-".repeat(maxDateLen + 2) & "+"
    
    echo "> ", sepLine
    echo "> | ", "FILE".alignLeft(maxNameLen), " | ",
                "SIZE".alignLeft(maxSizeLen), " | ",
                "RIGHTS".alignLeft(maxRightsLen), " | ",
                "DATE".alignLeft(maxDateLen), " |"
    echo "> ", sepLine
    
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

proc cmdTechno() =
  echo "> Technoblade never dies... 🥀"

proc cmdNotch() =
  echo "                                               /|"
  echo "> No, I can't throw an apple in the console.../ |  <-- This is a fishing rod 😅"
  echo "                                                |"
  echo "                                                |"
  echo "                                                |"
  echo "                                               .?"
  echo "                                               🍎"

proc isKeyPressed(virtualKey: int): bool =
  return (GetAsyncKeyState(int32(virtualKey)) and 0x8000) != 0

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
      let cmd = trimmed.strip(chars = {'^', '#'})
      
      if not isSilent:
        echo "> [script] ", cmd
      
      executeCommand(cmd)
      
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdTakes(args: seq[string]) =
  if args.len < 2:
    echo "> Error: invalid takes syntax"
    return
  
  let cmdLine = args.join(" ")
  
  let questionPos = cmdLine.find(" ? ")
  if questionPos == -1:
    echo "> Error: use 'condition ? true_command : false_command'"
    return
  
  let conditionPart = cmdLine[0..<questionPos].strip()
  let commandsPart = cmdLine[questionPos+3..^1].strip()
  
  let cleanCondition = conditionPart.strip().strip(chars = {'(', ')'})
  let conditions = cleanCondition.split(" and ")
  
  var keysToPress: seq[int] = @[]
  var keyNames: seq[string] = @[]
  
  for cond in conditions:
    let condStr = cond.strip()
    if condStr.startsWith("press."):
      let keyName = condStr[6..^1].toUpperAscii()
      keyNames.add(keyName)
      
      let vk = case keyName
        of "Y": 0x59
        of "L_SHIFT": 0xA0
        of "R_SHIFT": 0xA1
        of "CTRL", "L_CTRL": 0xA2
        of "R_CTRL": 0xA3
        of "ALT", "L_ALT": 0xA4
        of "R_ALT": 0xA5
        of "A": 0x41
        of "B": 0x42
        of "C": 0x43
        of "D": 0x44
        of "E": 0x45
        of "F": 0x46
        of "G": 0x47
        of "H": 0x48
        of "I": 0x49
        of "J": 0x4A
        of "K": 0x4B
        of "L": 0x4C
        of "M": 0x4D
        of "N": 0x4E
        of "O": 0x4F
        of "P": 0x50
        of "Q": 0x51
        of "R": 0x52
        of "S": 0x53
        of "T": 0x54
        of "U": 0x55
        of "V": 0x56
        of "W": 0x57
        of "X": 0x58
        of "Z": 0x5A
        else: 0
      
      if vk != 0:
        keysToPress.add(vk)
      else:
        echo "> Error: unknown key: ", keyName
        return
    else:
      echo "> Error: unknown condition: ", condStr
      return
  
  if keysToPress.len == 0:
    echo "> Error: no valid keys to press"
    return
  
  echo "> Press ", keyNames.join(" + "), " simultaneously..."
  
  var allPressed = false
  var attempts = 0
  
  while attempts < 1000:
    var pressed = 0
    for vk in keysToPress:
      if isKeyPressed(vk):
        pressed += 1
    
    if pressed == keysToPress.len:
      allPressed = true
      break
    
    attempts += 1
    sleep(10)
  
  let colonPos = commandsPart.find(" : ")
  if colonPos == -1:
    echo "> Error: missing true/false commands"
    return
  
  let trueCmdPart = commandsPart[0..<colonPos].strip()
  let falseCmdPart = commandsPart[colonPos+3..^1].strip()
  
  let trueCmd = trueCmdPart.strip(chars = {'(', ')'})
  let falseCmd = falseCmdPart.strip()
  
  if allPressed:
    echo "> [condition true]"
    executeCommand(trueCmd)
  else:
    echo "> [condition false]"
    executeCommand(falseCmd)

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
    of "takes": cmdTakes(args)
    else:
      echo "> Unknown command: ", command

# ---------- ГЛАВНЫЙ ЦИКЛ ----------
when isMainModule:
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