#!/usr/bin/env fish

set -l content (xclip -selection clipboard -o)
read -P "Enter seconds offset: " offset
string join \n $content | awk -v offset=$offset '/^[0-9]+:[0-9]+/ {split($1, t, ":"); total = t[1]*60 + t[2] + offset; mins = int(total/60); secs = total%60; $1 = sprintf("%02d:%02d", mins, secs)} 1' | xclip -selection clipboard
