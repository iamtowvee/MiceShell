import os, strutils, sequtils, times, parseutils

const VERSION = "0.1.0"

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

# ---------- КОМАНДЫ ----------
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
  echo "  mice              Nothing... <3"

proc cmdExit() =
  echo "> Exited with Code::0"
  quit(0)

proc cmdOutln(args: seq[string]) =
  echo args.join(" ")

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
    echo "> | FILE   | SIZE | RIGHTS | DATE                |"
    echo "> |--------|------|--------|---------------------|"
    
    for kind, path2 in walkDir(path):
      let name = extractFilename(path2)
      let size = getFileSizeStr(path2)
      let rights = getRights(path2)
      let date = formatDate(getLastModificationTime(path2))
      echo "> | ", name.alignLeft(6), " | ", size.alignLeft(4), " | ", rights.alignLeft(6), " | ", date, " |"
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
    else:
      echo "> Unknown command: ", command

# ---------- ГЛАВНЫЙ ЦИКЛ ----------
when isMainModule:
  echo "MiceShell v", VERSION
  echo "Distributed under Apache-2.0"
  echo ""
  
  while true:
    stdout.write("* ")
    stdout.flushFile()
    let input = stdin.readLine()
    if input.strip().len > 0:
      executeCommand(input)