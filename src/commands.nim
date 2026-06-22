import os, osproc, strutils, times, httpclient, terminal
import unicode as uni
import winim/lean

var currentEncoding* = "UTF-8"

# ---------- ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ ----------
proc getFileSizeStr*(path: string): string =
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

proc getRights*(path: string): string =
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

proc formatDate*(time: Time): string =
  return time.format("yyyy-MM-dd HH:mm:ss")

# ---------- КОМАНДЫ ----------
proc cmdEnc*(args: seq[string]) =
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

proc cmdCls*() =
  eraseScreen()
  setCursorPos(0, 0)

proc cmdPing*(args: seq[string]) =
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

proc cmdIp*() =
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

proc cmdFch*(args: seq[string]) =
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
  
  # Пробуем httpclient
  try:
    let client = newHttpClient()
    client.timeout = 30000
    let response = client.get(url)
    if response.code == Http200:
      putEnv(varName, response.body)
      echo "> Ok. Content saved to ", varName, "."
      return
  except:
    discard
  
  # Пробуем PowerShell
  try:
    let tempFile = getTempDir() / "miceshell_temp.txt"
    let cmd = "powershell -Command \"[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '" & url & "' -OutFile '" & tempFile & "'\""
    let exitCode = execCmd(cmd)
    if exitCode == 0:
      let content = readFile(tempFile)
      putEnv(varName, content)
      removeFile(tempFile)
      echo "> Ok. Content saved to ", varName, "."
      return
  except:
    discard
  
  echo "> Error: could not fetch content"

proc cmdDwn*(args: seq[string]) =
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
  
  # Способ 1: httpclient
  try:
    let client = newHttpClient()
    client.timeout = 30000
    let response = client.get(url)
    if response.code == Http200:
      writeFile(filePath, response.body)
      echo "> Ok. [", filePath, "]"
      return
  except:
    discard
  
  # Способ 2: PowerShell с TLS 1.2
  try:
    let cmd = "powershell -Command \"[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12; Invoke-WebRequest -Uri '" & url & "' -OutFile '" & filePath & "'\""
    let exitCode = execCmd(cmd)
    if exitCode == 0:
      echo "> Ok. [", filePath, "]"
      return
  except:
    discard
  
  # Способ 3: curl
  try:
    let exitCode = execCmd("curl -L -o \"" & filePath & "\" \"" & url & "\"")
    if exitCode == 0:
      echo "> Ok. [", filePath, "]"
      return
  except:
    discard
  
  # Способ 4: certutil (Windows)
  try:
    let cmd = "certutil -urlcache -split -f \"" & url & "\" \"" & filePath & "\""
    let exitCode = execCmd(cmd)
    if exitCode == 0:
      echo "> Ok. [", filePath, "]"
      return
  except:
    discard
  
  echo "> Error: all download methods failed"

proc cmdOutln*(args: seq[string]) =
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

proc cmdHelp*() =
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
  echo "  sys               System information"
  echo "  mice              Nothing... <3"

proc cmdExit*() =
  echo "> Exited with Code::0"
  quit(0)

proc cmdCd*(args: seq[string]) =
  if args.len == 0:
    echo "> Error: specify path"
    return
  try:
    setCurrentDir(args[0])
    echo "> Ok [", getCurrentDir(), "]"
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdWin*() =
  echo "> ", getCurrentDir()

proc cmdCrt*(args: seq[string]) =
  if args.len == 0:
    echo "> Error: specify folder name"
    return
  try:
    createDir(args[0])
    echo "> Ok. [", getCurrentDir() / args[0], "]"
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdRmf*(args: seq[string]) =
  if args.len == 0:
    echo "> Error: specify folder name"
    return
  try:
    removeDir(args[0])
    echo "> Ok. [", getCurrentDir() / args[0], "]"
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdNew*(args: seq[string]) =
  if args.len == 0:
    echo "> Error: specify file name"
    return
  try:
    writeFile(args[0], "")
    echo "> Ok. [", getCurrentDir() / args[0], "]"
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdDlf*(args: seq[string]) =
  if args.len == 0:
    echo "> Error: specify file name"
    return
  try:
    removeFile(args[0])
    echo "> Ok. [", getCurrentDir() / args[0], "]"
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdGls*(args: seq[string]) =
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

proc cmdAnl*(args: seq[string]) =
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

proc cmdEfl*(args: seq[string]) =
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

proc cmdChg*(args: seq[string]) =
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

proc cmdFl*(args: seq[string]) =
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

proc cmdTree*(args: seq[string]) =
  let path = if args.len > 0: args[0] else: "."
  try:
    for kind, dir in walkDir(path):
      if kind == pcDir:
        echo "> 📁 ", extractFilename(dir)
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdFt*(args: seq[string]) =
  let path = if args.len > 0: args[0] else: "."
  try:
    for kind, item in walkDir(path):
      if kind == pcDir:
        echo "> 📁 ", extractFilename(item)
      else:
        echo "> 📄 ", extractFilename(item)
  except:
    echo "> Error: ", getCurrentExceptionMsg()

proc cmdSys*() =
  echo "> OS: ", hostOS
  echo "> CPU: ", hostCPU
  echo "> Nim version: ", NimVersion
  echo "> Current encoding: ", currentEncoding
  echo "> Current dir: ", getCurrentDir()
  echo "> User: ", getEnv("USERNAME")
  echo "> Computer: ", getEnv("COMPUTERNAME")

proc cmdMice*() =
  echo "> on venus"

proc cmdTechno*() =
  echo "> Technoblade never dies... 🥀"

proc cmdNotch*() =
  echo "                                               /|"
  echo "> No, I can't throw an apple in the console.../ |  <-- This is a fishing rod 😅"
  echo "                                                |"
  echo "                                                |"
  echo "                                                |"
  echo "                                               .?"
  echo "                                               🍎"

# ---------- ЭКСПОРТ ВСЕХ КОМАНД ----------
export cmdEnc, cmdCls, cmdPing, cmdIp, cmdFch, cmdDwn, cmdOutln
export cmdHelp, cmdExit, cmdCd, cmdWin, cmdCrt, cmdRmf, cmdNew, cmdDlf
export cmdGls, cmdAnl, cmdEfl, cmdChg, cmdFl, cmdTree, cmdFt
export cmdSys, cmdMice, cmdTechno, cmdNotch