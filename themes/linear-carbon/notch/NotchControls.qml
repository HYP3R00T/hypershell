import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import "/usr/share/omarchy/shell/plugins/panels/audio/Model.js" as AudioModel
import "/usr/share/omarchy/shell/plugins/panels/network/Model.js" as NetModel

Item {
    id: hub
    required property bool active
    required property NotchPalette themePalette
    signal dismissRequested()
    readonly property color ink: themePalette.ink
    readonly property color muted: themePalette.muted
    readonly property color accent: themePalette.accent
    readonly property color tile: themePalette.tile
    readonly property color detail: Qt.tint(ink, Qt.rgba(muted.r, muted.g, muted.b, 0.35))
    readonly property color selection: themePalette.selection
    readonly property color hoverFill: themePalette.hover
    readonly property int actionWidth: Math.max(76, textSize * 5 + 18)
    readonly property int pageTopInset: 18
    readonly property int pageBottomInset: 14
    property string selected: "agents"
    property int textSize: 12
    property string notice: ""
    property var displayData: ({})
    property string displayName: ""
    property string scale: ""
    property real brightness: -1
    property bool nightLight: false
    property var powerInfo: ({})
    property var profiles: []
    property string profile: ""
    property var ethernet: ({})
    property var connection: ({})
    property var traffic: ({})
    property string dns: ""
    property var agents: []
    property real agentTokens: 0
    property var weather: ({})
    property bool weatherFailed: false
    property double weatherTime: 0
    readonly property string helper: Quickshell.shellDir + "/notch-data.py"
    readonly property string configPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/shell.json"

    readonly property var sections: [
        { key: "agents", label: "Agents", icon: "bot", view: agentsPage },
        { key: "audio", label: "Audio", icon: "audio-lines", view: audioPage },
        { key: "display", label: "Display", icon: "monitor", view: displayPage },
        { key: "power", label: "Power", icon: "battery-medium", view: powerPage },
        { key: "ethernet", label: "Ethernet", icon: "ethernet-port", view: ethernetPage },
        { key: "weather", label: "Weather", icon: "cloud-sun", view: weatherPage }
    ]
    readonly property var nodes: active && selected === "audio" ? Pipewire.nodes.values : []
    readonly property var sink: active && selected === "audio" ? Pipewire.defaultAudioSink : null
    readonly property var source: active && selected === "audio" ? Pipewire.defaultAudioSource : null
    property var sinkAvailability: ({})
    property var sourceAvailability: ({})
    property string outputSinkName: ""
    readonly property var volumeSink: nodes.find(node => node && node.name === outputSinkName) ?? sink
    readonly property var outputs: nodes.filter(node => node && node.isSink && !node.isStream && (node === sink || sinkAvailability[node.name] !== false))
    readonly property var inputs: nodes.filter(node => node && !node.isSink && !node.isStream && node.name !== "quickshell"
        && (node === source || AudioModel.isAudioSource(node) || AudioModel.isUntypedSource(node, sourceAvailability)))
    readonly property var streams: nodes.filter(node => AudioModel.isPlaybackStream(node) && node.audio
        && !String(node.name || "").startsWith("omarchy_speaker_tuning"))
    readonly property bool untypedInput: !!source && !source.audio
    property var virtualInputLevel: null
    PwObjectTracker { objects: [...hub.outputs, ...hub.inputs, ...hub.streams] }

    clip: true
    implicitHeight: Math.min(410, Math.max(sidebar.implicitHeight + 18,
        content.implicitHeight + pageTopInset + pageBottomInset))

    function number(value, decimals = 0) {
        return Number(value).toLocaleString(Qt.locale(), "f", decimals);
    }

    function audioChoices(list) {
        return AudioModel.rowSnapshot(list).map(row => ({text: AudioModel.nodeLabel(nodeFor(row)), value: row}));
    }

    function nodeFor(row) {
        return row ? nodes.find(node => node && node.id === row.id && node.name === row.name) ?? null : null;
    }

    function selectAudio(node, input) {
        if (!node || actionProc.running) return;
        if (input) {
            if (node.audio) Pipewire.preferredDefaultAudioSource = node;
        } else {
            Pipewire.preferredDefaultAudioSink = node;
        }
        run([input ? "omarchy-audio-input-set-default" : "omarchy-audio-output-set-default",
             String(node.id), String(node.name)]);
    }

    function selectSection(key) {
        if (key === selected) return;
        selected = key;
        viewport.contentY = 0;
        notice = "";
    }

    function readSection() {
        if (!active) return;
        switch (selected) {
        case "audio": sinkRead.read(); sourceRead.read(); outputRead.read(); if (untypedInput) inputRead.read(); break;
        case "display": displaysRead.read(); nightRead.read(); textSizeRead.read(); break;
        case "power": powerRead.read(); profilesRead.read(); break;
        case "ethernet": networkRead.read(); dnsRead.read(); break;
        case "agents": agentsRead.read(); break;
        case "weather": if (Date.now() - weatherTime > 300000) weatherRead.read(); break;
        }
    }

    function run(argv, refresh = true) {
        if (actionProc.running) return;
        notice = "";
        actionProc.refresh = refresh;
        actionProc.command = argv;
        actionProc.running = true;
    }

    function readBrightness() {
        if (displayName && !brightnessRead.running) {
            brightnessRead.monitor = displayName;
            brightnessRead.read();
        }
    }

    function pairs(raw) {
        const result = {};
        for (const line of raw.trim().split("\n")) {
            const split = line.indexOf("\t");
            if (split > 0) result[line.slice(0, split)] = line.slice(split + 1);
        }
        return result;
    }

    onActiveChanged: {
        if (active) textSizeRead.read();
        readSection();
    }
    onSelectedChanged: readSection()
    onSinkChanged: if (active && selected === "audio") outputRead.read()
    onSourceChanged: {
        virtualInputLevel = null;
        if (active && selected === "audio" && untypedInput) inputRead.read();
    }

    FileView {
        path: hub.configPath.replace(/\.json$/, ".toml")
        watchChanges: true
        printErrors: false
        onFileChanged: { reload(); textSizeRead.read(); }
    }
    Timer {
        interval: 1500
        repeat: true
        running: hub.active && hub.selected === "ethernet"
        onTriggered: networkRead.read()
    }
    Timer {
        interval: 5000
        repeat: true
        running: hub.active && ["audio", "display", "power", "agents"].includes(hub.selected)
        onTriggered: hub.readSection()
    }

    component Reader: Process {
        id: reader
        signal received(string data)
        signal failed()
        function read() { if (!running) running = true; }
        stdout: StdioCollector { id: output; waitForEnd: true }
        onExited: function(code) {
            if (code === 0) received(output.text);
            else failed();
        }
    }

    Reader {
        id: sinkRead
        command: ["omarchy-audio-sink-availability"]
        onReceived: data => hub.sinkAvailability = AudioModel.parseSinkAvailability(data)
    }
    Reader {
        id: sourceRead
        command: ["omarchy-audio-sink-availability", "sources"]
        onReceived: data => hub.sourceAvailability = AudioModel.parseSinkAvailability(data)
    }
    Reader {
        id: outputRead
        command: ["omarchy-audio-output-sink"]
        onReceived: data => hub.outputSinkName = data.trim()
    }
    Process {
        id: inputRead
        property var request: null
        function read() {
            if (running || !hub.untypedInput) return;
            request = AudioModel.nodeRow(hub.source);
            if (!request) return;
            command = ["wpctl", "get-volume", String(request.id)];
            running = true;
        }
        stdout: StdioCollector { id: inputLevelOutput }
        onExited: function(code) {
            if (code !== 0 || hub.nodeFor(request) !== hub.source) return;
            const match = /^Volume:\s+([0-9.]+)(?:\s+(\[MUTED\]))?/.exec(inputLevelOutput.text.trim());
            if (match) hub.virtualInputLevel = {volume: Number(match[1]), muted: !!match[2]};
        }
    }
    Reader {
        id: textSizeRead
        command: ["omarchy-display-text-size"]
        onReceived: data => {
            const match = /^text size:\s+(\d+)/m.exec(data);
            if (match) hub.textSize = Number(match[1]);
        }
    }
    Reader {
        id: displaysRead
        command: ["hyprctl", "-j", "monitors", "all"]
        onReceived: data => {
            try {
                const displays = JSON.parse(data).map(monitor => ({
                    name: monitor.name, enabled: monitor.disabled !== true,
                    focused: monitor.focused, scale: monitor.scale
                }));
                const focused = displays.find(monitor => monitor.focused && monitor.enabled)
                    || displays.find(monitor => monitor.enabled);
                hub.displayData = {all: displays};
                hub.scale = focused ? String(focused.scale) : "";
                if (!displays.some(monitor => monitor.enabled && monitor.name === hub.displayName))
                    hub.displayName = focused?.name ?? "";
                hub.readBrightness();
            } catch (_) {}
        }
    }
    Reader {
        id: brightnessRead
        property string monitor
        command: ["omarchy-brightness-display", "--no-osd", "--monitor", monitor]
        onReceived: data => {
            const amount = parseFloat(data.trim());
            if (monitor === hub.displayName) hub.brightness = Number.isFinite(amount) ? amount : -1;
            else Qt.callLater(hub.readBrightness);
        }
        onFailed: {
            if (monitor === hub.displayName) hub.brightness = -1;
            else Qt.callLater(hub.readBrightness);
        }
    }
    Reader {
        id: nightRead
        command: ["omarchy-toggle-nightlight", "--status"]
        onReceived: data => { try { hub.nightLight = JSON.parse(data).enabled; } catch (_) {} }
    }
    Reader {
        id: powerRead
        command: ["omarchy-battery-status", "--shell"]
        onReceived: data => {
            const info = hub.pairs(data);
            if (Object.keys(info).length) hub.powerInfo = info;
        }
    }
    Reader {
        id: profilesRead
        command: ["omarchy-powerprofiles-list", "--active-state"]
        onReceived: data => {
            const entries = hub.pairs(data);
            if (!Object.keys(entries).length) return;
            hub.profiles = Object.keys(entries);
            hub.profile = hub.profiles.find(key => entries[key] === "1") || "";
        }
    }
    Reader {
        id: networkRead
        command: ["omarchy-network-status", "--verbose"]
        onReceived: data => {
            const sample = NetModel.parseKeyValue(data);
            const wired = sample.type === "ethernet" ? sample : {};
            hub.ethernet = wired;
            hub.traffic = NetModel.throughputState(hub.traffic, wired, Date.now() / 1000);
            hub.connection = NetModel.pingLatencyState(hub.connection, wired, 24, 5);
        }
        onFailed: {
            hub.ethernet = ({});
            hub.traffic = ({});
            hub.connection = ({});
        }
    }
    Reader {
        id: dnsRead
        command: ["omarchy-dns"]
        onReceived: data => hub.dns = data.trim()
    }
    Reader {
        id: agentsRead
        command: ["python3", hub.helper, "agents"]
        onReceived: data => {
            try {
                const snapshot = JSON.parse(data);
                hub.agents = snapshot.providers;
                hub.agentTokens = snapshot.tokens;
            } catch (_) {}
        }
    }
    Reader {
        id: weatherRead
        command: ["python3", hub.helper, "weather"]
        onReceived: data => {
            try {
                hub.weather = JSON.parse(data);
                hub.weatherFailed = !hub.weather.name;
                if (!hub.weatherFailed) hub.weatherTime = Date.now();
            } catch (_) { hub.weatherFailed = true; }
        }
        onFailed: hub.weatherFailed = true
    }
    Process {
        id: actionProc
        property bool refresh: true
        onExited: function(code) {
            if (code !== 0) hub.notice = "The command could not be completed";
            if (refresh) hub.readSection();
        }
    }

    Item {
        width: 56
        height: parent.height
        Column {
            id: sidebar
            anchors.horizontalCenter: parent.horizontalCenter
            y: 10
            spacing: 3
            Repeater {
                model: hub.sections
                delegate: Controls.Button {
                    id: tab
                    required property var modelData
                    objectName: "notch-" + modelData.key
                    width: 40
                    height: 36
                    leftPadding: 0
                    rightPadding: 0
                    topPadding: 0
                    bottomPadding: 0
                    hoverEnabled: true
                    readonly property bool chosen: hub.selected === modelData.key
                    Accessible.role: Accessible.RadioButton
                    Accessible.checkable: true
                    Accessible.checked: chosen
                    Accessible.name: modelData.label
                    onClicked: hub.selectSection(modelData.key)
                    background: Rectangle {
                        radius: 6
                        color: parent.chosen ? hub.selection : parent.visualFocus || parent.hovered ? hub.hoverFill : "transparent"
                    }
                    contentItem: Item {
                        Image {
                            anchors.centerIn: parent
                            anchors.alignWhenCentered: true
                            width: 17
                            height: width
                            source: Qt.resolvedUrl("icons/" + tab.modelData.icon + ".svg")
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                autoPaddingEnabled: false
                                colorization: 1
                                colorizationColor: tab.chosen ? hub.accent : hub.muted
                            }
                        }
                    }
                }
            }
        }
    }

    Flickable {
        id: viewport
        anchors.fill: parent
        anchors.leftMargin: 56
        anchors.topMargin: hub.pageTopInset
        anchors.rightMargin: 14
        anchors.bottomMargin: hub.pageBottomInset
        clip: true
        contentWidth: width
        contentHeight: content.implicitHeight
        boundsBehavior: Flickable.StopAtBounds
        Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }
        ColumnLayout {
            id: content
            x: 16
            width: Math.max(0, viewport.width - x - 2)
            spacing: 9
            Loader {
                id: page
                Layout.fillWidth: true
                active: hub.active
                sourceComponent: hub.sections.find(section => section.key === hub.selected)?.view ?? null
            }
            Copy {
                visible: hub.notice !== ""
                Layout.fillWidth: true
                text: hub.notice
                color: hub.accent
                wrapMode: Text.Wrap
            }
        }
    }

    component Copy: Text {
        color: hub.ink
        textFormat: Text.PlainText
        font.pixelSize: hub.textSize
        elide: Text.ElideRight
    }

    component Action: Controls.Button {
        id: button
        property bool selected: false
        property int minimumButtonWidth: hub.actionWidth
        implicitWidth: Math.max(minimumButtonWidth, implicitContentWidth + leftPadding + rightPadding)
        implicitHeight: 30
        leftPadding: 9
        rightPadding: 9
        hoverEnabled: true
        background: Rectangle {
            radius: 6
            color: button.selected || button.down || button.visualFocus ? hub.selection : button.hovered ? hub.hoverFill : hub.tile
            opacity: button.enabled ? 1 : 0.55
        }
        contentItem: Copy {
            text: button.text
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: button.selected ? hub.accent : hub.ink
        }
    }

    component EqualActions: RowLayout {
        Layout.fillWidth: true
        uniformCellSizes: true
        spacing: 5
    }

    component Field: RowLayout {
        property string label
        property string value: "—"
        property bool heading: false
        readonly property bool compact: parent instanceof GridLayout
        Layout.fillWidth: true
        spacing: 5
        Copy {
            text: parent.label
            color: parent.heading ? hub.ink : hub.detail
            font.pixelSize: hub.textSize + (parent.heading ? 1 : 0)
            font.weight: parent.heading ? Font.Medium : Font.Normal
            Layout.fillWidth: true
            Layout.preferredWidth: parent.compact ? implicitWidth : 120
        }
        Copy {
            text: parent.value || "—"
            Layout.fillWidth: true
            Layout.preferredWidth: parent.compact ? implicitWidth : 120
            horizontalAlignment: Text.AlignRight
        }
    }

    component Metrics: GridLayout {
        Layout.fillWidth: true
        columns: width >= hub.textSize * 28 ? 2 : 1
        uniformCellWidths: true
        columnSpacing: 13
        rowSpacing: 6
    }

    component Range: GridLayout {
        id: range
        property string label
        property bool compact: false
        property real amount: 0
        property real minimum: 0
        property real maximum: 100
        property var stops: []
        property string suffix: "%"
        property string status: ""
        readonly property real displayValue: stops.length ? stops[Math.round(slider.value)] : Math.round(slider.value)
        readonly property string reading: status || displayValue + suffix
        signal adjusted(real value)
        signal committed(real value)
        Layout.fillWidth: true
        columns: 3
        columnSpacing: range.compact ? 10 : 0
        rowSpacing: 2
        Field {
            visible: !range.compact
            Layout.row: 0
            Layout.column: 0
            Layout.columnSpan: 3
            label: range.label
            value: range.reading
            heading: true
        }
        Copy {
            visible: range.compact
            Layout.row: 0
            Layout.column: 0
            Layout.minimumWidth: 32
            Layout.preferredWidth: 120
            text: range.label
        }
        Copy {
            visible: range.compact
            Layout.row: 0
            Layout.column: 2
            Layout.preferredWidth: Math.max(38, implicitWidth)
            text: range.reading
            color: hub.detail
            horizontalAlignment: Text.AlignRight
        }
        Controls.Slider {
            id: slider
            Layout.row: range.compact ? 0 : 1
            Layout.column: range.compact ? 1 : 0
            Layout.columnSpan: range.compact ? 1 : 3
            Layout.fillWidth: true
            Layout.minimumWidth: 36
            implicitHeight: 19
            from: range.stops.length ? 0 : range.minimum
            to: range.stops.length ? range.stops.length - 1 : range.maximum
            stepSize: 1
            value: range.stops.length ? range.stops.reduce((best, stop, index) =>
                Math.abs(stop - range.amount) < Math.abs(range.stops[best] - range.amount) ? index : best, 0) : range.amount
            Accessible.name: range.label
            onMoved: {
                range.adjusted(range.displayValue);
                if (!pressed) range.committed(range.displayValue);
            }
            onPressedChanged: if (!pressed) range.committed(range.displayValue)
            background: Rectangle {
                x: slider.leftPadding
                y: (slider.height - height) / 2
                width: slider.availableWidth
                height: 4
                radius: 2
                color: hub.themePalette.track
                Rectangle { width: parent.width * slider.visualPosition; height: parent.height; radius: 2; color: hub.muted }
            }
            handle: Rectangle {
                x: slider.leftPadding + slider.visualPosition * Math.max(0, slider.availableWidth - width)
                y: (slider.height - height) / 2
                width: 11
                height: 11
                radius: 6
                color: slider.activeFocus ? hub.accent : hub.ink
            }
        }
    }

    component Choice: Controls.ComboBox {
        id: chooser
        Layout.fillWidth: true
        implicitHeight: 30
        enabled: count > 1
        textRole: "text"
        valueRole: "value"
        background: Rectangle {
            color: chooser.popup.visible || chooser.visualFocus ? hub.selection : hub.tile
            radius: 6
        }
        contentItem: Copy {
            text: chooser.displayText
            leftPadding: 8
            rightPadding: chooser.count > 1 ? 22 : 8
            verticalAlignment: Text.AlignVCenter
        }
        indicator: Copy {
            visible: chooser.count > 1
            x: chooser.width - width - 9
            y: (chooser.height - height) / 2
            text: chooser.popup.visible ? "⌃" : "⌄"
            color: hub.muted
        }
        delegate: Controls.ItemDelegate {
            id: option
            required property int index
            required property var modelData
            width: choices.width
            height: 28
            padding: 0
            hoverEnabled: true
            highlighted: chooser.highlightedIndex === index
            contentItem: Item {
                Copy {
                    anchors.left: parent.left
                    anchors.leftMargin: 8
                    anchors.right: check.left
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: option.modelData.text
                }
                Copy {
                    id: check
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    text: chooser.currentIndex === option.index ? "✓" : ""
                    color: hub.muted
                }
            }
            background: Rectangle {
                radius: 4
                color: option.highlighted || option.hovered ? hub.selection : "transparent"
            }
        }
        popup: Controls.Popup {
            id: menu
            property bool opensAbove: false
            property real spaceForMenu: 0
            readonly property int gap: 4
            x: 0
            y: opensAbove ? -height - gap : chooser.height + gap
            width: chooser.width
            height: Math.min(176, spaceForMenu, chooser.count * 28 + 2 * padding)
            padding: 4
            onAboutToShow: {
                const top = chooser.mapToItem(hub, 0, 0).y;
                const above = Math.max(0, top - gap);
                const below = Math.max(0, hub.height - top - chooser.height - gap);
                opensAbove = below < Math.min(176, chooser.count * 28 + 2 * padding) && above > below;
                spaceForMenu = opensAbove ? above : below;
            }
            contentItem: ListView {
                id: choices
                clip: true
                model: chooser.popup.visible ? chooser.delegateModel : null
                currentIndex: chooser.highlightedIndex
                boundsBehavior: Flickable.StopAtBounds
                Controls.ScrollIndicator.vertical: Controls.ScrollIndicator {}
            }
            background: Rectangle { color: hub.hoverFill; radius: 7 }
        }
    }

    component Group: ColumnLayout {
        Layout.fillWidth: true
        spacing: 7
    }

    Component {
        id: audioPage
        Group {
            spacing: 14
            Group {
                Range {
                    label: "Output volume"
                    enabled: !!hub.volumeSink?.audio
                    amount: (hub.volumeSink?.audio?.volume ?? 0) * 100
                    status: hub.volumeSink?.audio?.muted ? "Muted" : ""
                    onAdjusted: value => { if (hub.volumeSink?.audio) hub.volumeSink.audio.volume = value / 100; }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Choice {
                        Accessible.name: "Output device"
                        model: hub.audioChoices(hub.outputs)
                        currentIndex: hub.outputs.indexOf(hub.sink)
                        onActivated: hub.selectAudio(hub.nodeFor(currentValue), false)
                    }
                    Action {
                        text: hub.volumeSink?.audio?.muted ? "Unmute" : "Mute"
                        enabled: !!hub.volumeSink?.audio
                        onClicked: hub.volumeSink.audio.muted = !hub.volumeSink.audio.muted
                    }
                }
            }
            Group {
                Range {
                    label: "Input gain"
                    enabled: !!hub.source?.audio || (!!hub.virtualInputLevel && !actionProc.running)
                    amount: (hub.source?.audio?.volume ?? hub.virtualInputLevel?.volume ?? 0) * 100
                    status: hub.untypedInput && !hub.virtualInputLevel ? "Reading…" : ""
                    onAdjusted: value => { if (hub.source?.audio) hub.source.audio.volume = value / 100; }
                    onCommitted: value => {
                        if (hub.untypedInput && hub.source && hub.virtualInputLevel
                                && Math.round(hub.virtualInputLevel.volume * 100) !== value)
                            hub.run(["wpctl", "set-volume", String(hub.source.id), String(value / 100)]);
                    }
                }
                Choice {
                    Accessible.name: "Input device"
                    model: hub.audioChoices(hub.inputs)
                    currentIndex: hub.inputs.indexOf(hub.source)
                    onActivated: hub.selectAudio(hub.nodeFor(currentValue), true)
                }
            }
            Group {
                Copy {
                    text: hub.streams.length ? "App volume" : "No apps are playing audio"
                    color: hub.streams.length ? hub.ink : hub.muted
                    font.pixelSize: hub.textSize + (hub.streams.length ? 1 : 0)
                    font.weight: hub.streams.length ? Font.Medium : Font.Normal
                }
                Repeater {
                    model: AudioModel.rowSnapshot(hub.streams)
                    delegate: Range {
                        required property var modelData
                        readonly property var node: hub.nodeFor(modelData)
                        compact: true
                        label: node ? AudioModel.streamLabel(node, Mpris.players.values, hub.streams) : ""
                        maximum: 150
                        enabled: !!node?.audio
                        amount: (node?.audio?.volume ?? 0) * 100
                        onAdjusted: value => { if (node?.audio) node.audio.volume = value / 100; }
                    }
                }
            }
        }
    }

    Component {
        id: displayPage
        Group {
            Range {
                label: "Brightness"
                minimum: 1
                enabled: hub.brightness >= 0 && !actionProc.running
                amount: Math.max(1, hub.brightness)
                status: hub.brightness < 0 ? "Unavailable" : ""
                onCommitted: value => {
                    if (hub.displayName) hub.run(["omarchy-brightness-display", "--no-osd", "--monitor", hub.displayName, Math.round(value) + "%"]);
                }
            }
            RowLayout {
                Layout.fillWidth: true
                Copy { text: "Night Light"; font.pixelSize: hub.textSize + 1; font.weight: Font.Medium; Layout.fillWidth: true }
                Controls.Button {
                    id: nightSwitch
                    Accessible.name: "Night Light"
                    Accessible.role: Accessible.CheckBox
                    Accessible.checkable: true
                    Accessible.checked: hub.nightLight
                    implicitWidth: 38
                    implicitHeight: 30
                    padding: 0
                    hoverEnabled: true
                    enabled: !actionProc.running
                    background: null
                    contentItem: Item {
                        Rectangle {
                            width: 38
                            height: 20
                            anchors.centerIn: parent
                            radius: height / 2
                            color: hub.nightLight ? hub.selection : nightSwitch.hovered ? hub.hoverFill : hub.tile
                            border.width: nightSwitch.visualFocus ? 1 : 0
                            border.color: hub.accent
                            Rectangle {
                                height: 14
                                width: height
                                radius: height / 2
                                anchors.verticalCenter: parent.verticalCenter
                                x: hub.nightLight ? parent.width - width - 3 : 3
                                color: hub.nightLight ? hub.accent : hub.muted
                            }
                        }
                    }
                    onClicked: hub.run(["omarchy-toggle-nightlight"])
                }
            }
            Range {
                label: "Text size"
                stops: [9, 10, 11, 12, 14, 16, 20]
                amount: hub.textSize
                suffix: " px"
                enabled: !actionProc.running
                onCommitted: value => {
                    if (value !== hub.textSize) hub.run(["omarchy-display-text-size", String(value)]);
                }
            }
            Copy { text: "Scale · focused display"; color: hub.detail }
            GridLayout {
                Layout.fillWidth: true
                columns: width >= hub.textSize * 20 ? 6 : 3
                uniformCellWidths: true
                columnSpacing: 4
                rowSpacing: 4
                Repeater {
                    model: ["1", "1.25", "1.6", "2", "3", "4"]
                    delegate: Action {
                        required property string modelData
                        Layout.fillWidth: true
                        minimumButtonWidth: 0
                        leftPadding: 3
                        rightPadding: 3
                        text: modelData + "×"
                        Accessible.name: "Display scale " + text
                        selected: Number(modelData) === Number(hub.scale)
                        enabled: !!hub.scale && !actionProc.running
                        onClicked: hub.run(["omarchy-hyprland-monitor-scaling", modelData])
                    }
                }
            }
            Field {
                visible: brightnessDisplay.count < 2
                label: "Brightness display"
                value: hub.displayName || "—"
            }
            Copy { visible: brightnessDisplay.count > 1; text: "Brightness display"; color: hub.detail }
            Choice {
                id: brightnessDisplay
                visible: count > 1
                Accessible.name: "Display for brightness control"
                model: (hub.displayData.all ?? []).filter(monitor => monitor.enabled).map(monitor => ({text: monitor.name, value: monitor.name}))
                currentIndex: model.findIndex(option => option.value === hub.displayName)
                onActivated: {
                    hub.displayName = currentValue;
                    hub.brightness = -1;
                    hub.readBrightness();
                }
            }
            Repeater {
                model: hub.displayData.all ?? []
                delegate: RowLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Copy { text: modelData.name; Layout.fillWidth: true; color: hub.muted }
                    Action {
                        text: modelData.enabled ? "Disable" : "Enable"
                        Accessible.name: text + " " + modelData.name
                        enabled: !actionProc.running && (!modelData.enabled || hub.displayData.all.filter(monitor => monitor.enabled).length > 1)
                        onClicked: {
                            if (/^[A-Za-z0-9_.-]+$/.test(modelData.name))
                                hub.run(["hyprctl", "eval", "hl.monitor({ output = " + JSON.stringify(modelData.name) + ", disabled = " + modelData.enabled + " })"]);
                        }
                    }
                }
            }
        }
    }

    Component {
        id: powerPage
        Group {
            Copy { text: "Power profile"; font.pixelSize: hub.textSize + 1; font.weight: Font.Medium }
            EqualActions {
                Repeater {
                    model: hub.profiles
                    delegate: Action {
                        required property string modelData
                        Layout.fillWidth: true
                        text: ({"power-saver": "Power saver", balanced: "Balanced", performance: "Performance"})[modelData] || modelData
                        selected: hub.profile === modelData
                        enabled: !actionProc.running
                        onClicked: hub.run(["omarchy-powerprofiles-set",
                            UPower.onBattery && UPower.displayDevice?.isPresent ? "battery" : "ac", modelData])
                    }
                }
            }
            Metrics {
                Layout.topMargin: 10
                Field {
                    label: "Power state"
                    value: hub.powerInfo.state ? hub.powerInfo.state[0].toUpperCase() + hub.powerInfo.state.slice(1) : "—"
                }
                Field { visible: !!hub.powerInfo.threshold; label: "Charge limit"; value: hub.powerInfo.threshold || "" }
                Field {
                    visible: !hub.powerInfo.threshold && !!hub.powerInfo.time
                    label: hub.powerInfo.state === "charging" ? "Time to full" : "Time remaining"
                    value: hub.powerInfo.time || "—"
                }
                Field {
                    visible: !hub.powerInfo.threshold && !!hub.powerInfo.rate
                    label: "Battery rate"
                    value: hub.powerInfo.rate || "—"
                }
                Field { label: "Battery size"; value: hub.powerInfo.size || "—" }
                Field { label: "Charge cycles"; value: hub.powerInfo.cycles || "—" }
            }
        }
    }

    Component {
        id: ethernetPage
        Group {
            RowLayout {
                Layout.fillWidth: true
                Copy {
                    Layout.fillWidth: true
                    text: hub.ethernet.speed > 0 ? NetModel.formatHeaderSpeed(hub.ethernet.speed, hub.number) : hub.ethernet.iface || "Ethernet disconnected"
                    font.pixelSize: hub.textSize + 3
                }
                Action {
                    text: "Speed test"
                    enabled: !!hub.ethernet.iface
                    onClicked: {
                        hub.dismissRequested();
                        Quickshell.execDetached(["omarchy-shell", "shell", "summon", "omarchy.speedtest", "{}"]);
                    }
                }
            }
            Metrics {
                Field { label: "Ping"; value: NetModel.formatPingLatency(hub.connection.internetPingLatency, !!hub.connection.internetPingSamples?.length, null, hub.number) }
                Field { label: "Packet loss"; value: NetModel.formatPacketLoss(hub.connection.internetPingPacketLoss, !!hub.connection.internetPingSamples?.length, hub.number) }
                Field { label: "Receiving"; value: hub.ethernet.iface ? NetModel.formatRate(hub.traffic.downloadRate, hub.number) : "—" }
                Field { label: "Sending"; value: hub.ethernet.iface ? NetModel.formatRate(hub.traffic.uploadRate, hub.number) : "—" }
                Field { label: "Downloaded"; value: hub.ethernet.iface ? NetModel.formatBytes(hub.ethernet.rx_bytes, hub.number) : "—" }
                Field { label: "Uploaded"; value: hub.ethernet.iface ? NetModel.formatBytes(hub.ethernet.tx_bytes, hub.number) : "—" }
                Field { label: "IP address"; value: hub.ethernet.ip || "—" }
                Field { label: "Gateway"; value: hub.ethernet.gateway || "—" }
            }
            Copy { Layout.topMargin: 4; text: "DNS provider"; font.pixelSize: hub.textSize + 1; font.weight: Font.Medium }
            EqualActions {
                Repeater {
                    model: ["DHCP", "Cloudflare", "Google", "Custom"]
                    delegate: Action {
                        required property string modelData
                        Layout.fillWidth: true
                        text: modelData
                        selected: hub.dns === modelData
                        enabled: !actionProc.running
                        onClicked: {
                            if (modelData === "Custom") {
                                hub.dismissRequested();
                                Quickshell.execDetached(["omarchy-launch-floating-terminal-with-presentation", "omarchy-dns Custom"]);
                            } else {
                                hub.run(["omarchy-dns", modelData]);
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: agentsPage
        Group {
            id: agentsPageView
            readonly property int detailSize: Math.max(11, hub.textSize - 1)
            function resetLabel(raw) {
                if (!raw) return "";
                const minutes = Math.max(0, Math.ceil((new Date(raw).getTime() - Date.now()) / 60000));
                if (!minutes || !isFinite(minutes)) return "";
                return minutes >= 1440 ? Math.floor(minutes / 1440) + "d " + Math.floor(minutes % 1440 / 60) + "h"
                    : minutes >= 60 ? Math.floor(minutes / 60) + "h " + minutes % 60 + "m" : minutes + "m";
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 4
                Copy {
                    text: hub.agentTokens >= 1e9 ? hub.number(hub.agentTokens / 1e9, 1) + "B"
                        : hub.agentTokens >= 1e6 ? hub.number(hub.agentTokens / 1e6, 1) + "M"
                        : hub.agentTokens >= 1e3 ? hub.number(hub.agentTokens / 1e3, 1) + "K"
                        : hub.number(hub.agentTokens)
                    font.pixelSize: hub.textSize + 3
                    font.weight: Font.DemiBold
                    Layout.alignment: Qt.AlignBaseline
                }
                Copy {
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBaseline
                    text: "tokens today"
                }
            }
            Copy { visible: !hub.agents.length; text: "No usage records available"; color: hub.muted }
            Repeater {
                model: hub.agents
                delegate: Group {
                    id: provider
                    required property var modelData
                    Layout.topMargin: 12
                    spacing: 6
                    RowLayout {
                        Layout.fillWidth: true
                        Copy {
                            text: provider.modelData.name || "Agent"
                            font.pixelSize: hub.textSize + 2
                            font.weight: Font.DemiBold
                            Layout.fillWidth: true
                        }
                        Copy {
                            text: provider.modelData.tierLabel || ""
                            color: hub.muted
                            font.pixelSize: agentsPageView.detailSize
                            horizontalAlignment: Text.AlignRight
                        }
                    }
                    Repeater {
                        model: provider.modelData.limits || []
                        delegate: RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            Copy {
                                text: modelData.title || modelData.label || ""
                                Layout.preferredWidth: Math.max(48, implicitWidth)
                                font.pixelSize: agentsPageView.detailSize
                                color: hub.muted
                            }
                            Rectangle {
                                Layout.fillWidth: true
                                height: 4
                                radius: 2
                                color: hub.themePalette.track
                                Rectangle { width: parent.width * Math.min(1, Math.max(0, Number(modelData.percent) || 0)); height: 4; radius: 2; color: hub.muted }
                            }
                            Copy {
                                text: agentsPageView.resetLabel(modelData.resetsAt)
                                Layout.preferredWidth: 50
                                horizontalAlignment: Text.AlignRight
                                font.pixelSize: agentsPageView.detailSize
                                color: hub.ink
                            }
                        }
                    }
                    Copy {
                        visible: provider.modelData.resetCredits?.available !== undefined
                        Layout.fillWidth: true
                        font.pixelSize: agentsPageView.detailSize
                        text: (provider.modelData.resetCredits?.available ?? 0) + " free resets" +
                            (agentsPageView.resetLabel(provider.modelData.resetCredits?.nextExpiresAt) ?
                                " · Next expires in " + agentsPageView.resetLabel(provider.modelData.resetCredits.nextExpiresAt) : "")
                        color: hub.muted
                    }
                }
            }
        }
    }

    Component {
        id: weatherPage
        Group {
            RowLayout {
                Layout.fillWidth: true
                Copy {
                    Layout.fillWidth: true
                    text: hub.weather.name || (weatherRead.running ? "Loading weather…" : "Weather unavailable")
                    font.pixelSize: hub.textSize + 2
                }
                Action { text: "Refresh"; enabled: !weatherRead.running; onClicked: weatherRead.read() }
            }
            Copy {
                visible: !!hub.weather.name
                Layout.fillWidth: true
                text: hub.weather.temperature + "°C  ·  " + hub.weather.condition
                font.pixelSize: hub.textSize + 5
            }
            Metrics {
                Field { visible: !!hub.weather.name; label: "Feels like"; value: hub.weather.feels + "°C" }
                Field { visible: !!hub.weather.name; label: "Wind"; value: hub.weather.wind + " km/h" }
                Field { visible: !!hub.weather.name; label: "Humidity"; value: hub.weather.humidity + "%" }
            }
            Repeater {
                model: hub.weather.forecast ?? []
                delegate: Field {
                    required property var modelData
                    label: Qt.formatDate(new Date(modelData.date + "T12:00:00"), "dddd")
                    value: modelData.high + "° / " + modelData.low + "°"
                }
            }
            Copy {
                visible: hub.weatherFailed
                Layout.fillWidth: true
                color: hub.muted
                text: hub.weather.name ? "Could not refresh the forecast" : "Could not load the configured Omarchy location"
                wrapMode: Text.Wrap
            }
        }
    }
}
