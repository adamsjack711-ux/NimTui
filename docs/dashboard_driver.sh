#!/bin/zsh
# Drives the dashboard example inside tmux for the framework hero gif
# (docs/dashboard.tape). Coordinates assume a 100x28 window. Mouse capture
# is on by default in the dashboard.
#
# Note: the single-key shortcuts (t/m) are app-level onKey handlers, so they
# only fire when a text input is NOT focused (the input consumes letters).
# The driver cycles themes while the process list is focused, and only types
# into the filter afterwards.
S=${1:-db}
source ~/loom/docs/gif_lib.sh

typ() { for c in ${(s::)1}; do tmux send-keys -t $S -l "$c"; sleep 0.11; done }

sleep 4.3                        # hero hold: live gauges + sparkline filling

# live theme switching — one signal restyles the whole app.
# focus the process list first so 't' reaches the app shortcut, not the input.
tmux send-keys -t $S Tab; sleep 0.7
tmux send-keys -t $S t; sleep 2.1    # neon
tmux send-keys -t $S t; sleep 2.1    # mono
tmux send-keys -t $S t; sleep 1.3    # back to default

# keyboard + mouse selection over the live, PID-keyed process list
tmux send-keys -t $S Down Down Down; sleep 0.9
click 6 12; sleep 0.9
wheeldn 30 14; wheeldn 30 14; sleep 1.2

# reactive filtering — click into the filter, the count updates per keystroke
click 20 6; sleep 0.7
typ "claude"; sleep 1.9
tmux send-keys -t $S BSpace BSpace BSpace BSpace BSpace BSpace; sleep 1.3

# tabs + scrollable help viewport
click 14 4; sleep 1.6            # help tab
wheeldn 50 14; sleep 0.5
wheeldn 50 14; sleep 0.5
wheeldn 50 14; sleep 1.6
click 5 4; sleep 1.4             # back to overview

tmux send-keys -t $S q
