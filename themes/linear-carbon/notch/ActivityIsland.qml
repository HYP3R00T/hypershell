/* Tabler Filled icons
MIT License

Copyright (c) 2020-2026 Paweł Kuna

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

import QtQuick
import QtQuick.Controls
import QtQuick.Shapes
import Quickshell.Io
import Quickshell.Services.UPower

FocusScope {
    id: island

    required property bool motionEnabled
    required property int curveRadius
    required property NotchPalette themePalette
    required property var workspaceEntries
    required property string timeLabel
    required property string dateLabel
    property real availableHeight: 450

    property bool pinned: false
    property bool peek: false
    property bool waitForExit: false
    readonly property bool expanded: pinned || peek
    readonly property color frameColor: themePalette.frame
    readonly property color ink: themePalette.ink
    readonly property color muted: themePalette.muted
    readonly property string iconFont: "JetBrainsMono Nerd Font"
    readonly property string activeWorkspaceKey: workspaceEntries.find(entry => entry.active)?.key ?? ""
    property string layoutMode: ""
    readonly property UPowerDevice battery: UPower.displayDevice
    readonly property real chargeLevel: Math.max(0, Math.min(1, battery?.percentage ?? 0))

    property real morph: expanded ? 1 : 0
    readonly property int reservedWorkspaceMarks: 7
    readonly property int workspaceMarkPitch: 7
    readonly property int statusHeight: 10
    readonly property int headerInset: 18
    readonly property int clockClearance: 10
    property real workspaceExtraWidth: Math.max(0, workspaceEntries.length - reservedWorkspaceMarks) * 2 * workspaceMarkPitch
    property real controlsProgress: pinned ? 1 : 0
    readonly property int controlsTopInset: 7
    readonly property int controlsBottomInset: 12
    readonly property real maxControlHeight: Math.max(0, availableHeight - header.height - controlsTopInset - controlsBottomInset)
    implicitWidth: 210 + workspaceExtraWidth + 20 * morph + 246 * controlsProgress
    implicitHeight: header.height + (1 - controlsProgress) * morph * (date.implicitHeight + 12)
        + controlsProgress * (Math.min(maxControlHeight, controls.implicitHeight) + controlsTopInset + controlsBottomInset)

    Behavior on controlsProgress {
        enabled: island.motionEnabled
        NumberAnimation { duration: island.pinned ? 210 : 155; easing.type: Easing.OutCubic }
    }

    Behavior on morph {
        enabled: island.motionEnabled
        NumberAnimation { duration: island.expanded ? 265 : 175; easing.type: Easing.OutCubic }
    }

    Behavior on workspaceExtraWidth {
        enabled: island.motionEnabled
        NumberAnimation { duration: 175; easing.type: Easing.OutCubic }
    }

    function dismiss() {
        pinned = false;
        peek = false;
        waitForExit = pointer.hovered;
        enterDelay.stop();
        leaveDelay.stop();
    }

    Keys.onEscapePressed: dismiss()

    HoverHandler {
        id: pointer
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onHoveredChanged: {
            if (hovered) {
                leaveDelay.stop();
                if (!island.expanded && !island.waitForExit)
                    enterDelay.restart();
            } else {
                island.waitForExit = false;
                enterDelay.stop();
                if (!island.pinned)
                    leaveDelay.restart();
            }
        }
    }
    Timer { id: enterDelay; interval: 145; onTriggered: island.peek = pointer.hovered }
    Timer { id: leaveDelay; interval: 180; onTriggered: island.peek = false }

    function refreshLayout() {
        if (activeWorkspaceKey && !layoutQuery.running) {
            layoutQuery.workspaceKey = activeWorkspaceKey;
            layoutQuery.running = true;
        }
    }

    onActiveWorkspaceKeyChanged: refreshLayout()
    Component.onCompleted: refreshLayout()

    Timer {
        // Omarchy refreshes its own bar via IPC when a layout changes in place.
        // The standalone notch uses the same read-only command on a short interval.
        interval: 1500
        running: island.activeWorkspaceKey !== ""
        repeat: true
        onTriggered: island.refreshLayout()
    }

    Process {
        id: layoutQuery
        property string workspaceKey
        command: ["omarchy-hyprland-workspace-layout-current", workspaceKey]
        stdout: StdioCollector { id: layoutOutput }
        onExited: function(exitCode) {
            if (workspaceKey !== island.activeWorkspaceKey) {
                Qt.callLater(island.refreshLayout);
            } else if (exitCode === 0 && layoutOutput.text.trim()) {
                island.layoutMode = layoutOutput.text.trim();
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: island.frameColor
        topLeftRadius: 0
        topRightRadius: 0
        bottomLeftRadius: island.curveRadius
        bottomRightRadius: island.curveRadius
    }

    FrameShoulder {
        width: island.curveRadius
        anchors.right: parent.left
        anchors.rightMargin: -0.5
        paintColor: island.frameColor
    }
    FrameShoulder {
        width: island.curveRadius
        anchors.left: parent.right
        anchors.leftMargin: -0.5
        paintColor: island.frameColor
        mirrored: true
    }

    AbstractButton {
        id: header
        width: parent.width
        height: 30
        padding: 0
        background: null
        Accessible.name: {
            const action = (island.pinned ? "Close top notch, " : "Open top notch, ") + island.timeLabel;
            const position = island.workspaceEntries.findIndex(entry => entry.active);
            const workspace = position < 0 ? "" : ". Workspace " + (position + 1) + " of " + island.workspaceEntries.length;
            const layout = island.layoutMode === "scrolling" ? "Scrolling"
                : island.layoutMode === "floating" ? "Floating" : "Tiled";
            const power = island.battery?.isPresent
                ? ". Battery " + Math.round(island.chargeLevel * 100) + " percent"
                : "";
            return action + workspace + (island.layoutMode ? ". " + layout + " layout" : "") + power;
        }
        onClicked: {
            if (island.pinned) {
                island.dismiss();
            } else {
                island.pinned = true;
                island.forceActiveFocus();
            }
        }

        contentItem: Item {
            Row {
                id: workspaceMarks
                readonly property real pitch: Math.min(island.workspaceMarkPitch,
                    Math.max(0.5, (notchClock.x - island.headerInset - island.clockClearance)
                        / Math.max(1, island.workspaceEntries.length)))
                anchors.left: parent.left
                anchors.leftMargin: island.headerInset
                anchors.verticalCenter: parent.verticalCenter
                height: island.statusHeight
                spacing: Math.max(0, pitch - 3)

                Repeater {
                    model: island.workspaceEntries.length
                    delegate: Rectangle {
                        required property int index
                        readonly property var entry: island.workspaceEntries[index]
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(3, workspaceMarks.pitch)
                        height: entry?.active ? island.statusHeight : 3
                        color: entry?.active ? island.ink
                            : Qt.tint(island.frameColor, Qt.rgba(island.muted.r, island.muted.g, island.muted.b,
                                entry?.occupied ? 0.48 : 0.3))
                        radius: 2
                        Behavior on height {
                            enabled: island.motionEnabled
                            NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                        }
                    }
                }
            }

            Label {
                id: notchClock
                anchors.centerIn: parent
                text: island.timeLabel
                textFormat: Text.PlainText
                color: island.ink
                font.family: island.iconFont
                font.pixelSize: 12
                font.weight: Font.DemiBold
            }

            Row {
                x: Math.round(parent.width - width - island.headerInset)
                y: Math.round((parent.height - height) / 2)
                spacing: 10

                Item {
                    width: Math.ceil(island.statusHeight * 18 / 14)
                    height: island.statusHeight
                    visible: island.layoutMode !== ""
                    anchors.verticalCenter: parent.verticalCenter

                    LayoutGlyph {
                        mode: island.layoutMode
                        height: parent.height
                        x: Math.round((parent.width - width) / 2)
                    }
                }

                Item {
                    width: 17
                    height: island.statusHeight
                    visible: island.battery?.isPresent ?? false
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        width: 16
                        height: parent.height
                        color: "transparent"
                        border.color: island.muted
                        radius: 2
                    }
                    Rectangle {
                        x: 2
                        y: 2
                        width: 12 * island.chargeLevel
                        height: parent.height - 4
                        radius: 1
                        color: island.muted
                    }
                    Rectangle {
                        x: 16
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: 3
                        color: island.muted
                    }

                }
            }
        }
    }

    Item {
        anchors.top: header.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        clip: true
        opacity: Math.max(0, Math.min(1, (island.morph - 0.22) / 0.62))
        visible: opacity > 0

        Label {
            id: date
            anchors.top: parent.top
            anchors.topMargin: 2
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 15
            anchors.rightMargin: 15
            text: island.dateLabel
            visible: !island.pinned && island.controlsProgress < 0.1
            textFormat: Text.PlainText
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
            color: island.muted
            font.pixelSize: 11
        }

        NotchControls {
            id: controls
            themePalette: island.themePalette
            anchors.fill: parent
            anchors.leftMargin: 15
            anchors.rightMargin: 15
            anchors.topMargin: island.controlsTopInset
            anchors.bottomMargin: island.controlsBottomInset
            active: island.pinned
            onDismissRequested: island.dismiss()
            visible: island.controlsProgress > 0 && height > 5
            enabled: active
            opacity: Math.min(1, island.controlsProgress * 1.7)
        }
    }

    component LayoutGlyph: Item {
        id: glyph
        required property string mode
        readonly property rect viewBox: mode === "scrolling" ? Qt.rect(3, 5, 18, 14)
            : mode === "floating" ? Qt.rect(2, 2, 20, 20) : Qt.rect(3, 3, 18, 18)
        width: Math.round(height * viewBox.width / viewBox.height)

        Item {
            transform: Scale {
                xScale: glyph.width / glyph.viewBox.width
                yScale: glyph.height / glyph.viewBox.height
            }

            Shape {
                x: -glyph.viewBox.x
                y: -glyph.viewBox.y
                ShapePath {
                    strokeWidth: -1
                    fillColor: island.muted
                    fillRule: ShapePath.WindingFill
                    PathSvg {
                        path: {
                            switch (glyph.mode) {
                            case "scrolling": // Tabler Filled caret-left-right
                                return "M13 6c0 -.89 1.077 -1.337 1.707 -.707l6 6a1 1 0 0 1 0 1.414l-6 6a.95 .95 0 0 1 -.082 .073l-.009 .006l-.022 .016l-.058 .042l-.016 .009l-.009 .007l-.028 .014l-.043 .024l-.018 .007l-.018 .01l-.034 .012l-.033 .015l-.026 .007l-.02 .008l-.026 .005l-.036 .012l-.029 .004l-.024 .006l-.028 .003l-.031 .006l-.032 .002l-.026 .003h-.026l-.033 .002l-.033 -.002h-.026l-.026 -.003l-.032 -.002l-.031 -.006l-.028 -.003l-.024 -.006l-.03 -.004l-.035 -.012l-.027 -.005l-.019 -.008l-.026 -.007l-.033 -.015l-.034 -.012l-.018 -.01l-.018 -.007l-.043 -.024l-.028 -.014l-.009 -.007l-.016 -.009l-.058 -.042l-.019 -.012l-.003 -.004l-.01 -.006a1.006 1.006 0 0 1 -.154 -.155l-.006 -.009l-.016 -.022l-.042 -.058l-.009 -.016l-.007 -.009l-.014 -.028l-.024 -.043l-.007 -.018l-.01 -.018l-.012 -.034l-.015 -.033l-.007 -.026l-.008 -.02l-.005 -.026l-.012 -.036l-.004 -.029l-.006 -.024l-.003 -.028l-.006 -.031l-.002 -.032l-.003 -.026v-.026l-.002 -.033v-12z " +
                                    "M9.293 5.293c.63 -.63 1.707 -.184 1.707 .707v12l-.002 .033v.026l-.003 .026l-.002 .032l-.006 .031l-.003 .028l-.006 .024l-.004 .03l-.012 .035l-.005 .027l-.008 .019l-.007 .026l-.015 .033l-.012 .034l-.01 .018l-.007 .018l-.024 .043l-.014 .028l-.007 .009l-.009 .016l-.042 .058l-.012 .019l-.004 .003l-.006 .01a1.006 1.006 0 0 1 -.155 .154l-.009 .006l-.022 .016l-.058 .042l-.016 .009l-.009 .007l-.028 .014l-.043 .024l-.018 .007l-.018 .01l-.034 .012l-.033 .015l-.026 .007l-.02 .008l-.026 .005l-.036 .012l-.029 .004l-.024 .006l-.028 .003l-.031 .006l-.032 .002l-.026 .003h-.026l-.033 .002l-.033 -.002h-.026l-.028 -.003l-.03 -.002l-.032 -.006l-.027 -.003l-.025 -.006l-.028 -.004l-.037 -.012l-.026 -.005l-.02 -.008l-.025 -.007l-.034 -.015l-.033 -.012l-.019 -.01l-.017 -.007l-.044 -.024l-.027 -.014l-.01 -.007l-.015 -.009l-.059 -.042l-.018 -.012l-.004 -.004l-.008 -.006a1.006 1.006 0 0 1 -.082 -.073l-6 -6a1 1 0 0 1 0 -1.414l6 -6z";
                            case "floating": // Tabler Filled copy
                                return "M20.926 7.074a3.67 3.67 0 0 1 1.074 2.593v8.666a3.667 3.667 0 0 1 -3.667 3.667h-8.666a3.667 3.667 0 0 1 -3.667 -3.667v-8.666q 0 -.053 .005 -.102a3.66 3.66 0 0 1 3.662 -3.565h8.666c.973 0 1.905 .386 2.593 1.074 " +
                                    "M17.374 3.514a1 1 0 1 1 -1.748 .972c-.221 -.398 -.342 -.486 -.626 -.486h-10c-.548 0 -1 .452 -1 1v9.998c0 .36 .194 .692 .507 .87a1 1 0 1 1 -.99 1.738a3 3 0 0 1 -1.517 -2.606v-10c0 -1.652 1.348 -3 3 -3h10c1.094 0 1.828 .533 2.374 1.514";
                            default: // Tabler Filled layout-grid
                                return "M9 3a2 2 0 0 1 2 2v4a2 2 0 0 1 -2 2h-4a2 2 0 0 1 -2 -2v-4a2 2 0 0 1 2 -2z " +
                                    "M19 3a2 2 0 0 1 2 2v4a2 2 0 0 1 -2 2h-4a2 2 0 0 1 -2 -2v-4a2 2 0 0 1 2 -2z " +
                                    "M9 13a2 2 0 0 1 2 2v4a2 2 0 0 1 -2 2h-4a2 2 0 0 1 -2 -2v-4a2 2 0 0 1 2 -2z " +
                                    "M19 13a2 2 0 0 1 2 2v4a2 2 0 0 1 -2 2h-4a2 2 0 0 1 -2 -2v-4a2 2 0 0 1 2 -2z";
                            }
                        }
                    }
                }
            }
        }
    }

}
