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
                    
                    var scriptPath = "/home/adam/dev/oss/podcast/scripts/add-seconds.fish"
                    
                    // 2. Wrap command in bash to write output to file. 
                    // This explicitly prevents backgrounded clipboard utilities (e.g. wl-copy) from inheriting QProcess' open standard file descriptors!
                    var cmd = "bash -c 'echo \"" + offset + "\" > ~/.cache/add_seconds_offset; " 
                            + scriptPath + " " + offset + " > ~/.cache/add_seconds_widget.out 2> ~/.cache/add_seconds_widget.err; "
                            + "RET=$?; cat ~/.cache/add_seconds_widget.out; cat ~/.cache/add_seconds_widget.err >&2; exit $RET'"

                    logger.log("Executing script: " + scriptPath + " with offset: " + offset)
                    
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
            if (stdout) { logger.log("STDOUT: " + stdout) }
            if (stderr) { logger.log("STDERR: " + stderr) }

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
            // Write to a logical place for widget logs
            var timestamp = new Date().toISOString()
            var escapedMsg = msg.toString().replace(/'/g, "'\\''")
            connectSource("echo '" + timestamp + " - " + escapedMsg + "' >> ~/.cache/add_seconds_widget.log")
        }
    }
}
