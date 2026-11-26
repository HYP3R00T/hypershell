import QtQuick
import QtQuick.Controls.Basic as Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "/usr/share/omarchy/shell/plugins/panels/clock/Model.js" as ClockModel

ColumnLayout {
    id: calendar

    required property NotchPalette themePalette
    required property date today
    property date month: firstOfMonth(today)
    property var shellSettings: ({})
    readonly property var clockSettings: Object.values(shellSettings.bar?.layout ?? {}).flat()
        .find(entry => entry?.id === "omarchy.clock")?.settings
        ?? shellSettings.plugins?.find(entry => entry?.id === "omarchy.clock")?.settings ?? {}
    readonly property int weekStart: ClockModel.normalizedWeekStart(clockSettings.weekStartDay, Qt.locale().firstDayOfWeek)
    readonly property var headers: ["Wk"].concat(ClockModel.weekdayOrder(weekStart)
        .map(day => Qt.locale().standaloneDayName(day || 7, Locale.ShortFormat)))
    readonly property var cells: {
        const todayKey = ClockModel.dateKey(today.getFullYear(), today.getMonth(), today.getDate());
        const result = [];
        for (const row of ClockModel.monthGrid(month.getFullYear(), month.getMonth(), weekStart, todayKey)) {
            result.push({ text: row.week, muted: true });
            for (const day of row.days)
                result.push({ text: day.day, muted: !day.inMonth, today: day.today });
        }
        return result;
    }
    spacing: 8

    function firstOfMonth(date) {
        return new Date(date.getFullYear(), date.getMonth(), 1);
    }

    function move(delta) {
        month = new Date(month.getFullYear(), month.getMonth() + delta, 1);
    }

    FileView {
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/omarchy/shell.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: { try { calendar.shellSettings = JSON.parse(text()); } catch (_) {} }
    }

    component CalendarText: Text {
        textFormat: Text.PlainText
        color: calendar.themePalette.ink
        font.pixelSize: 12
        verticalAlignment: Text.AlignVCenter
    }

    component CalendarButton: Controls.Button {
        id: button
        implicitWidth: Math.max(30, contentItem.implicitWidth + 16)
        implicitHeight: 29
        padding: 0
        hoverEnabled: true
        background: Rectangle {
            radius: 7
            color: button.down ? calendar.themePalette.selection
                : button.hovered || button.visualFocus ? calendar.themePalette.hover : calendar.themePalette.tile
        }
        contentItem: CalendarText {
            text: button.text
            horizontalAlignment: Text.AlignHCenter
        }
    }

    RowLayout {
        Layout.fillWidth: true
        CalendarButton { text: "‹"; Accessible.name: "Previous month"; onClicked: calendar.move(-1) }
        CalendarText {
            Layout.fillWidth: true
            text: Qt.locale().toString(calendar.month, "MMMM yyyy")
            horizontalAlignment: Text.AlignHCenter
            font.bold: true
        }
        CalendarButton { text: "›"; Accessible.name: "Next month"; onClicked: calendar.move(1) }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 8
        uniformCellWidths: true
        columnSpacing: 2
        rowSpacing: 2
        Repeater {
            model: calendar.headers
            delegate: CalendarText {
                required property string modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 24
                text: modelData
                elide: Text.ElideRight
                horizontalAlignment: Text.AlignHCenter
                color: calendar.themePalette.muted
            }
        }
        Repeater {
            model: calendar.cells
            delegate: Rectangle {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 25
                radius: 5
                color: modelData.today ? calendar.themePalette.selection : "transparent"
                CalendarText {
                    anchors.fill: parent
                    text: parent.modelData.text
                    color: parent.modelData.muted ? calendar.themePalette.muted : calendar.themePalette.ink
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        CalendarText {
            Layout.fillWidth: true
            color: calendar.themePalette.muted
            text: {
                const date = calendar.today;
                return date.getFullYear() + " · " + ClockModel.yearProgressPercent(date.getFullYear(), date.getMonth(), date.getDate()) + "% elapsed";
            }
        }
        CalendarButton { text: "Today"; onClicked: calendar.month = calendar.firstOfMonth(calendar.today) }
    }
}
