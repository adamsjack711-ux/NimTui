## Basic geometric primitives shared by the layout and rendering layers.

type
  Size* = object
    w*, h*: int

  Rect* = object
    x*, y*, w*, h*: int

proc size*(w, h: int): Size = Size(w: w, h: h)
proc rect*(x, y, w, h: int): Rect = Rect(x: x, y: y, w: w, h: h)

proc `==`*(a, b: Size): bool = a.w == b.w and a.h == b.h
proc `==`*(a, b: Rect): bool =
  a.x == b.x and a.y == b.y and a.w == b.w and a.h == b.h

proc right*(r: Rect): int = r.x + r.w
proc bottom*(r: Rect): int = r.y + r.h
proc isEmpty*(r: Rect): bool = r.w <= 0 or r.h <= 0

proc shrink*(r: Rect, n: int): Rect =
  ## Inset all four sides by `n`.
  rect(r.x + n, r.y + n, r.w - 2 * n, r.h - 2 * n)

proc intersect*(a, b: Rect): Rect =
  let x = max(a.x, b.x)
  let y = max(a.y, b.y)
  rect(x, y, min(a.right, b.right) - x, min(a.bottom, b.bottom) - y)

proc contains*(r: Rect, x, y: int): bool =
  x >= r.x and x < r.right and y >= r.y and y < r.bottom
