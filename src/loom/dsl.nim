## The declarative widget-tree macro. Turns nested block-calls into
## constructor calls plus `add` — plain Nim control flow (`if`, `case`,
## `for`, `while`, `let`) works anywhere inside.
##
## ```nim
## let root = tui:
##   vbox(gap = 1):
##     panel(title = "Stats"):
##       gauge(cpu.get, label = "cpu")
##     for name in items:
##       text(name)
## ```

import std/macros

proc isBlockCall(n: NimNode): bool =
  n.kind in {nnkCall, nnkCommand} and n.len >= 2 and
    n[n.len - 1].kind == nnkStmtList

proc transformExpr(n: NimNode): NimNode

proc transformBody(parent: NimNode, body: NimNode): NimNode =
  result = newStmtList()
  for st in body:
    case st.kind
    of nnkLetSection, nnkVarSection, nnkConstSection, nnkAsgn,
       nnkDiscardStmt, nnkCommentStmt, nnkProcDef, nnkFuncDef:
      result.add st
    of nnkForStmt:
      var f = copyNimTree(st)
      f[f.len - 1] = transformBody(parent, st[st.len - 1])
      result.add f
    of nnkWhileStmt:
      var w = copyNimTree(st)
      w[1] = transformBody(parent, st[1])
      result.add w
    of nnkIfStmt, nnkWhenStmt:
      var ifn = newNimNode(st.kind)
      for branch in st:
        var b = copyNimTree(branch)
        b[b.len - 1] = transformBody(parent, branch[branch.len - 1])
        ifn.add b
      result.add ifn
    of nnkCaseStmt:
      var cs = newNimNode(nnkCaseStmt)
      cs.add st[0]
      for j in 1 ..< st.len:
        var b = copyNimTree(st[j])
        b[b.len - 1] = transformBody(parent, st[j][st[j].len - 1])
        cs.add b
      result.add cs
    of nnkBlockStmt:
      var bl = copyNimTree(st)
      bl[1] = transformBody(parent, st[1])
      result.add bl
    of nnkStmtList:
      result.add transformBody(parent, st)
    else:
      # Any other expression is a child widget.
      result.add newCall(ident"add", parent, transformExpr(st))

proc transformExpr(n: NimNode): NimNode =
  if isBlockCall(n):
    let tmp = genSym(nskLet, "loomWidget")
    var call = copyNimTree(n)
    let body = call[call.len - 1]
    call.del(call.len - 1)
    var stmts = newStmtList()
    stmts.add newLetStmt(tmp, call)
    stmts.add transformBody(tmp, body)
    stmts.add tmp
    newTree(nnkBlockStmt, newEmptyNode(), stmts)
  else:
    n

macro tui*(body: untyped): untyped =
  ## Build a widget tree declaratively. The last statement is the root
  ## widget; earlier statements (lets, helper code) pass through untouched.
  expectKind body, nnkStmtList
  var stmts = newStmtList()
  for j in 0 ..< body.len - 1:
    stmts.add body[j]
  stmts.add transformExpr(body[body.len - 1])
  newTree(nnkBlockStmt, newEmptyNode(), stmts)
