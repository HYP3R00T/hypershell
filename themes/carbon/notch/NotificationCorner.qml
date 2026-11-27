import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "/usr/share/omarchy/shell/plugins/notifications/Markup.js" as Markup

PanelWindow {
    id: corner

    required property ShellScreen targetScreen
    required property NotchPalette themePalette
    required property bool enabledForTheme
    required property bool blockedByFullscreen
    required property bool motionEnabled
    required property int bezel
    required property int curveRadius
    property bool peek: false
    property bool pinned: false
    property bool waitForExit: false
    property string selectedKey: ""
    property string incomingKey: ""
    property var liveRows: []
    property bool doNotDisturb: false
    property bool bridgeReady: false
    property bool refreshPending: false
    readonly property bool open: peek || pinned || incomingKey !== ""
    onOpenChanged: requestSnapshot()
    readonly property bool previewOnly: !peek && !pinned && incomingKey !== ""
    readonly property string notificationDir: Quickshell.env("HOME") + "/.local/state/omarchy/notifications"
    readonly property int maxListHeight: Math.max(100, Math.min(370, (targetScreen?.height ?? 800) - 80))
    readonly property int drawerWidth: Math.max(0, width - bezel - curveRadius)
    readonly property var entries: {
        const byKey = new Map();
        for (const row of history.rows.concat(bridgeReady ? liveRows : current.rows)) byKey.set(row.key, row);
        return [...byKey.values()].sort((a, b) => b.time - a.time).slice(0, 50);
    }

    screen: targetScreen
    visible: enabledForTheme && !!targetScreen && !blockedByFullscreen
    onVisibleChanged: if (!visible) dismiss()
    anchors { top: true; right: true }
    implicitWidth: Math.min(365 + bezel + curveRadius, targetScreen?.width ?? 365)
    implicitHeight: maxListHeight + heading.height + bezel + 24
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "linear-carbon-notification-corner"
    WlrLayershell.keyboardFocus: pinned ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    mask: Region {
        item: hotCorner
        Region { item: corner.open ? drawer : null }
    }

    HyprlandFocusGrab {
        active: corner.visible && corner.pinned
        windows: [corner]
        onCleared: corner.dismiss()
    }

    function dismiss() {
        pinned = false;
        peek = false;
        selectedKey = "";
        incomingKey = "";
        waitForExit = pointer.hovered;
        reveal.stop();
        hide.stop();
        arrivalTimeout.stop();
    }

    function requestSnapshot() {
        if (!enabledForTheme) return;
        if (snapshot.running) refreshPending = true;
        else {
            snapshot.command = ["omarchy-shell", "notifications", "cornerSnapshot", open && pointer.hovered ? "1" : "0"];
            snapshot.running = true;
        }
    }

    function parsePayload(data) {
        if (data.length > 3300000) return null;
        try {
            return JSON.parse(data);
        } catch (_) {
            return null;
        }
    }

    function readRows(source, native) {
        if (!Array.isArray(source)) return null;
        return source.slice(0, 100)
            .filter(row => row && typeof row.key === "string" && /^[A-Za-z0-9_-]{1,120}$/.test(row.key)
                && typeof row.ts === "number" && Number.isFinite(row.ts)
                && row.ts > 0 && row.ts < 8640000000000)
            .map(row => ({
                key: row.key,
                time: row.ts,
                live: native,
                app: typeof row.app === "string" ? row.app.slice(0, 96) : "",
                icon: typeof row.appIcon === "string" && /^[a-zA-Z0-9_.-]{1,256}$/.test(row.appIcon) ? row.appIcon : "",
                summary: typeof row.summary === "string" ? row.summary.slice(0, 240) : "",
                body: typeof row.body === "string" ? Markup.oneLine(row.body.slice(0, 4096)).slice(0, 900) : "",
                actions: native && Array.isArray(row.actions)
                    ? row.actions.slice(0, 4).map(label => typeof label === "string" ? label.slice(0, 70) : "Action") : []
            }))
            .filter(row => row.summary || row.body);
    }

    function updateLive(data) {
        const state = parsePayload(data);
        const rows = readRows(state?.rows, true);
        if (!rows || typeof state.dnd !== "boolean") {
            bridgeReady = false;
            return;
        }
        doNotDisturb = state.dnd;
        if (doNotDisturb) {
            incomingKey = "";
            arrivalTimeout.stop();
        } else if (bridgeReady && visible) {
            const newest = rows.find(row => !liveRows.some(previous => previous.key === row.key && previous.time === row.time));
            if (newest && !pinned && !peek) {
                incomingKey = newest.key;
                arrivalTimeout.restart();
            } else if (incomingKey && !rows.some(row => row.key === incomingKey)) {
                incomingKey = "";
            }
        }
        bridgeReady = true;
        if (JSON.stringify(rows) !== JSON.stringify(liveRows)) liveRows = rows;
    }

    function invokeNotice(key, index) {
        Quickshell.execDetached(["omarchy-shell", "notifications", "cornerAction", key, String(index)]);
    }

    function removeNotice(key) {
        Quickshell.execDetached(["omarchy-shell", "notifications", "cornerDismiss", key]);
        if (selectedKey === key) selectedKey = "";
        if (incomingKey === key) incomingKey = "";
    }

    function clearNotices() {
        selectedKey = "";
        incomingKey = "";
        arrivalTimeout.stop();
        Quickshell.execDetached(["omarchy-shell", "notifications", "cornerClearAll"]);
    }

    Timer {
        running: corner.enabledForTheme
        triggeredOnStart: true
        repeat: true
        interval: 12000
        onTriggered: corner.requestSnapshot()
    }
    Timer { id: arrivalTimeout; interval: 1500; onTriggered: corner.incomingKey = "" }
    FileView {
        path: Quickshell.env("XDG_RUNTIME_DIR") + "/linear-carbon-notification-signal"
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload();
            corner.requestSnapshot();
        }
        onLoaded: corner.requestSnapshot()
    }
    Process {
        id: snapshot
        stdout: StdioCollector { id: liveOutput }
        onExited: function(code) {
            if (code === 0) corner.updateLive(liveOutput.text);
            else corner.bridgeReady = false;
            if (corner.refreshPending) {
                corner.refreshPending = false;
                Qt.callLater(corner.requestSnapshot);
            }
        }
    }

    Process {
        id: toggleDnd
        command: ["omarchy-shell", "notifications", "toggleDnd"]
        onExited: corner.requestSnapshot()
    }

    component HeaderIconButton: Controls.Button {
        id: button
        required property url iconSource
        property bool active: false
        width: 32
        height: 28
        padding: 0
        hoverEnabled: true
        opacity: enabled || active ? 1 : 0.45
        contentItem: Item {
            IconImage {
                id: glyph
                anchors.centerIn: parent
                implicitSize: 15
                source: button.iconSource
                visible: false
            }
            MultiEffect {
                anchors.fill: glyph
                source: glyph
                colorization: 1
                colorizationColor: button.active ? corner.themePalette.frame : corner.themePalette.ink
            }
        }
        background: Rectangle {
            radius: 6
            color: button.active ? corner.themePalette.accent
                : button.hovered || button.visualFocus ? corner.themePalette.hover : corner.themePalette.tile
        }
    }

    function pinDrawer() {
        if (pinned) return;
        reveal.stop();
        hide.stop();
        pinned = true;
        pane.forceActiveFocus();
    }

    component NotificationFile: FileView {
        id: file
        property var rows: []
        preload: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoadFailed: rows = []
        onLoaded: rows = corner.readRows(corner.parsePayload(text()), false) ?? []
    }

    NotificationFile { id: history; path: corner.notificationDir + "/history.json" }
    NotificationFile { id: current; path: corner.notificationDir + "/live.json" }

    Timer { id: reveal; interval: 150; onTriggered: corner.peek = pointer.hovered }
    Timer {
        id: hide
        interval: 180
        onTriggered: {
            corner.peek = false;
            corner.selectedKey = "";
        }
    }

    FocusScope {
        id: pane
        anchors.fill: parent
        Keys.onEscapePressed: corner.dismiss()

        TapHandler {
            onTapped: corner.pinDrawer()
        }

        HoverHandler {
            id: pointer
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onHoveredChanged: {
                if (hovered) {
                    hide.stop();
                    if (corner.previewOnly) corner.peek = true;
                    else if (!corner.open && !corner.waitForExit) reveal.restart();
                } else {
                    corner.waitForExit = false;
                    reveal.stop();
                    if (!corner.pinned) hide.restart();
                }
                if (corner.open) corner.requestSnapshot();
            }
        }

        Shape {
            id: silhouette
            anchors.fill: parent
            visible: drawer.visible
            preferredRendererType: Shape.CurveRenderer

            readonly property real leftEdge: drawer.x
            readonly property real rightEdge: width - corner.bezel
            readonly property real topEdge: corner.bezel
            readonly property real bottomEdge: drawer.y + drawer.height
            readonly property real curve: Math.max(0, Math.min(corner.curveRadius,
                (rightEdge - leftEdge) / 2, (bottomEdge - topEdge) / 2))

            // Keep both curves tangent to the visible bezel and overlap it by one pixel.
            ShapePath {
                fillColor: corner.themePalette.frame
                strokeWidth: -1
                startX: silhouette.leftEdge - silhouette.curve
                startY: silhouette.topEdge - 1

                PathLine { x: silhouette.leftEdge - silhouette.curve; y: silhouette.topEdge }
                PathArc {
                    x: silhouette.leftEdge
                    y: silhouette.topEdge + silhouette.curve
                    radiusX: silhouette.curve
                    radiusY: silhouette.curve
                }
                PathLine { x: silhouette.leftEdge; y: silhouette.bottomEdge - silhouette.curve }
                PathArc {
                    x: silhouette.leftEdge + silhouette.curve
                    y: silhouette.bottomEdge
                    radiusX: silhouette.curve
                    radiusY: silhouette.curve
                    direction: PathArc.Counterclockwise
                }
                PathLine { x: silhouette.rightEdge - silhouette.curve; y: silhouette.bottomEdge }
                PathArc {
                    x: silhouette.rightEdge
                    y: silhouette.bottomEdge + silhouette.curve
                    radiusX: silhouette.curve
                    radiusY: silhouette.curve
                }
                PathLine { x: silhouette.rightEdge + 1; y: silhouette.bottomEdge + silhouette.curve }
                PathLine { x: silhouette.rightEdge + 1; y: silhouette.topEdge - 1 }
                PathLine { x: silhouette.leftEdge - silhouette.curve; y: silhouette.topEdge - 1 }
            }
        }

        Item {
            id: drawer
            visible: width > 0 && height > 0
            clip: true
            anchors { top: parent.top; right: parent.right }
            anchors.topMargin: Math.max(0, corner.bezel - 1)
            anchors.rightMargin: Math.max(0, corner.bezel - 1)
            width: corner.open ? corner.drawerWidth : 0
            height: corner.open ? heading.height + list.height + 12 : 0

            Behavior on width {
                enabled: corner.motionEnabled
                NumberAnimation { duration: corner.open ? 220 : 150; easing.type: Easing.OutCubic }
            }
            Behavior on height {
                enabled: corner.motionEnabled
                NumberAnimation { duration: corner.open ? 220 : 150; easing.type: Easing.OutCubic }
            }

            Item {
                anchors { right: parent.right; top: parent.top }
                width: corner.drawerWidth
                height: heading.height + list.height + 12
                visible: corner.open

                Item {
                    id: heading
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 46
                    Text {
                        anchors { left: parent.left; right: dndButton.left }
                        anchors.leftMargin: 14
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Notifications"
                        textFormat: Text.PlainText
                        elide: Text.ElideRight
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                        color: corner.themePalette.ink
                    }
                    HeaderIconButton {
                        id: dndButton
                        anchors.right: clearButton.left
                        anchors.rightMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        iconSource: Quickshell.iconPath(corner.doNotDisturb
                            ? "notifications-disabled-symbolic" : "preferences-system-notifications-symbolic", true)
                        active: corner.doNotDisturb
                        enabled: corner.bridgeReady && !toggleDnd.running
                        Accessible.name: "Do Not Disturb"
                        Accessible.checkable: true
                        Accessible.checked: corner.doNotDisturb
                        onClicked: toggleDnd.running = true
                    }
                    HeaderIconButton {
                        id: clearButton
                        anchors.right: parent.right
                        anchors.rightMargin: 20
                        anchors.verticalCenter: parent.verticalCenter
                        iconSource: Qt.resolvedUrl("icons/list-x.svg")
                        Accessible.name: "Clear all notifications"
                        enabled: corner.bridgeReady && corner.entries.length > 0
                        onClicked: corner.clearNotices()
                    }
                }

                ListView {
                    id: list
                    anchors { left: parent.left; top: heading.bottom; right: parent.right }
                    anchors.margins: 8
                    anchors.topMargin: 0
                    height: Math.min(corner.maxListHeight, Math.max(44, contentHeight))
                    model: !drawer.visible ? []
                        : corner.previewOnly ? corner.entries.filter(row => row.key === corner.incomingKey) : corner.entries
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

                    delegate: Controls.Button {
                        id: notice
                        required property var modelData
                        readonly property bool expanded: corner.selectedKey === modelData.key
                        width: ListView.view.width - 6
                        height: copy.implicitHeight + 16
                        padding: 0
                        hoverEnabled: true
                        Accessible.name: modelData.summary || modelData.body
                        onClicked: corner.selectedKey = expanded ? "" : modelData.key
                        background: Rectangle {
                            radius: 7
                            color: notice.expanded ? corner.themePalette.selection
                                : notice.hovered || notice.visualFocus ? corner.themePalette.hover : "transparent"
                        }
                        contentItem: Item {
                            IconImage {
                                id: sourceIcon
                                anchors { left: parent.left; top: parent.top }
                                anchors.margins: 8
                                width: 24
                                height: width
                                source: notice.modelData.icon ? Quickshell.iconPath(notice.modelData.icon, true) : ""
                                visible: status === Image.Ready
                            }
                            Column {
                                id: copy
                                anchors { left: parent.left; right: parent.right; top: parent.top }
                                anchors.margins: 8
                                anchors.leftMargin: sourceIcon.visible ? 40 : 8
                                spacing: 4
                                Item {
                                    width: parent.width
                                    height: appName.implicitHeight
                                    Text {
                                        id: appName
                                        anchors { left: parent.left; right: timestamp.left }
                                        anchors.rightMargin: 8
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: notice.modelData.app
                                        textFormat: Text.PlainText
                                        elide: Text.ElideRight
                                        color: corner.themePalette.muted
                                        font.pixelSize: 11
                                    }
                                    Text {
                                        id: timestamp
                                        anchors.right: removeButton.visible ? removeButton.left : parent.right
                                        anchors.rightMargin: removeButton.visible ? 4 : 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: Qt.formatTime(new Date(notice.modelData.time * 1000), "HH:mm")
                                        textFormat: Text.PlainText
                                        color: corner.themePalette.muted
                                        font.pixelSize: 11
                                    }
                                    Controls.Button {
                                        id: removeButton
                                        anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                                        width: 24
                                        height: 24
                                        visible: corner.bridgeReady
                                        Accessible.name: "Dismiss notification"
                                        padding: 0
                                        hoverEnabled: true
                                        onClicked: corner.removeNotice(notice.modelData.key)
                                        contentItem: Item {
                                            Repeater {
                                                model: [-45, 45]
                                                Rectangle {
                                                    required property int modelData
                                                    anchors.centerIn: parent
                                                    width: 8
                                                    height: 1
                                                    rotation: modelData
                                                    antialiasing: true
                                                    color: removeButton.hovered ? corner.themePalette.ink : corner.themePalette.muted
                                                }
                                            }
                                        }
                                        background: Rectangle {
                                            radius: 5
                                            color: removeButton.hovered || removeButton.visualFocus
                                                ? corner.themePalette.selection : "transparent"
                                        }
                                    }
                                }
                                Text {
                                    visible: text.length > 0
                                    width: parent.width
                                    text: notice.modelData.summary
                                    textFormat: Text.PlainText
                                    color: corner.themePalette.ink
                                    font.pixelSize: 13
                                    font.weight: Font.DemiBold
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                                Flow {
                                    visible: notice.expanded && notice.modelData.live
                                    width: parent.width
                                    spacing: 4
                                    Repeater {
                                        model: parent.visible ? ["Open", ...notice.modelData.actions] : []
                                        delegate: Controls.Button {
                                            required property int index
                                            required property string modelData
                                            text: modelData
                                            leftPadding: 8
                                            rightPadding: 8
                                            contentItem: Text {
                                                text: parent.text
                                                textFormat: Text.PlainText
                                                color: corner.themePalette.ink
                                                font.pixelSize: 11
                                            }
                                            background: Rectangle {
                                                radius: 5
                                                color: parent.hovered ? corner.themePalette.hover : corner.themePalette.tile
                                            }
                                            onClicked: corner.invokeNotice(notice.modelData.key, index - 1)
                                        }
                                    }
                                }
                                Text {
                                    visible: text.length > 0
                                    width: parent.width
                                    text: notice.modelData.body
                                    textFormat: Text.PlainText
                                    color: corner.themePalette.muted
                                    font.pixelSize: 12
                                    wrapMode: Text.Wrap
                                    maximumLineCount: notice.expanded ? 12 : 2
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: list
                    visible: !list.count
                    text: "No recent notifications"
                    textFormat: Text.PlainText
                    color: corner.themePalette.muted
                    font.pixelSize: 12
                }
            }
        }

        Item {
            id: hotCorner
            anchors { top: parent.top; right: parent.right }
            width: 22
            height: 22
        }
    }
}
