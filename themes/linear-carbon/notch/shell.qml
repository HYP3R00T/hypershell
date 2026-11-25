import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: shell

    readonly property color frameColor: palette.frame
    readonly property int bezel: 5
    readonly property int screenRadius: 19
    property bool motionEnabled: false
    property bool themeActive: false
    readonly property ShellScreen targetScreen: Quickshell.screens[0] ?? null

    NotchPalette { id: palette }

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: shell.themeActive = text().trim() === "linear-carbon"
        onLoadFailed: shell.themeActive = false
    }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Process {
        id: checkMotion
        command: ["hyprctl", "-j", "getoption", "animations:enabled"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    shell.motionEnabled = JSON.parse(text).bool === true;
                } catch (_) {
                    shell.motionEnabled = false;
                }
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded")
                checkMotion.running = true;
        }
    }

    // Draw the bezel with a transparent interior so Omarchy owns wallpaper selection.
    PanelWindow {
        screen: shell.targetScreen
        visible: shell.themeActive
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        WlrLayershell.layer: WlrLayer.Bottom
        WlrLayershell.namespace: "omarchy-top-preview-frame"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        mask: Region {}

        Canvas {
            readonly property color paintColor: shell.frameColor
            anchors.fill: parent
            onPaintColorChanged: requestPaint()
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d");
                const edge = shell.bezel;
                const innerRadius = shell.screenRadius - edge;
                ctx.reset();
                ctx.clearRect(0, 0, width, height);
                ctx.beginPath();
                ctx.rect(0, 0, width, height);
                ctx.roundedRect(edge, edge, width - 2 * edge, height - 2 * edge, innerRadius, innerRadius);
                ctx.fillRule = Qt.OddEvenFill;
                ctx.fillStyle = paintColor;
                ctx.fill();
            }
        }
    }

    PanelWindow {
        id: panel

        screen: shell.targetScreen
        visible: shell.themeActive
        color: "transparent"
        anchors { left: true; top: true; right: true }
        implicitHeight: Math.min(450, screen?.height ?? 450)
        exclusiveZone: 38
        WlrLayershell.namespace: "omarchy-top-preview"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: activity.pinned ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        mask: Region {
            item: activity
            bottomLeftRadius: Math.round(activity.bottomRadius)
            bottomRightRadius: bottomLeftRadius
        }

        readonly property HyprlandMonitor monitor: screen ? Hyprland.monitorFor(screen) : null
        readonly property string monitorName: monitor?.name ?? ""
        property var workspaceEntries: []
        property string lastWorkspaceSnapshot: ""
        property bool workspaceRefreshPending: false

        function refreshWorkspaces() {
            if (workspaceSnapshot.running)
                workspaceRefreshPending = true;
            else if (monitorName && !workspaceDelay.running)
                workspaceDelay.start();
        }

        onMonitorNameChanged: {
            workspaceEntries = [];
            lastWorkspaceSnapshot = "";
            refreshWorkspaces();
        }
        Component.onCompleted: refreshWorkspaces()

        Timer {
            id: workspaceDelay
            interval: 20
            onTriggered: {
                if (panel.monitorName && !workspaceSnapshot.running) {
                    workspaceSnapshot.requestedMonitor = panel.monitorName;
                    workspaceSnapshot.running = true;
                }
            }
        }

        Process {
            id: workspaceSnapshot
            property string requestedMonitor
            command: ["hyprctl", "repl", "return o.dynamic_workspace_model(" + JSON.stringify(requestedMonitor) + ")"]
            stdout: StdioCollector { id: workspaceOutput }

            onExited: function(exitCode) {
                const snapshot = workspaceOutput.text;
                if (exitCode === 0 && requestedMonitor === panel.monitorName && snapshot !== panel.lastWorkspaceSnapshot) {
                    try {
                        const entries = JSON.parse(snapshot);
                        if (Array.isArray(entries) && entries.every(entry =>
                            entry && typeof entry.active === "boolean" && typeof entry.occupied === "boolean")) {
                            panel.workspaceEntries = entries;
                            panel.lastWorkspaceSnapshot = snapshot;
                        }
                    } catch (_) {
                        console.warn("Top notch: could not read the dynamic workspace list");
                    }
                }
                if (panel.workspaceRefreshPending) {
                    panel.workspaceRefreshPending = false;
                    workspaceDelay.restart();
                }
            }
        }

        Connections {
            target: Hyprland
            function onRawEvent(event) {
                const name = event?.name ?? "";
                if (/^(workspacev2|createworkspacev2|destroyworkspacev2|moveworkspacev2|changeworkspaceid|renameworkspace|openwindow|closewindow|movewindowv2|pin|focusedmon|monitoraddedv2|monitorremoved|configreloaded)$/.test(name))
                    panel.refreshWorkspaces();
            }
        }

        Rectangle {
            width: parent.width
            height: shell.bezel
            color: shell.frameColor
        }

        HyprlandFocusGrab {
            active: shell.themeActive && activity.pinned
            windows: [panel]
            onCleared: activity.dismiss()
        }

        ActivityIsland {
            id: activity
            anchors.horizontalCenter: parent.horizontalCenter
            y: shell.bezel
            width: Math.min(implicitWidth, Math.max(0, parent.width - 48))
            height: implicitHeight
            themePalette: palette
            motionEnabled: shell.motionEnabled
            workspaceEntries: panel.workspaceEntries
            timeLabel: Qt.formatTime(clock.date, "HH:mm")
            dateLabel: Qt.formatDate(clock.date, "dddd d MMMM")
            availableHeight: panel.height - shell.bezel
        }
    }
}
