Output docs/dashboard.gif
Set Shell zsh
Set FontSize 14
Set Width 908
Set Height 448
Set Padding 12
Set Framerate 15
Hide
Type "~/loom/docs/dashboard_driver.sh db >/dev/null 2>&1 & tmux kill-session -t db 2>/dev/null; tmux new-session -d -s db -x 100 -y 28 ~/loom/bin/dashboard; tmux set -t db status off; tmux setw -t db window-size manual; clear; tmux attach -t db"
Enter
Sleep 1
Show
Sleep 25
Hide
Sleep 1
