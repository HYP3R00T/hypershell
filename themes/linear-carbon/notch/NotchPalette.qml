import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: palette
    readonly property string path: Quickshell.shellDir + "/../colors.toml"
    property var colors: ({})
    property bool refreshPending: false

    readonly property color frame: colors.darker_background ?? "#09090a"
    readonly property color ink: colors.foreground ?? "#ececf0"
    readonly property color muted: colors.light_foreground ?? "#a6a6b0"
    readonly property color accent: colors.accent ?? "#afa2f4"
    readonly property color tile: colors.dark_background ?? "#101012"
    readonly property color hover: colors.background ?? "#19191c"
    readonly property color track: colors.lighter_background ?? "#26262b"
    readonly property color selectionTint: colors.selection ?? "#373155"
    readonly property color selection: Qt.tint(tile, Qt.rgba(selectionTint.r, selectionTint.g, selectionTint.b, 0.4))

    function refresh() {
        if (reader.running) refreshPending = true;
        else reader.running = true;
    }

    Component.onCompleted: refresh()

    FileView {
        path: palette.path
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload();
            palette.refresh();
        }
    }

    Process {
        id: reader
        command: ["python3", Quickshell.shellDir + "/notch-data.py", "palette", palette.path]
        stdout: StdioCollector { id: result }
        onExited: function(exitCode) {
            if (exitCode === 0) {
                try { palette.colors = JSON.parse(result.text); } catch (_) {}
            }
            if (palette.refreshPending) {
                palette.refreshPending = false;
                Qt.callLater(palette.refresh);
            }
        }
    }
}
