#!/bin/zsh
# Drives the chess example inside tmux for the hero gif (docs/chess.tape).
# Plays Scholar's mate entirely with the mouse: click-click moves plus two
# drag-and-drops. Coordinates assume a 100x28 window; squares are 4x2 cells
# starting at column 3 (1-based col = 5 + 4*file, row = 16 - 2*rank).
S=${1:-cg}
source ~/loom/docs/gif_lib.sh

drag() {  # drag $1,$2 -> path... -> release on last point
  press $1 $2; shift 2
  while (( $# >= 2 )); do
    sleep 0.12; motion $1 $2
    local x=$1 y=$2; shift 2
    (( $# < 2 )) && release $x $y
  done
}

sleep 3                                   # hero hold on the fresh board
click 21 14; sleep 1.0                    # select e2 - legal dots appear
click 21 10; sleep 1.0                    # e4
click 21 4; sleep 0.6; click 21 8; sleep 0.9      # e5
drag 17 16 19 14 23 12 27 10 31 9 33 8; sleep 1.0 # Qd1-h5 by drag
click 9 2; sleep 0.5; click 13 6; sleep 0.9       # Nc6
drag 25 16 23 14 19 12 15 11 13 10; sleep 1.0     # Bf1-c4 by drag
click 29 2; sleep 0.5; click 25 6; sleep 0.9      # Nf6
click 33 8; sleep 1.2                     # select the queen - f7 flags red
click 25 4; sleep 3.2                     # Qxf7# checkmate
tmux send-keys -t $S q
