//@ pragma UseQApplication

import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

ShellRoot {
    id: shell

    readonly property color frameColor: palette.frame
    readonly property int bezel: 5
    readonly property int frameRadius: 8
    property bool motionEnabled: false
    property bool gapless: false
    property bool gapModeReady: false
    property real bottomFrameRadius: gapless ? 0 : frameRadius
    readonly property int gapTransitionMs: 340
    property bool themeActive: false
    readonly property ShellScreen targetScreen: Quickshell.screens[0] ?? null

    Behavior on bottomFrameRadius {
        enabled: shell.motionEnabled && shell.gapModeReady
        NumberAnimation { duration: shell.gapTransitionMs; easing.type: Easing.InOutSine }
    }

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

    BottomPanel {
        id: bottomPanel
        targetScreen: shell.targetScreen
        themeActive: shell.themeActive
        motionEnabled: shell.motionEnabled
        themePalette: palette
        bezel: shell.bezel
        curveRadius: shell.frameRadius
        frameCornerRadius: shell.bottomFrameRadius
        today: clock.date
    }

    NotificationCorner {
        targetScreen: shell.targetScreen
        enabledForTheme: shell.themeActive
        blockedByFullscreen: bottomPanel.underFullscreen
        motionEnabled: shell.motionEnabled
        themePalette: palette
        bezel: shell.bezel
        curveRadius: shell.frameRadius
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

    Process {
        id: checkGapless
        command: ["test", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/toggles/hypr/window-no-gaps.lua"]
        running: true
        onExited: exitCode => {
            shell.gapless = exitCode === 0;
            shell.gapModeReady = true;
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "configreloaded") {
                checkMotion.running = true;
                checkGapless.running = true;
            }
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

        Rectangle {
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: shell.bezel
            color: shell.frameColor
        }

        Rectangle {
            anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
            width: shell.bezel
            color: shell.frameColor
        }

        Rectangle {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            height: shell.bezel
            color: shell.frameColor
        }

        FrameShoulder {
            x: shell.bezel
            y: shell.bezel
            width: shell.frameRadius
            mirrored: true
            paintColor: shell.frameColor
        }

        FrameShoulder {
            x: parent.width - shell.bezel - width
            y: shell.bezel
            width: shell.frameRadius
            paintColor: shell.frameColor
        }

        FrameShoulder {
            x: shell.bezel
            y: parent.height - shell.bezel - height
            width: shell.bottomFrameRadius
            visible: width > 0
            mirrored: true
            inverted: true
            paintColor: shell.frameColor
        }

        FrameShoulder {
            x: parent.width - shell.bezel - width
            y: parent.height - shell.bezel - height
            width: shell.bottomFrameRadius
            visible: width > 0
            inverted: true
            paintColor: shell.frameColor
        }
    }

    PanelWindow {
        id: panel

        screen: shell.targetScreen
        visible: shell.themeActive
        color: "transparent"
        anchors { left: true; top: true; right: true }
        implicitHeight: Math.min(450, screen?.height ?? 450)
        exclusiveZone: shell.bezel + (shell.gapless ? 0 : activity.collapsedHeight)
        WlrLayershell.namespace: "omarchy-top-preview"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: activity.pinned ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        mask: Region {
            item: notchHitArea
            bottomLeftRadius: panel.notchReveal > 0 ? activity.curveRadius : 0
            bottomRightRadius: bottomLeftRadius
        }

        property bool peek: false
        readonly property bool notchShown: !shell.gapless || peek || activity.pinned
        property real notchReveal: notchShown ? 1 : 0

        Behavior on notchReveal {
            enabled: shell.motionEnabled && shell.gapModeReady
            NumberAnimation {
                duration: shell.gapTransitionMs
                easing.type: Easing.InOutSine
            }
        }

        Connections {
            target: shell
            function onGaplessChanged() {
                hideNotch.stop();
                panel.peek = shell.gapless && notchHitArea.containsMouse;
                if (shell.gapless) activity.dismiss();
            }
        }

        Timer {
            id: hideNotch
            interval: 180
            onTriggered: {
                if (!notchHitArea.containsMouse) panel.peek = false;
            }
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

        // One continuous hover area joins the frame edge and the notch header.
        MouseArea {
            id: notchHitArea
            anchors.horizontalCenter: parent.horizontalCenter
            y: shell.gapless ? 0 : shell.bezel
            width: activity.width
            height: (shell.gapless ? shell.bezel : 0) + Math.max(
                activity.height * panel.notchReveal,
                panel.notchShown ? activity.collapsedHeight : 0)
            z: 1
            hoverEnabled: shell.gapless && !activity.pinned
            acceptedButtons: Qt.NoButton

            onEntered: {
                hideNotch.stop();
                panel.peek = true;
            }
            onExited: hideNotch.restart()
        }

        Item {
            id: notchViewport
            visible: panel.notchReveal > 0
            anchors.horizontalCenter: parent.horizontalCenter
            y: shell.bezel
            width: activity.width + 2 * shell.frameRadius
            height: activity.height
            clip: true

            ActivityIsland {
                id: activity
                anchors.horizontalCenter: parent.horizontalCenter
                y: -height * (1 - panel.notchReveal)
                opacity: Math.min(1, panel.notchReveal * 1.4)
                width: Math.min(implicitWidth, Math.max(0, panel.width - 48))
                height: implicitHeight
                themePalette: palette
                curveRadius: shell.frameRadius
                motionEnabled: shell.motionEnabled
                workspaceEntries: panel.workspaceEntries
                timeLabel: Qt.formatTime(clock.date, "HH:mm")
                availableHeight: panel.height - shell.bezel
            }
        }
    }
}
