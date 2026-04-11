#!/usr/bin/env fish

echo (date "+%Y-%m-%d %H:%M:%S")" - add-seconds.fish invoked with args: $argv" >>~/add-seconds.log

# Detect display environment
set -l is_x true
if set -q WAYLAND_DISPLAY
    set is_x false
end

# Clipboard functions for Wayland
function get_using_wl
    wl-paste -n 2>/dev/null
end

function set_using_wl
    wl-copy >/dev/null 2>&1
end

# Clipboard functions for X11
function get_using_x
    xclip -selection clipboard -o 2>/dev/null
end

function set_using_x
    xclip -selection clipboard >/dev/null 2>&1
end

# Add a time offset (in seconds) to a timestamp string (MM:SS or HH:MM:SS)
function add_time -a timestamp offset
    set -l parts (string split ':' "$timestamp")
    set -l h 0
    set -l m 0
    set -l s 0

    if test (count $parts) -eq 3
        set h $parts[1]
        set m $parts[2]
        set s $parts[3]
    else
        set m $parts[1]
        set s $parts[2]
    end

    set -l total (math "$h * 3600 + $m * 60 + $s + $offset")
    if test $total -lt 0
        set total 0
    end

    set -l nh (math "floor($total / 3600)")
    set -l nm (math "floor(($total % 3600) / 60)")
    set -l ns (math "$total % 60")

    if test $nh -gt 0
        printf "%02d:%02d:%02d" $nh $nm $ns
    else
        printf "%02d:%02d" $nm $ns
    end
end

# --- Main execution ---

# Get clipboard content (each line becomes an array element)
set -l content
if test "$is_x" = true
    set content (get_using_x)
else
    set content (get_using_wl)
end

if test (count $content) -eq 0
    echo "Error: Could not read from clipboard (is it empty?)"
    exit 1
end

# Get offset from args or prompt
if test -n "$argv[1]"
    set offset $argv[1]
else
    read -P "Enter seconds offset (e.g., 18 or -10): " offset
end

# Validate offset
if not string match -qr '^-?[0-9]+$' -- "$offset"
    echo "Error: Offset must be an integer."
    exit 1
end

# Process content line by line, adjusting all timestamps
set -l processed
for line in $content
    set -l result "$line"
    for match in (string match -ra '(?:[0-9]+:)?[0-9]+:[0-9]+' "$line")
        set -l new_ts (add_time "$match" "$offset")
        set result (string replace "$match" "$new_ts" "$result")
    end
    set -a processed "$result"
end

# Set clipboard content (printf preserves newlines between array elements)
if test "$is_x" = true
    printf '%s\n' $processed | set_using_x
else
    printf '%s\n' $processed | set_using_wl
end
set -l copy_status $status

if test $copy_status -eq 0
    echo "Clipboard updated successfully."
else
    echo "Error: Failed to update clipboard."
    exit 1
end
