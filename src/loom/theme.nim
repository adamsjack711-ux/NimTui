## Themes: named style sets that widgets fall back to when no explicit
## style is given. The active theme lives in a signal, so `setTheme`
## repaints everything that reads it — no manual invalidation.

import style, reactive

type
  Theme* = object
    name*: string
    border*: Style        ## panel/box borders
    title*: Style         ## panel titles
    dim*: Style           ## rules, scrollbars, secondary text
    placeholder*: Style   ## empty-input hint text
    selection*: Style     ## focused list selection / active tab
    selectionUnfocused*: Style
    tabInactive*: Style
    accent*: Color        ## sparklines and similar
    gaugeLow*, gaugeMid*, gaugeHigh*: Color

const
  themeDefault* = Theme(
    name: "default",
    border: Style(),
    title: Style(attrs: {aBold}),
    dim: Style(fg: clBrightBlack),
    placeholder: Style(fg: clBrightBlack, attrs: {aItalic}),
    selection: Style(attrs: {aReverse}),
    selectionUnfocused: Style(attrs: {aReverse, aDim}),
    tabInactive: Style(attrs: {aDim}),
    accent: clCyan,
    gaugeLow: clGreen, gaugeMid: clYellow, gaugeHigh: clRed)

  themeMono* = Theme(
    name: "mono",
    border: Style(),
    title: Style(attrs: {aBold}),
    dim: Style(attrs: {aDim}),
    placeholder: Style(attrs: {aDim, aItalic}),
    selection: Style(attrs: {aReverse}),
    selectionUnfocused: Style(attrs: {aReverse, aDim}),
    tabInactive: Style(attrs: {aDim}),
    accent: defaultColor,
    gaugeLow: defaultColor, gaugeMid: defaultColor, gaugeHigh: defaultColor)

  themeNeon* = Theme(
    name: "neon",
    border: Style(fg: Color(kind: ckC256, idx: 60)),
    title: Style(fg: Color(kind: ckC256, idx: 213), attrs: {aBold}),
    dim: Style(fg: Color(kind: ckC256, idx: 60)),
    placeholder: Style(fg: Color(kind: ckC256, idx: 60), attrs: {aItalic}),
    selection: Style(fg: Color(kind: ckC256, idx: 201), attrs: {aReverse}),
    selectionUnfocused: Style(fg: Color(kind: ckC256, idx: 96),
                              attrs: {aReverse}),
    tabInactive: Style(fg: Color(kind: ckC256, idx: 60)),
    accent: Color(kind: ckC256, idx: 51),
    gaugeLow: Color(kind: ckC256, idx: 84),
    gaugeMid: Color(kind: ckC256, idx: 220),
    gaugeHigh: Color(kind: ckC256, idx: 197))

var themeSig = signal(themeDefault)

proc theme*(): Theme =
  ## The active theme. Reading it inside a render pass subscribes the
  ## frame to theme changes.
  themeSig.get

proc setTheme*(t: Theme) =
  themeSig.set t

proc mergeStyle*(base, over: Style): Style =
  ## `over` wins where it says something; `base` fills the gaps.
  result = base
  if over.fg != defaultColor: result.fg = over.fg
  if over.bg != defaultColor: result.bg = over.bg
  result.attrs = base.attrs + over.attrs
