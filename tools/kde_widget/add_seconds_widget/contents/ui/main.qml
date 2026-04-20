import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents

Item {
    id: root

    property string statusText: ""
    property color statusColor: PlasmaCore.Theme.textColor
    property string savedOffset: ""

    readonly property string fishScript: `#!/usr/bin/env fish

mkdir -p ~/.local/state/org.kde.plasma.addseconds
echo (date "+%Y-%m-%d %H:%M:%S")" - add-seconds.fish invoked via inlined QML script with args: $argv" >>~/.local/state/org.kde.plasma.addseconds/add-seconds.log

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
`

    // Tell plasma we want a compact representation (an icon) that opens into a full representation
    Plasmoid.preferredRepresentation: Plasmoid.compactRepresentation

    Plasmoid.compactRepresentation: PlasmaComponents.Button {
        icon.name: "clock"
        onClicked: plasmoid.expanded = !plasmoid.expanded
        
    }

    Plasmoid.fullRepresentation: Item {
        Layout.minimumWidth: 250
        Layout.minimumHeight: 180
        Layout.preferredWidth: 300
        Layout.preferredHeight: 200

        ColumnLayout {
            anchors.centerIn: parent
            anchors.margins: PlasmaCore.Units.largeSpacing
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaComponents.Label {
                text: "Add Seconds to Chapters in Clipboard"
                font.weight: Font.Bold
                Layout.alignment: Qt.AlignHCenter
            }

            PlasmaComponents.TextField {
                id: offsetInput
                text: root.savedOffset
                placeholderText: "e.g., 18 or -10"
                Layout.alignment: Qt.AlignHCenter
                Layout.fillWidth: true
                onAccepted: runButton.clicked()
            }

            PlasmaComponents.Button {
                id: runButton
                text: "Add Seconds"
                icon.name: "media-playback-start"
                Layout.alignment: Qt.AlignHCenter
                onClicked: {
                    var offset = offsetInput.text
                    
                    // 1. Validation Error Handling
                    try {
                        if (offset === "") {
                            root.statusText = "Please enter an offset."
                            root.statusColor = "red"
                            logger.log("Validation Error: User attempted to run with empty offset.")
                            return
                        }
                        if (!/^-?\d+$/.test(offset)) {
                            root.statusText = "Offset must be a valid integer."
                            root.statusColor = "red"
                            logger.log("Validation Error: User entered invalid offset: " + offset)
                            return
                        }
                        
                        root.statusText = "Running..."
                        root.statusColor = "black"
                    } catch (err) {
                        logger.log("Framework Error updating UI during validation: " + err)
                    }
                    
                    // Prepare the inlined script execution
                    var escapedScript = root.fishScript.replace(/'/g, "'\\''")
                    var cmd = "bash -c 'TMP_DIR=$(mktemp -d /tmp/add_seconds_widget_XXXXXX); "
                            + "echo \"" + offset + "\" > ~/.cache/add_seconds_offset; "
                            + "cat << \"EOF\" > $TMP_DIR/script.fish\n"
                            + escapedScript + "\nEOF\n"
                            + "chmod +x $TMP_DIR/script.fish; "
                            + "$TMP_DIR/script.fish " + offset + " > ~/.cache/add_seconds_widget.out 2> ~/.cache/add_seconds_widget.err; "
                            + "RET=$?; rm -rf $TMP_DIR; "
                            + "cat ~/.cache/add_seconds_widget.out; cat ~/.cache/add_seconds_widget.err >&2; exit $RET'"

                    logger.log("Executing inlined script with offset: " + offset)
                    console.log("AddSecondsWidget: Executing inlined script with offset: " + offset)
                    executable.exec(cmd)
                }
            }

            PlasmaComponents.Label {
                id: statusLabel
                text: root.statusText
                color: root.statusColor
                wrapMode: Text.WordWrap
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 250
            }
        }
    }

    PlasmaCore.DataSource {
        id: executable
        engine: "executable"
        connectedSources: []

        onNewData: {
            var exitCode = data["exit code"]
            var stdout = data["stdout"] ? data["stdout"].trim() : ""
            var stderr = data["stderr"] ? data["stderr"].trim() : ""

            // Disconnect immediately
            disconnectSource(sourceName)

            // 3. Execution Error Handling
            if (exitCode === undefined) {
                statusLabel.text = "Error: Widget failed to execute command."
                statusLabel.color = PlasmaCore.Theme.negativeTextColor
                logger.log("Critical Error: exitCode was undefined. Data source: " + sourceName)
                return
            }

            // Thorough Logging
            logger.log("Process Finished - Exit Code: " + exitCode)
            console.log("AddSecondsWidget: Process Finished - Exit Code: " + exitCode)
            if (stdout) { 
                logger.log("STDOUT: " + stdout)
                console.log("AddSecondsWidget: STDOUT: " + stdout)
            }
            if (stderr) { 
                logger.log("STDERR: " + stderr) 
                console.log("AddSecondsWidget: STDERR: " + stderr)
            }

            // Log exit details to the UI
            try {
                if (exitCode === 0) {
                    logger.log("Success!")
                    root.statusText = "Success!"
                    root.statusColor = "green"
                    logger.log("marked as success")
                } else {
                    var errorMsg = stderr ? stderr : (stdout ? stdout : "Unknown Error");
                    logger.log("Error message: " + errorMsg)
                    root.statusText = "Error " + exitCode + ":\n" + errorMsg
                    root.statusColor = "red"
                    logger.log("marked as error")
                }
            } catch (err) {
                logger.log("Framework Error updating UI: " + err)
                try {
                    root.statusText = exitCode === 0 ? "Success!" : "Error!";
                    root.statusColor = exitCode === 0 ? "green" : "red";
                } catch (fallbackErr) {
                    logger.log("Fallback UI update also failed: " + fallbackErr)
                }
            }
        }

        function exec(cmd) {
            connectSource(cmd)
        }
    }

    PlasmaCore.DataSource {
        id: cacheReader
        engine: "executable"
        connectedSources: []

        onNewData: {
            logger.log("about to read cache")
            try {
            var exitCode = data["exit code"]
            var stdout = data["stdout"] ? data["stdout"].trim() : ""
            var stderr = data["stderr"] ? data["stderr"].trim() : ""
            } catch (err) {
                logger.log("Framework Error reading cache: " + err)
            }

            // Always gracefully disconnect
            try {
                logger.log("about to disconnect source")
                disconnectSource(sourceName)
            } catch (err) {
                logger.log("Framework Error disconnecting source: " + err)
            }
            
            try {
                logger.log("CacheReader finished - exit code: " + exitCode + " | stdout: " + stdout + " | stderr: " + stderr)
                if (stdout !== "") {
                    root.savedOffset = stdout
                    logger.log("Successfully loaded cached offset: " + stdout)
                } else {
                    logger.log("Cache was empty or could not be read.")
                }
            } catch (err) {
                logger.log("Framework Error loading cache: " + err)
            }
        }

        Component.onCompleted: {
            connectSource("cat ~/.cache/add_seconds_offset 2>/dev/null || true")
        }
    }

    PlasmaCore.DataSource {
        id: logger
        engine: "executable"
        connectedSources: []

        onNewData: {
            disconnectSource(sourceName)
        }

        function log(msg) {
            // Write to a logical place for widget logs (XDG State Home)
            var timestamp = new Date().toISOString()
            var escapedMsg = msg.toString().replace(/'/g, "'\\''")
            connectSource("mkdir -p ~/.local/state/org.kde.plasma.addseconds && echo '" + timestamp + " - " + escapedMsg + "' >> ~/.local/state/org.kde.plasma.addseconds/add-seconds.log")
        }
    }
}
