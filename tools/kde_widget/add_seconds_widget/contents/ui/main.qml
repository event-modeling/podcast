import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents

Item {
    id: root

    // Tell plasma we want a compact representation (an icon) that opens into a full representation
    Plasmoid.preferredRepresentation: Plasmoid.compactRepresentation

    Plasmoid.compactRepresentation: PlasmaComponents.Button {
        icon.name: "clock"
        onClicked: plasmoid.expanded = !plasmoid.expanded
        
        PlasmaComponents.ToolTip {
            text: "Add Seconds to Clipboard Timestamps"
        }
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
                    if (offset === "") {
                        statusLabel.text = "Please enter an offset."
                        statusLabel.color = PlasmaCore.Theme.negativeTextColor
                        return
                    }
                    
                    statusLabel.text = "Running..."
                    statusLabel.color = PlasmaCore.Theme.textColor
                    
                    // Single-quote the offset to prevent shell injection, though it should be parsed securely 
                    var scriptPath = "/home/adam/dev/oss/podcast/scripts/add-seconds.fish"
                    var cmd = "echo '" + offset + "' > ~/.cache/add_seconds_offset && " + scriptPath + " " + offset
                    executable.exec(cmd)
                    plasmoid.expanded = false
                }
            }

            PlasmaComponents.Label {
                id: statusLabel
                text: ""
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
            var stdout = data["stdout"]
            var stderr = data["stderr"]

            // Log exit details to the UI
            if (exitCode === 0) {
                statusLabel.text = "Success!"
                statusLabel.color = PlasmaCore.Theme.positiveTextColor
            } else {
                statusLabel.text = "Error " + exitCode + ":\n" + (stderr ? stderr : stdout)
                statusLabel.color = PlasmaCore.Theme.negativeTextColor
            }
            
            // Disconnect so we don't re-trigger on subsequent updates 
            disconnectSource(sourceName)
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
            var stdout = data["stdout"]
            if (stdout) {
                var previousOffset = stdout.trim()
                if (previousOffset !== "") {
                    offsetInput.text = previousOffset
                }
            }
            disconnectSource(sourceName)
        }

        Component.onCompleted: {
            connectSource("cat ~/.cache/add_seconds_offset 2>/dev/null || true")
        }
    }
}
