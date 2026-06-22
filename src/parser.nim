import strutils, winim/lean, tables, os

type
  TokenKind* = enum
    tkIdent, tkString, tkUrl, tkPath, tkColon, tkQuestion
    tkLParen, tkRParen, tkAnd, tkOr, tkPress, tkEOF

  Token* = object
    kind*: TokenKind
    value*: string
    pos*: int

  AstNodeKind* = enum
    nodeCommand, nodeCondition, nodeParen, nodeBinaryOp, nodeString, nodePath, nodeUrl

  AstNode* = ref object
    kind*: AstNodeKind
    raw*: string
    cmd*: string
    args*: seq[AstNode]
    condition*: AstNode
    trueBranch*: AstNode
    falseBranch*: AstNode
    left*: AstNode
    right*: AstNode
    op*: string
    expr*: AstNode

# ---------- ЛЕКСЕР ----------
proc tokenize(input: string): seq[Token] =
  var i = 0
  var tokens: seq[Token] = @[]
  
  while i < input.len:
    let ch = input[i]
    
    if ch in Whitespace:
      inc i
      continue
    
    elif ch == '(':
      tokens.add(Token(kind: tkLParen, value: "(", pos: i))
      inc i
    elif ch == ')':
      tokens.add(Token(kind: tkRParen, value: ")", pos: i))
      inc i
    elif ch == ':':
      tokens.add(Token(kind: tkColon, value: ":", pos: i))
      inc i
    elif ch == '?':
      tokens.add(Token(kind: tkQuestion, value: "?", pos: i))
      inc i
    
    elif ch == '"' or ch == '{':
      let quote = ch
      inc i
      var start = i
      while i < input.len and input[i] != quote:
        inc i
      let str = input[start..<i]
      tokens.add(Token(kind: tkString, value: str, pos: start))
      if i < input.len and input[i] == quote:
        inc i
    
    elif i + 4 < input.len and (input[i..i+4] == "http:" or (i+5 < input.len and input[i..i+5] == "https:")):
      var start = i
      while i < input.len and input[i] notin Whitespace and input[i] != ')' and input[i] != '(':
        inc i
      let url = input[start..<i]
      tokens.add(Token(kind: tkUrl, value: url, pos: start))
    
    elif i + 5 < input.len and input[i..i+4] == "press":
      var start = i
      while i < input.len and input[i] notin Whitespace and input[i] != '(' and input[i] != ')':
        inc i
      let press = input[start..<i]
      tokens.add(Token(kind: tkPress, value: press, pos: start))
    
    elif i + 2 < input.len and input[i..i+2] == "and":
      tokens.add(Token(kind: tkAnd, value: "and", pos: i))
      inc i, 3
    
    elif i + 1 < input.len and input[i..i+1] == "or":
      tokens.add(Token(kind: tkOr, value: "or", pos: i))
      inc i, 2
    
    else:
      var start = i
      while i < input.len and input[i] notin Whitespace and input[i] != '(' and input[i] != ')' and input[i] != ':' and input[i] != '?':
        inc i
      let word = input[start..<i]
      
      if word in ["dwn", "outln", "cd", "fl", "tree", "ft", "win", "crt", "rmf", "new", "dlf", "efl", "anl", "gls", "chg", "fch", "ping", "ip", "enc", "cls", "history", "ch", "load", "takes", "sys", "mice"]:
        tokens.add(Token(kind: tkIdent, value: word, pos: start))
      elif word.startsWith("http://") or word.startsWith("https://"):
        tokens.add(Token(kind: tkUrl, value: word, pos: start))
      else:
        tokens.add(Token(kind: tkPath, value: word, pos: start))
  
  tokens.add(Token(kind: tkEOF, value: "", pos: input.len))
  return tokens

# ---------- ПАРСЕР ----------
type Parser = object
  tokens: seq[Token]
  pos: int

proc current(p: Parser): Token =
  if p.pos < p.tokens.len:
    return p.tokens[p.pos]
  return Token(kind: tkEOF, value: "", pos: -1)

proc next(p: var Parser): Token =
  let tok = current(p)
  inc p.pos
  return tok

proc expect(p: var Parser, kind: TokenKind): bool =
  if current(p).kind == kind:
    discard next(p)
    return true
  return false

# ---------- ПАРСИНГ ----------
proc parsePrimary(p: var Parser): AstNode
proc parseAnd(p: var Parser): AstNode
proc parseOr(p: var Parser): AstNode

proc parsePrimary(p: var Parser): AstNode =
  let tok = current(p)
  
  case tok.kind
  of tkLParen:
    discard next(p)
    let expr = parseOr(p)
    if not expect(p, tkRParen):
      return nil
    let node = AstNode(kind: nodeParen)
    node.expr = expr
    node.raw = "(" & expr.raw & ")"
    return node
  
  of tkPress:
    let press = next(p).value
    return AstNode(kind: nodeParen, raw: press)
  
  of tkIdent:
    let cmd = next(p).value
    
    if cmd == "takes":
      return nil
    
    var args: seq[AstNode] = @[]
    var raw = cmd
    
    while true:
      let nextTok = current(p)
      case nextTok.kind
      of tkString, tkPath, tkUrl:
        let val = next(p).value
        let argNode = AstNode(kind: nodeParen)
        argNode.raw = val
        args.add(argNode)
        raw.add(" " & val)
      of tkColon:
        let colon = next(p).value
        let argNode = AstNode(kind: nodeParen)
        argNode.raw = colon
        args.add(argNode)
        raw.add(" " & colon)
      of tkQuestion, tkRParen, tkEOF:
        break
      else:
        discard next(p)
    
    let node = AstNode(kind: nodeCommand)
    node.cmd = cmd
    node.args = args
    node.raw = raw
    return node
  
  of tkString:
    let val = next(p).value
    let node = AstNode(kind: nodeString)
    node.raw = val
    return node
  
  of tkPath:
    let val = next(p).value
    let node = AstNode(kind: nodePath)
    node.raw = val
    return node
  
  of tkUrl:
    let val = next(p).value
    let node = AstNode(kind: nodeUrl)
    node.raw = val
    return node
  
  else:
    return nil

proc parseAnd(p: var Parser): AstNode =
  var left = parsePrimary(p)
  if left == nil:
    return nil
  
  while current(p).kind == tkAnd:
    discard next(p)
    let right = parsePrimary(p)
    if right == nil:
      return left
    let node = AstNode(kind: nodeBinaryOp)
    node.op = "and"
    node.left = left
    node.right = right
    node.raw = left.raw & " and " & right.raw
    left = node
  
  return left

proc parseOr(p: var Parser): AstNode =
  var left = parseAnd(p)
  if left == nil:
    return nil
  
  while current(p).kind == tkOr:
    discard next(p)
    let right = parseAnd(p)
    if right == nil:
      return left
    let node = AstNode(kind: nodeBinaryOp)
    node.op = "or"
    node.left = left
    node.right = right
    node.raw = left.raw & " or " & right.raw
    left = node
  
  return left

proc parseExpression(p: var Parser): AstNode =
  let tok = current(p)
  
  case tok.kind
  of tkLParen:
    discard next(p)
    let expr = parseOr(p)
    if not expect(p, tkRParen):
      return nil
    let node = AstNode(kind: nodeParen)
    node.expr = expr
    node.raw = "(" & expr.raw & ")"
    return node
  else:
    return parsePrimary(p)

# ---------- TAKES ----------
proc parseTakes(p: var Parser): AstNode =
  let cmdTok = current(p)
  if cmdTok.kind != tkIdent or cmdTok.value != "takes":
    return nil
  discard next(p)
  
  var raw = "takes"
  
  let condition = parseOr(p)
  if condition == nil:
    return nil
  raw.add(" " & condition.raw)
  
  if not expect(p, tkQuestion):
    return nil
  raw.add(" ? ")
  
  let trueBranch = parseExpression(p)
  if trueBranch == nil:
    return nil
  raw.add(trueBranch.raw)
  
  if not expect(p, tkColon):
    return nil
  raw.add(" : ")
  
  let falseBranch = parseExpression(p)
  if falseBranch == nil:
    return nil
  raw.add(falseBranch.raw)
  
  let node = AstNode(kind: nodeCondition)
  node.condition = condition
  node.trueBranch = trueBranch
  node.falseBranch = falseBranch
  node.raw = raw
  return node

# ---------- ПУБЛИЧНЫЙ API ----------
proc parseScript*(content: string): seq[AstNode] =
  let tokens = tokenize(content)
  var p = Parser(tokens: tokens, pos: 0)
  var nodes: seq[AstNode] = @[]
  
  while p.pos < p.tokens.len:
    let tok = current(p)
    if tok.kind == tkEOF:
      break
    
    if tok.kind == tkIdent and tok.value == "takes":
      let node = parseTakes(p)
      if node != nil:
        nodes.add(node)
        continue
    
    let node = parseExpression(p)
    if node != nil:
      nodes.add(node)
      continue
    
    discard next(p)
  
  return nodes

# ---------- ИСПОЛНЕНИЕ ----------
var execCommand*: proc(input: string) {.closure.}

proc evalCondition(node: AstNode): bool =
  case node.kind
  of nodeParen:
    if node.expr != nil:
      return evalCondition(node.expr)
    
    if node.raw.startsWith("press."):
      let key = node.raw[6..^1]
      let vk = case key
        of "Y": 0x59
        of "L_SHIFT": 0xA0
        of "R_SHIFT": 0xA1
        of "CTRL", "L_CTRL": 0xA2
        of "R_CTRL": 0xA3
        of "ALT", "L_ALT": 0xA4
        of "R_ALT": 0xA5
        else: 0
      if vk != 0:
        echo "> Press key: ", key
        var pressed = false
        var attempts = 0
        while attempts < 1000:
          if (GetAsyncKeyState(vk.int32) and 0x8000) != 0:
            pressed = true
            break
          attempts += 1
          sleep(10)
        return pressed
      return false
    return false
  
  of nodeBinaryOp:
    if node.op == "and":
      # Собираем все press из условия
      var keys: seq[string] = @[]
      
      proc collectPresses(n: AstNode) =
        if n.kind == nodeParen and n.raw.startsWith("press."):
          keys.add(n.raw[6..^1])
        elif n.kind == nodeBinaryOp and n.op == "and":
          collectPresses(n.left)
          collectPresses(n.right)
      
      collectPresses(node)
      
      if keys.len == 0:
        return false
      
      echo "> Press ", keys.join(" + "), " simultaneously..."
      
      var allPressed = false
      var attempts = 0
      while attempts < 1000:
        var pressedCount = 0
        for key in keys:
          let vk = case key
            of "Y": 0x59
            of "L_SHIFT": 0xA0
            of "R_SHIFT": 0xA1
            of "CTRL", "L_CTRL": 0xA2
            of "R_CTRL": 0xA3
            of "ALT", "L_ALT": 0xA4
            of "R_ALT": 0xA5
            else: 0
          if vk != 0 and (GetAsyncKeyState(vk.int32) and 0x8000) != 0:
            pressedCount += 1
        if pressedCount == keys.len:
          allPressed = true
          break
        attempts += 1
        sleep(10)
      
      return allPressed
      
    elif node.op == "or":
      return evalCondition(node.left) or evalCondition(node.right)
    else:
      return false
  
  else:
    return false

proc nodeToString(node: AstNode): string =
  case node.kind
  of nodeCommand:
    result = node.cmd
    for arg in node.args:
      result.add(" " & arg.raw)
  of nodeParen:
    if node.expr != nil:
      return nodeToString(node.expr)
    else:
      return node.raw
  of nodeBinaryOp:
    return nodeToString(node.left) & " " & node.op & " " & nodeToString(node.right)
  of nodeString, nodePath, nodeUrl:
    return node.raw
  else:
    return node.raw

proc execScript*(nodes: seq[AstNode]) =
  for node in nodes:
    case node.kind
    of nodeCommand:
      var cmdLine = node.cmd
      for arg in node.args:
        cmdLine.add(" " & arg.raw)
      if execCommand != nil:
        execCommand(cmdLine)
    
    of nodeCondition:
      let result = evalCondition(node.condition)
      
      if result:
        echo "> [condition true]"
        execScript(@[node.trueBranch])
      else:
        echo "> [condition false]"
        execScript(@[node.falseBranch])
    
    of nodeBinaryOp:
      if execCommand != nil:
        execCommand(node.raw)
    
    of nodeParen:
      if node.expr != nil:
        execScript(@[node.expr])
      else:
        if node.raw.len > 0 and execCommand != nil:
          execCommand(node.raw)
    
    of nodeString, nodePath, nodeUrl:
      if execCommand != nil and node.raw.len > 0:
        execCommand(node.raw)