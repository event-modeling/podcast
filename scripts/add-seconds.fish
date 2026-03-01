#!/usr/bin/env fish

# Function to copy to clipboard with fallback
function copy_to_clipboard -a text
    set -l tools wl-copy "xclip -selection clipboard"
    # Prefer wl-copy if on Wayland
    if not set -q WAYLAND_DISPLAY
        set tools "xclip -selection clipboard" wl-copy
    end

    for tool in $tools
        # Attempt to copy
        echo -n "$text" | eval $tool 2>/dev/null
        
        # Verify if it worked by trying to paste it back
        set -l verify_cmd "xclip -selection clipboard -o"
        if string match -q "wl-copy" $tool
            set verify_cmd "wl-paste -n"
        end
        
        set -l pasted (eval $verify_cmd 2>/dev/null)
        if test "$pasted" = "$text"
            return 0
        end
    end
    return 1
end

# Function to get from clipboard with fallback
function get_from_clipboard
    set -l tools "wl-paste -n" "xclip -selection clipboard -o"
    if not set -q WAYLAND_DISPLAY
        set tools "xclip -selection clipboard -o" "wl-paste -n"
    end

    for tool in $tools
        set -l content (eval $tool 2>/dev/null | string collect)
        if test -n "$content"
            echo "$content"
            return 0
        end
    end
    return 1
end

# Main execution
set -l content (get_from_clipboard)
if test $status -ne 0
    echo "Error: Could not read from clipboard (is it empty?)"
    exit 1
end

read -P "Enter seconds offset (e.g., 18 or -10): " offset

# Validate offset
if not string match -qr '^-?[0-9]+$' -- "$offset"
    echo "Error: Offset must be an integer."
    exit 1
end

# Process content using awk
set -l processed (echo "$content" | awk -v offset="$offset" '
{
    line = $0
    while (match(line, /(([0-9]+):)?([0-9]+):([0-9]+)/, m)) {
        if (m[2] != "") { h = m[2]; m_val = m[3]; s = m[4] }
        else { h = 0; m_val = m[3]; s = m[4] }
        total = h * 3600 + m_val * 60 + s + offset
        if (total < 0) total = 0
        nh = int(total / 3600); nm = int((total % 3600) / 60); ns = total % 60
        if (nh > 0) { new_ts = sprintf("%02d:%02d:%02d", nh, nm, ns) }
        else { new_ts = sprintf("%02d:%02d", nm, ns) }
        ts_full = m[0]
        sub(ts_full, new_ts, line)
    }
    print line
}
' | string collect)

if copy_to_clipboard "$processed"
    echo "Clipboard updated successfully."
else
    echo "Error: Failed to update clipboard with any tool."
    exit 1
end
