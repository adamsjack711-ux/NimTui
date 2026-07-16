# shared tmux input-injection helpers for the demo gif drivers
raw() { local h=$(printf '%s' "$1" | xxd -p | tr -d '\n' | sed 's/../& /g'); tmux send-keys -t $S -H ${=h}; }
click()  { raw $'\e[<0;'"$1;$2M"; sleep 0.06; raw $'\e[<0;'"$1;$2m"; }
press()  { raw $'\e[<0;'"$1;$2M"; }
motion() { raw $'\e[<32;'"$1;$2M"; }
release(){ raw $'\e[<0;'"$1;$2m"; }
wheeldn(){ raw $'\e[<65;'"$1;$2M"; }
