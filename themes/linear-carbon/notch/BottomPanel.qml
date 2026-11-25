import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "/usr/share/omarchy/shell/plugins/dock/DockModel.js" as DockModel

PanelWindow {
    id: bar

    required property bool themeActive
    required property bool motionEnabled
    required property NotchPalette themePalette
    required property ShellScreen targetScreen
    required property int bezel
    required property int curveRadius
    readonly property HyprlandMonitor monitor: targetScreen ? Hyprland.monitorFor(targetScreen) : null
    readonly property int workspaceId: monitor?.activeWorkspace?.id ?? -1
    readonly property bool underFullscreen: Hyprland.toplevels.values.some(window =>
        window.workspace?.id === workspaceId && ((Number(window.lastIpcObject?.fullscreen) & 2) !== 0
            || window.wayland?.fullscreen === true))
    readonly property int slotSize: 32
    readonly property int slotGap: 3
    readonly property int rowHeight: 36
    readonly property var terminalEntries: DesktopEntries.applications.values.filter(entry =>
        entry.runInTerminal || entry.execString.includes("--app-id="))
    property var pinnedIds: []
    property var pendingPins: null
    property bool pinsReady: false
    readonly property var tasks: {
        const installed = DesktopEntries.applications.values;
        const apps = new Map();
        for (const id of pinnedIds) {
            const entry = installed.find(app => app.id === id);
            if (entry) apps.set("desktop:" + id, { entry, windows: [], pinned: true });
        }

        for (const window of Hyprland.toplevels.values) {
            if (!window.wayland || window.wayland.parent) continue;
            const appId = window.wayland.appId;
            const entry = appId ? DesktopEntries.heuristicLookup(appId)
                ?? DesktopEntries.byId(DockModel.claimingEntryId(appId, terminalEntries)) : null;
            const key = entry ? "desktop:" + entry.id
                : appId ? "app:" + appId : "window:" + window.address;
            if (!apps.has(key)) apps.set(key, { entry, windows: [], pinned: false });
            apps.get(key).windows.push(window);
        }
        return [...apps.values()];
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "fullscreen") Hyprland.refreshToplevels();
        }
    }

    function activateTask(task) {
        const windows = task.windows;
        if (windows.length) {
            const rank = DockModel.pickWindow(windows.map(window => ({
                workspaceId: window.workspace?.id,
                activated: window.activated
            })), workspaceId);
            windows[rank]?.wayland?.activate();
            return;
        }
        const entry = task.entry;
        if (!entry) return;
        if (entry.runInTerminal) {
            const command = entry.command.filter(word => !/^%[a-zA-Z]$/.test(word));
            if (command.length) Quickshell.execDetached(["omarchy", "launch", "tui", ...command]);
        } else {
            Quickshell.execDetached(["uwsm-app", "--", "gtk-launch", "--", entry.id + ".desktop"]);
        }
    }

    function openPinEditor() {
        if (!pinsReady) {
            Quickshell.execDetached(["omarchy", "notification", "send", "Could not read Linear Carbon pins"]);
            pinOverlay.mode = "";
            return;
        }
        pinOverlay.draft = pinnedIds.slice();
        search.text = "";
        pinOverlay.mode = "editor";
        search.forceActiveFocus();
    }

    function savePins() {
        const ids = pinOverlay.draft;
        if (JSON.stringify(ids) === JSON.stringify(pinnedIds)) {
            pinOverlay.mode = "";
            return;
        }
        pendingPins = ids.slice();
        pinsFile.setText(JSON.stringify(ids) + "\n");
    }

    FileView {
        id: pinsFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state")
            + "/omarchy/linear-carbon-pinned-apps.json"
        preload: true
        atomicWrites: true
        printErrors: false
        onLoaded: {
            try {
                const ids = JSON.parse(text());
                if (!Array.isArray(ids) || !ids.every(id => typeof id === "string" && id.length)) return;
                bar.pinnedIds = [...new Set(ids)];
                bar.pinsReady = true;
            } catch (_) {}
        }
        onLoadFailed: error => bar.pinsReady = error === FileViewError.FileNotFound
        onSaved: {
            if (bar.pendingPins) bar.pinnedIds = bar.pendingPins;
            bar.pendingPins = null;
            pinOverlay.mode = "";
        }
        onSaveFailed: {
            bar.pendingPins = null;
            Quickshell.execDetached(["omarchy", "notification", "send", "Could not save Linear Carbon pins"]);
        }
    }

    screen: targetScreen
    visible: themeActive && !!targetScreen && !underFullscreen
    anchors { left: true; bottom: true; right: true }
    implicitHeight: rowHeight + curveRadius
    exclusiveZone: implicitHeight
    color: "transparent"
    // Hyprland arranges Overlay after the existing Top-layer bar, so the
    // compositor stacks this above it using the bar's live reservation.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "linear-carbon-bottom-panel"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    onVisibleChanged: if (!visible) pinOverlay.mode = ""
    mask: Region {
        item: strip
    }

    PanelWindow {
        id: pinDismiss
        screen: bar.targetScreen
        visible: bar.visible && pinOverlay.mode !== ""
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "linear-carbon-pin-dismiss"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: pinOverlay.mode = ""
        }
    }

    PanelWindow {
        id: pinOverlay
        property string mode: ""
        property int clickX: 0
        property var draft: []
        readonly property bool editing: mode === "editor"
        readonly property int editorHeight: Math.min(400, Math.max(200, (bar.targetScreen?.height ?? 800) / 2))
        property real editorProgress: 0
        onEditingChanged: {
            editorGrowth.stop();
            editorProgress = editing && !bar.motionEnabled ? 1 : 0;
            if (editing && bar.motionEnabled) editorGrowth.start();
        }
        NumberAnimation {
            id: editorGrowth
            target: pinOverlay
            property: "editorProgress"
            to: 1
            duration: 240
            easing.type: Easing.OutCubic
        }
        screen: bar.targetScreen
        visible: bar.visible && mode !== "" && pinDismiss.backingWindowVisible
        anchors { left: true; right: true; bottom: true }
        // The compositor puts this non-reserving surface above the bar.
        // Leave a small overlap so the separately rendered surfaces meet cleanly.
        margins.bottom: -bar.curveRadius - 1
        exclusiveZone: 0
        // Paint the reveal inside a stable layer surface. Its bottom edge is
        // fixed to the bar throughout the animation.
        implicitHeight: editorHeight
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "linear-carbon-pin-editor"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        mask: Region { item: card }

        FrameShoulder {
            id: leftShoulder
            width: bar.curveRadius
            anchors.right: card.left
            anchors.rightMargin: -0.5
            anchors.bottom: card.bottom
            anchors.bottomMargin: 1
            paintColor: bar.themePalette.frame
            inverted: true
            visible: card.height >= height
        }
        FrameShoulder {
            width: bar.curveRadius
            anchors.left: card.right
            anchors.leftMargin: -0.5
            anchors.bottom: card.bottom
            anchors.bottomMargin: 1
            paintColor: bar.themePalette.frame
            mirrored: true
            inverted: true
            visible: leftShoulder.visible
        }

        FocusScope {
            id: card
            focus: true
            clip: true
            anchors.bottom: parent.bottom
            readonly property int sideInset: bar.bezel + leftShoulder.width
            x: pinOverlay.editing ? Math.round((parent.width - width) / 2)
                : Math.max(sideInset, Math.min(pinOverlay.clickX, parent.width - sideInset - width))
            width: Math.min(pinOverlay.editing ? 680 : 164, Math.max(0, parent.width - 2 * sideInset))
            height: pinOverlay.editing ? Math.round(pinOverlay.editorHeight * pinOverlay.editorProgress) : bar.slotSize + 8
            Keys.onEscapePressed: pinOverlay.mode = ""

            Rectangle {
                anchors.fill: parent
                topLeftRadius: bar.curveRadius
                topRightRadius: topLeftRadius
                color: bar.themePalette.frame
            }

            BarButton {
                id: editAction
                visible: !pinOverlay.editing
                anchors { left: parent.left; right: parent.right; verticalCenter: parent.verticalCenter }
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                text: "Edit pinned apps"
                focus: true
                onClicked: bar.openPinEditor()
            }

            ColumnLayout {
                visible: pinOverlay.editing
                anchors { top: parent.top; left: parent.left; right: parent.right }
                anchors.margins: 16
                height: pinOverlay.editorHeight - 32
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Text {
                        Layout.fillWidth: true
                        text: "Pinned apps"
                        textFormat: Text.PlainText
                        color: bar.themePalette.ink
                        font.pixelSize: 17
                        font.weight: Font.DemiBold
                    }
                    BarButton {
                        Layout.preferredWidth: 66
                        Layout.preferredHeight: bar.slotSize
                        text: "Cancel"
                        onClicked: pinOverlay.mode = ""
                    }
                    BarButton {
                        Layout.preferredWidth: 66
                        Layout.preferredHeight: bar.slotSize
                        selected: true
                        text: "Apply"
                        enabled: !bar.pendingPins
                        onClicked: bar.savePins()
                    }
                }

                Controls.TextField {
                    id: search
                    Layout.fillWidth: true
                    Layout.preferredHeight: 34
                    padding: 9
                    font.pixelSize: 13
                    color: bar.themePalette.ink
                    selectionColor: bar.themePalette.selection
                    selectedTextColor: bar.themePalette.ink
                    placeholderText: "Search installed apps"
                    placeholderTextColor: bar.themePalette.muted
                    Accessible.name: placeholderText
                    background: Rectangle { radius: 7; color: bar.themePalette.tile }
                    onTextChanged: appGrid.positionViewAtBeginning()
                }

                GridView {
                    id: appGrid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    cellWidth: width / Math.max(2, Math.floor(width / 106))
                    cellHeight: 79
                    boundsBehavior: Flickable.StopAtBounds
                    readonly property var apps: DesktopEntries.applications.values
                        .filter(entry => !entry.noDisplay && entry.name && entry.id)
                        .sort((a, b) => a.name.localeCompare(b.name))
                    model: {
                        if (!pinOverlay.editing) return [];
                        const query = search.text.trim().toLowerCase();
                        return query ? apps.filter(entry => entry.name.toLowerCase().includes(query)) : apps;
                    }
                    Controls.ScrollBar.vertical: Controls.ScrollBar {
                        width: 6
                        contentItem: Rectangle { radius: 3; color: bar.themePalette.muted }
                    }
                    delegate: BarButton {
                        id: app
                        required property var modelData
                        width: appGrid.cellWidth - 4
                        height: appGrid.cellHeight - 4
                        selected: pinOverlay.draft.includes(modelData.id)
                        enabled: !bar.pendingPins
                        Accessible.role: Accessible.CheckBox
                        Accessible.checkable: true
                        Accessible.checked: selected
                        Accessible.name: modelData.name
                        onClicked: {
                            const id = modelData.id;
                            pinOverlay.draft = selected
                                ? pinOverlay.draft.filter(value => value !== id)
                                : [...pinOverlay.draft, id];
                        }
                        contentItem: Item {
                            IconImage {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 8
                                width: 28
                                height: width
                                asynchronous: true
                                source: Quickshell.iconPath(app.modelData.icon || "application-x-executable", "application-x-executable")
                            }
                            Text {
                                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                                anchors.leftMargin: 6
                                anchors.rightMargin: 6
                                anchors.bottomMargin: 5
                                height: 32
                                text: app.modelData.name
                                textFormat: Text.PlainText
                                color: bar.themePalette.ink
                                font.pixelSize: 12
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                            Text {
                                anchors { top: parent.top; right: parent.right }
                                anchors.margins: 6
                                visible: app.selected
                                text: "✓"
                                color: bar.themePalette.accent
                                font.pixelSize: 12
                            }
                        }
                    }
                    Text {
                        anchors.centerIn: parent
                        visible: appGrid.count === 0
                        text: "No matching apps"
                        textFormat: Text.PlainText
                        color: bar.themePalette.muted
                    }
                }
            }
        }
    }

    component BarButton: Controls.Button {
        id: button
        property bool selected: false
        height: bar.slotSize
        padding: 0
        hoverEnabled: true
        background: Rectangle {
            radius: 7
            color: button.down || button.selected ? bar.themePalette.selection
                : button.hovered || button.visualFocus ? bar.themePalette.hover : "transparent"
        }
        contentItem: Text {
            text: button.text
            textFormat: Text.PlainText
            color: bar.themePalette.ink
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    Canvas {
        anchors.fill: parent
        readonly property color paintColor: bar.themePalette.frame
        onPaintColorChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const ctx = getContext("2d");
            const edge = bar.bezel;
            const curve = Math.min(bar.curveRadius, Math.max(0, width / 2 - edge));
            ctx.reset();
            ctx.clearRect(0, 0, width, height);
            ctx.beginPath();
            ctx.moveTo(0, 0);
            ctx.lineTo(edge, 0);
            ctx.arcTo(edge, curve, edge + curve, curve, curve);
            ctx.lineTo(width - edge - curve, curve);
            ctx.arcTo(width - edge, curve, width - edge, 0, curve);
            ctx.lineTo(width - edge, 0);
            ctx.lineTo(width, 0);
            ctx.lineTo(width, height);
            ctx.lineTo(0, height);
            ctx.closePath();
            ctx.fillStyle = paintColor;
            ctx.fill();
        }
    }

    Item {
        id: strip
        anchors { left: parent.left; bottom: parent.bottom; right: parent.right }
        height: bar.rowHeight

        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: eventPoint => {
                if (bar.pendingPins) return;
                pinOverlay.clickX = Math.round(strip.x + eventPoint.position.x);
                pinOverlay.mode = "context";
                editAction.forceActiveFocus();
            }
        }

        Item {
            anchors.centerIn: parent
            width: Math.min(Math.max(0, parent.width - 2 * bar.bezel),
                appPicker.width + 12 + (running.count ? 8 + running.naturalWidth : 0))
            height: parent.height

            BarButton {
                id: appPicker
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: 53
                text: "Apps"
                Accessible.name: "Open application launcher"
                onClicked: Quickshell.execDetached(["omarchy-shell", "omarchy.dock", "apps"])
            }

            Rectangle {
                visible: running.count > 0
                anchors.left: appPicker.right
                anchors.leftMargin: 3
                anchors.verticalCenter: parent.verticalCenter
                height: 14
                width: 1
                color: bar.themePalette.track
            }

            ListView {
                id: running
                readonly property int naturalWidth: count * (bar.slotSize + bar.slotGap) - bar.slotGap
                anchors.left: appPicker.right
                anchors.leftMargin: 8
                anchors.right: parent.right
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                height: bar.slotSize
                visible: count > 0
                clip: true
                orientation: ListView.Horizontal
                spacing: bar.slotGap
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentWidth > width
                keyNavigationEnabled: false
                model: bar.tasks
                delegate: BarButton {
                    id: task
                    required property var modelData
                    readonly property var window: modelData.windows[0]?.wayland
                    width: bar.slotSize
                    Accessible.name: modelData.pinned ? modelData.entry.name + ", pinned"
                        : window?.title || modelData.entry?.name || window?.appId || "Open window"
                    contentItem: Item {
                        IconImage {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 6
                            width: 18
                            height: width
                            opacity: task.window ? 1 : 0.72
                            source: Quickshell.iconPath(task.modelData.entry?.icon || "application-x-executable", "application-x-executable")
                        }
                        Rectangle {
                            visible: task.modelData.windows.some(window => window.activated)
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 3
                            width: 8
                            height: 2
                            radius: 1
                            color: bar.themePalette.accent
                        }
                    }
                    onClicked: bar.activateTask(modelData)
                }
            }
        }
    }
}
