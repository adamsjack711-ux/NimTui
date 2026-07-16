#!/bin/zsh
# Drives the journal example inside tmux for the hero gif (docs/journal.tape).
# Coordinates assume a 100x28 window.
S=${1:-jg}
source ~/loom/docs/gif_lib.sh

sleep 3                          # hero hold on the rich markdown note
wheeldn 60 14; sleep 0.5         # scroll the preview with the wheel
wheeldn 60 14; sleep 0.5
wheeldn 60 14; sleep 1.2
click 10 12; sleep 1.8           # click "markdown cheatsheet" in the tree
wheeldn 60 14; sleep 0.4
wheeldn 60 14; sleep 0.4
wheeldn 60 14; sleep 0.4
wheeldn 60 14; sleep 1.5
click 44 4; sleep 1.8            # raw tab
click 35 4; sleep 1.2            # back to preview
click 10 6; sleep 0.8            # select the 2026-07 folder
tmux send-keys -t $S Enter; sleep 1.2   # fold
tmux send-keys -t $S Enter; sleep 1.0   # unfold
click 15 27; sleep 0.6           # focus the quick-capture bar
tmux send-keys -t $S -l "ship the demos"; sleep 0.9
tmux send-keys -t $S Enter; sleep 1.8   # capture lands in the inbox
tmux send-keys -t $S Tab; sleep 0.3     # focus back to the tree
tmux send-keys -t $S t; sleep 2.4       # neon theme
tmux send-keys -t $S q
