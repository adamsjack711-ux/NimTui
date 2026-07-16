Output docs/chess.gif
Set Shell zsh
Set FontSize 14
Set Width 908
Set Height 490
Set Padding 12
Set Framerate 15
Hide
Type "~/loom/docs/chess_driver.sh cg >/dev/null 2>&1 & tmux kill-session -t cg 2>/dev/null; tmux new-session -d -s cg -x 100 -y 28 ~/loom/bin/chess; tmux set -t cg status off; tmux setw -t cg window-size manual; clear; tmux attach -t cg"
Enter
Sleep 1
Show
Sleep 16
Hide
Sleep 1
