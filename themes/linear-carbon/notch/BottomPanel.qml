import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import "/usr/share/omarchy/shell/plugins/dock/DockModel.js" as DockModel

PanelWindow {
    id: bar

    required property bool themeActive
    required property bool motionEnabled
    required property NotchPalette themePalette
    required property ShellScreen targetScreen
    required property int bezel
    required property int curveRadius
    required property real frameCornerRadius
    required property date today
    property bool calendarOpen: false
    readonly property int overlayBottomInset: Math.max(0,
        Number(monitor?.lastIpcObject?.reserved?.[3] ?? 0) - 1)
    readonly property HyprlandMonitor monitor: targetScreen ? Hyprland.monitorFor(targetScreen) : null
    readonly property int workspaceId: monitor?.activeWorkspace?.id ?? -1
    readonly property bool underFullscreen: Hyprland.toplevels.values.some(window =>
        window.workspace?.id === workspaceId && ((Number(window.lastIpcObject?.fullscreen) & 2) !== 0
            || window.wayland?.fullscreen === true))
    readonly property int slotSize: 36
    readonly property int slotGap: 3
    readonly property int rowHeight: 42
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
        pinOverlay.selectedPin = pinnedIds[0] ?? "";
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
    // Only the painted strip reserves space. The bezel curves extend above it.
    exclusiveZone: rowHeight
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "linear-carbon-bottom-panel"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    onVisibleChanged: {
        if (!visible) {
            pinOverlay.mode = "";
            calendarOpen = false;
            trayDrawer.expanded = false;
        }
    }
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
        property string selectedPin: ""
        readonly property int selectedPinIndex: Math.max(0, draft.indexOf(selectedPin))

        function moveSelectedPin(offset) {
            const from = selectedPinIndex;
            const to = from + offset;
            if (to < 0 || to >= draft.length) return;
            const reordered = draft.slice();
            const [id] = reordered.splice(from, 1);
            reordered.splice(to, 0, id);
            selectedPin = id;
            draft = reordered;
            Qt.callLater(() => pinOrder.positionViewAtIndex(selectedPinIndex, ListView.Contain));
        }
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
        margins.bottom: -1
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
                        renderType: Text.CurveRendering
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

                RowLayout {
                    visible: pinOverlay.draft.length > 0
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        renderType: Text.CurveRendering
                        text: "Pin order"
                        color: bar.themePalette.muted
                        font.pixelSize: 12
                    }

                    ListView {
                        id: pinOrder
                        Layout.fillWidth: true
                        Layout.preferredHeight: bar.slotSize
                        clip: true
                        orientation: ListView.Horizontal
                        spacing: bar.slotGap
                        boundsBehavior: Flickable.StopAtBounds
                        keyNavigationEnabled: false
                        model: pinOverlay.editing ? pinOverlay.draft : []

                        delegate: BarButton {
                            id: pin
                            required property string modelData
                            required property int index
                            readonly property var entry: DesktopEntries.byId(modelData)
                            width: bar.slotSize
                            selected: index === pinOverlay.selectedPinIndex
                            enabled: !bar.pendingPins
                            Accessible.name: entry?.name || modelData
                            Accessible.selected: selected
                            onClicked: pinOverlay.selectedPin = modelData
                            contentItem: Item {
                                AppIcon {
                                    anchors.centerIn: parent
                                    width: 19
                                    height: width
                                    source: Quickshell.iconPath(pin.entry?.icon || "application-x-executable", "application-x-executable")
                                }
                            }
                        }
                    }

                    BarButton {
                        Layout.preferredWidth: bar.slotSize
                        text: "‹"
                        Accessible.name: "Move selected pin left"
                        enabled: !bar.pendingPins && pinOverlay.selectedPinIndex > 0
                        onClicked: pinOverlay.moveSelectedPin(-1)
                    }
                    BarButton {
                        Layout.preferredWidth: bar.slotSize
                        text: "›"
                        Accessible.name: "Move selected pin right"
                        enabled: !bar.pendingPins && pinOverlay.selectedPinIndex < pinOverlay.draft.length - 1
                        onClicked: pinOverlay.moveSelectedPin(1)
                    }
                }

                Controls.TextField {
                    id: search
                    renderType: TextInput.CurveRendering
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
                            AppIcon {
                                anchors.horizontalCenter: parent.horizontalCenter
                                y: 8
                                width: 28
                                height: width
                                source: Quickshell.iconPath(app.modelData.icon || "application-x-executable", "application-x-executable")
                            }
                            Text {
                                renderType: Text.CurveRendering
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
                                renderType: Text.CurveRendering
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
                        renderType: Text.CurveRendering
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

    TrayMenu {
        id: trayPopup
        panelVisible: bar.visible
        targetScreen: bar.targetScreen
        themePalette: bar.themePalette
        bezel: bar.bezel
        curveRadius: bar.curveRadius
        bottomInset: bar.overlayBottomInset
    }

    PanelWindow {
        id: calendarOverlay
        screen: bar.targetScreen
        visible: bar.visible
        anchors { left: true; right: true; top: true; bottom: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "linear-carbon-calendar"
        WlrLayershell.keyboardFocus: bar.calendarOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        mask: Region {
            width: bar.calendarOpen ? calendarOverlay.width : 0
            height: bar.calendarOpen ? calendarOverlay.height : 0
        }

        readonly property int calendarWidth: Math.min(320, Math.max(0,
            width - 2 * (bar.bezel + bar.curveRadius)))
        readonly property int calendarHeight: Math.ceil(calendarPane.implicitHeight) + 24
        property real revealProgress: 0

        Connections {
            target: bar
            function onCalendarOpenChanged() {
                calendarMotion.stop();
                const opening = bar.calendarOpen;
                const target = opening ? 1 : 0;
                if (bar.motionEnabled && bar.visible) {
                    calendarMotion.to = target;
                    calendarMotion.easing.type = opening ? Easing.OutCubic : Easing.InOutSine;
                    calendarMotion.start();
                } else {
                    calendarOverlay.revealProgress = target;
                }
                if (opening) calendarCard.forceActiveFocus();
            }
        }

        NumberAnimation {
            id: calendarMotion
            target: calendarOverlay
            property: "revealProgress"
            duration: 240
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: bar.calendarOpen = false
        }

        Shape {
            id: calendarShape
            anchors.fill: parent
            visible: calendarCard.width > 0 && calendarCard.height > 0
            preferredRendererType: Shape.CurveRenderer
            readonly property real leftEdge: calendarCard.x
            readonly property real rightEdge: width - bar.bezel
            readonly property real topEdge: calendarCard.y
            readonly property real bottomEdge: calendarCard.y + calendarCard.height
            readonly property real dockEdge: bottomEdge - 1
            readonly property real curve: Math.max(0, Math.min(bar.curveRadius,
                (rightEdge - leftEdge) / 2, (dockEdge - topEdge) / 2))

            ShapePath {
                fillColor: bar.themePalette.frame
                strokeWidth: -1
                startX: calendarShape.leftEdge - calendarShape.curve
                startY: calendarShape.dockEdge

                PathArc {
                    x: calendarShape.leftEdge
                    y: calendarShape.dockEdge - calendarShape.curve
                    radiusX: calendarShape.curve
                    radiusY: calendarShape.curve
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: calendarShape.leftEdge; y: calendarShape.topEdge + calendarShape.curve }
                PathArc {
                    x: calendarShape.leftEdge + calendarShape.curve
                    y: calendarShape.topEdge
                    radiusX: calendarShape.curve
                    radiusY: calendarShape.curve
                }
                PathLine { x: calendarShape.rightEdge - calendarShape.curve; y: calendarShape.topEdge }
                PathArc {
                    x: calendarShape.rightEdge
                    y: calendarShape.topEdge - calendarShape.curve
                    radiusX: calendarShape.curve
                    radiusY: calendarShape.curve
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: calendarShape.rightEdge + 1; y: calendarShape.topEdge - calendarShape.curve }
                PathLine { x: calendarShape.rightEdge + 1; y: calendarShape.bottomEdge }
                PathLine { x: calendarShape.leftEdge - calendarShape.curve; y: calendarShape.bottomEdge }
                PathLine { x: calendarShape.leftEdge - calendarShape.curve; y: calendarShape.dockEdge }
            }
        }

        FocusScope {
            id: calendarCard
            anchors { right: parent.right; bottom: parent.bottom }
            anchors.rightMargin: bar.bezel - 1
            anchors.bottomMargin: bar.overlayBottomInset
            width: Math.round(calendarOverlay.calendarWidth * calendarOverlay.revealProgress)
            height: Math.round(calendarOverlay.calendarHeight * calendarOverlay.revealProgress)
            focus: true
            clip: true
            Keys.onEscapePressed: bar.calendarOpen = false

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.AllButtons
            }

            Loader {
                id: calendarPane
                active: bar.calendarOpen || calendarOverlay.revealProgress > 0
                anchors { top: parent.top; right: parent.right }
                anchors.margins: 12
                width: Math.max(0, calendarOverlay.calendarWidth - 24)
                sourceComponent: PanelCalendar {
                    themePalette: bar.themePalette
                    today: bar.today
                }
            }
        }
    }

    component AppIcon: Image {
        // Render desktop assets above the display resolution before scaling down.
        readonly property int decodeSize: Math.max(1, Math.ceil(width * Screen.devicePixelRatio * 2))
        sourceSize: Qt.size(decodeSize, decodeSize)
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        smooth: true
        mipmap: true
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
            renderType: Text.CurveRendering
            text: button.text
            textFormat: Text.PlainText
            color: bar.themePalette.ink
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
        }
    }

    Rectangle {
        anchors.fill: strip
        color: bar.themePalette.frame
    }

    FrameShoulder {
        x: bar.bezel
        anchors.bottom: strip.top
        width: bar.frameCornerRadius
        visible: width > 0
        mirrored: true
        inverted: true
        paintColor: bar.themePalette.frame
    }

    FrameShoulder {
        x: parent.width - bar.bezel - width
        anchors.bottom: strip.top
        width: bar.frameCornerRadius
        visible: width > 0
        inverted: true
        paintColor: bar.themePalette.frame
    }

    Item {
        id: strip
        anchors { left: parent.left; bottom: parent.bottom; right: parent.right }
        height: bar.rowHeight

        TapHandler {
            acceptedButtons: Qt.RightButton
            onTapped: eventPoint => {
                if (!trayDrawer.containsX(eventPoint.position.x))
                    trayDrawer.expanded = false;
                if (bar.pendingPins) return;
                if (eventPoint.position.x >= trayDrawer.x && eventPoint.position.x < dateButton.x + dateButton.width) return;
                pinOverlay.clickX = Math.round(strip.x + eventPoint.position.x);
                pinOverlay.mode = "context";
                editAction.forceActiveFocus();
            }
        }

        TapHandler {
            acceptedButtons: Qt.LeftButton | Qt.MiddleButton
            enabled: trayDrawer.expanded
            onTapped: eventPoint => {
                if (!trayDrawer.containsX(eventPoint.position.x))
                    trayDrawer.expanded = false;
            }
        }

        Item {
            anchors.centerIn: parent
            width: Math.min(Math.max(0, 2 * trayDrawer.x - parent.width - 12),
                appPicker.width + 12 + (running.count ? 8 + running.naturalWidth : 0))
            height: parent.height

            BarButton {
                id: appPicker
                anchors.left: parent.left
                anchors.leftMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                width: bar.slotSize
                Accessible.name: "Open application launcher"
                contentItem: Item {
                    Grid {
                        anchors.centerIn: parent
                        columns: 2
                        spacing: 1

                        Repeater {
                            model: 4
                            Rectangle {
                                width: 5
                                height: 5
                                radius: 1
                                color: bar.themePalette.ink
                            }
                        }
                    }
                }
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
                    readonly property bool isRunning: modelData.windows.length > 0
                    readonly property bool isFocused: modelData.windows.some(window => window.activated)
                    readonly property string appName: modelData.entry?.name || window?.title || window?.appId || "Application"
                    width: bar.slotSize
                    Accessible.name: appName + (modelData.pinned ? ", pinned" : "")
                        + (isFocused ? ", focused" : isRunning ? ", running" : "")
                    contentItem: Item {
                        AppIcon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            y: 4
                            width: 24
                            height: width
                            opacity: task.isRunning ? 1 : 0.72
                            source: Quickshell.iconPath(task.modelData.entry?.icon || "application-x-executable", "application-x-executable")
                        }
                        Rectangle {
                            visible: task.isRunning
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 4
                            width: task.isFocused ? 10 : 4
                            height: 2
                            radius: 1
                            color: task.isFocused ? bar.themePalette.accent : bar.themePalette.muted
                        }
                    }
                    onClicked: bar.activateTask(modelData)
                }
            }
        }

        Item {
            id: trayDrawer
            readonly property string vpnWidget: "io.github.grichard99.omaproton-vpn"
            property bool expanded: false
            property string vpnStatus: ""
            readonly property bool revealed: expanded || trayPopup.opened
            readonly property int slotCount: tray.count + (vpnStatus ? 1 : 0)
            anchors.right: dateButton.left
            anchors.rightMargin: visible ? 6 : 0
            anchors.verticalCenter: parent.verticalCenter
            width: visible ? trayArrow.width + tray.width : 0
            height: bar.slotSize
            visible: slotCount > 0
            function containsX(panelX) {
                return panelX >= x && panelX < x + width;
            }

            onExpandedChanged: if (expanded) vpnProbe.running = true
            onVisibleChanged: if (!visible) expanded = false

            HyprlandFocusGrab {
                active: bar.visible && trayDrawer.expanded && !trayPopup.opened
                windows: [bar]
                onCleared: trayDrawer.expanded = false
            }

            Connections {
                target: trayPopup
                function onOpenedChanged() {
                    if (trayPopup.opened) trayDrawer.expanded = false;
                }
            }

            Timer {
                interval: trayDrawer.expanded ? 4000 : 30000
                running: bar.visible
                repeat: true
                triggeredOnStart: true
                onTriggered: vpnProbe.running = true
            }

            Process {
                id: vpnProbe
                command: ["omarchy-shell", trayDrawer.vpnWidget, "status"]
                stdout: StdioCollector { id: vpnOutput }
                onExited: exitCode => trayDrawer.vpnStatus = exitCode === 0 ? vpnOutput.text.trim() : ""
            }

            BarButton {
                id: trayArrow
                width: 28
                height: width
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                Accessible.name: trayDrawer.revealed ? "Hide system tray" : "Show system tray"
                onClicked: trayDrawer.expanded = !trayDrawer.expanded
                contentItem: Item {
                    Shape {
                        anchors.centerIn: parent
                        width: 10
                        height: 10
                        preferredRendererType: Shape.CurveRenderer
                        ShapePath {
                            fillColor: "transparent"
                            strokeColor: trayArrow.hovered ? bar.themePalette.ink : bar.themePalette.muted
                            strokeWidth: 1.5
                            capStyle: ShapePath.RoundCap
                            joinStyle: ShapePath.RoundJoin
                            startX: 7
                            startY: 1.5
                            PathLine { x: 3; y: 5 }
                            PathLine { x: 7; y: 8.5 }
                        }
                    }
                }
            }

            ListView {
                id: tray
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                readonly property int slotExtent: 28
                width: trayDrawer.revealed ? Math.min(trayDrawer.slotCount * slotExtent, Math.floor(strip.width / 4)) : 0
                height: slotExtent
                enabled: trayDrawer.revealed
                Behavior on width {
                    enabled: bar.motionEnabled
                    NumberAnimation { duration: trayDrawer.revealed ? 220 : 165; easing.type: Easing.OutCubic }
                }
                orientation: ListView.Horizontal
                layoutDirection: Qt.RightToLeft
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentWidth > width
                clip: true
                model: SystemTray.items.values.filter(item => item.status !== Status.Passive)

                header: BarButton {
                    visible: !!trayDrawer.vpnStatus
                    width: visible ? tray.slotExtent : 0
                    height: tray.slotExtent
                    Accessible.name: "OmaProton VPN, " + trayDrawer.vpnStatus
                    contentItem: Item {
                        Item {
                            anchors.centerIn: parent
                            width: 16
                            height: width
                            Shape {
                                width: 24
                                height: width
                                scale: 16 / 24
                                anchors.centerIn: parent
                                preferredRendererType: Shape.CurveRenderer
                                ShapePath {
                                    fillColor: bar.themePalette.ink
                                    strokeWidth: -1
                                    // Proton VPN mark from Simple Icons (CC0).
                                    PathSvg { path: "m10.176 20.058.858-1.28 6.513-9.838c.57-.86.026-2.014-1.005-2.131L.378 4.95l8.373 15.055a.84.84 0 0 0 1.424.052h.001zM23.586 7.14l-9.662 14.61c-1.036 1.567-3.38 1.478-4.293-.162l-.093-.168c.3-.01.594-.086.855-.235a1.85 1.85 0 0 0 .612-.57l.86-1.28 6.516-9.844c.46-.694.525-1.56.173-2.314a2.375 2.375 0 0 0-1.899-1.364L.493 3.956l-.476-.054C-.163 2.392 1.101.95 2.784 1.143l18.991 2.16c1.856.21 2.835 2.289 1.812 3.838z" }
                                }
                            }
                        }
                    }
                    onClicked: {
                        trayDrawer.expanded = false;
                        Qt.callLater(() => Quickshell.execDetached(["omarchy-shell", trayDrawer.vpnWidget, "open"]));
                    }
                }

                delegate: BarButton {
                    id: trayButton
                    required property var modelData
                    width: tray.slotExtent
                    height: width
                    Accessible.name: modelData.title || modelData.tooltipTitle || modelData.id || "Tray application"
                    selected: trayPopup.opened && trayPopup.menu === modelData.menu

                    function openMenu() {
                        if (modelData.menu) {
                            trayPopup.open(modelData.menu);
                        } else {
                            const anchor = bar.contentItem.mapFromItem(trayButton, width / 2, 0);
                            modelData.display(bar, Math.round(anchor.x), Math.round(anchor.y));
                        }
                    }

                    contentItem: Item {
                        Image {
                            readonly property int pixelSize: Math.round(width * Screen.devicePixelRatio)
                            anchors.centerIn: parent
                            width: 16
                            height: width
                            sourceSize: Qt.size(pixelSize, pixelSize)
                            source: trayButton.modelData.icon
                            fillMode: Image.PreserveAspectFit
                        }
                    }

                    onClicked: {
                        if (modelData.onlyMenu) openMenu();
                        else modelData.activate();
                    }

                    TapHandler {
                        acceptedButtons: Qt.RightButton | Qt.MiddleButton
                        onTapped: (eventPoint, button) => {
                            if (button === Qt.MiddleButton) trayButton.modelData.secondaryActivate();
                            else trayButton.openMenu();
                        }
                    }

                    WheelHandler {
                        target: null
                        onWheel: event => {
                            const horizontal = Math.abs(event.angleDelta.x) > Math.abs(event.angleDelta.y);
                            const delta = horizontal ? event.angleDelta.x : event.angleDelta.y;
                            if (delta) trayButton.modelData.scroll(delta, horizontal);
                        }
                    }
                }
            }
        }

        BarButton {
            id: dateButton
            hoverEnabled: false
            anchors.right: parent.right
            anchors.rightMargin: bar.bezel + 3
            anchors.verticalCenter: parent.verticalCenter
            width: contentItem.implicitWidth + 20
            text: Qt.locale().toString(bar.today, "ddd d MMM")
            Accessible.name: (bar.calendarOpen ? "Close calendar, " : "Open calendar, ")
                + Qt.locale().toString(bar.today, Locale.LongFormat)
            background: Rectangle {
                radius: 7
                color: "transparent"
                border.width: dateButton.visualFocus ? 1 : 0
                border.color: bar.themePalette.muted
            }
            onClicked: {
                if (!bar.calendarOpen) Hyprland.refreshMonitors();
                bar.calendarOpen = !bar.calendarOpen;
            }
        }
    }
}
