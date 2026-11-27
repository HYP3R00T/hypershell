pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls.Basic as Controls
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

PanelWindow {
    id: popup

    required property bool panelVisible
    required property ShellScreen targetScreen
    required property NotchPalette themePalette
    required property int bezel
    required property int curveRadius
    required property int bottomInset

    property QsMenuHandle menu: null
    readonly property bool opened: menu !== null
    property var levels: []
    readonly property bool flyout: mainCard.x >= 230
    readonly property bool inSubmenu: levels.length > 0
    readonly property var level: inSubmenu ? levels[levels.length - 1] : null
    readonly property Item dockedCard: !flyout && inSubmenu ? subCard : mainCard
    readonly property int edgeInset: bezel + curveRadius + 4
    readonly property int maxHeight: Math.max(0, Math.min(460, height - bottomInset - 16))

    function closeSubmenus(depth) {
        const previous = levels;
        levels = previous.slice(0, depth);
        for (let index = previous.length - 1; index >= depth; --index) {
            previous[index].opener.menu = null;
            previous[index].opener.destroy();
        }
    }

    function dismiss() {
        closeSubmenus(0);
        menu = null;
    }

    function open(handle) {
        dismiss();
        mainCard.resetSelection();
        menu = handle;
        mainCard.forceActiveFocus();
    }

    function back() {
        const parentCard = levels.length > 1 ? subCard : mainCard;
        closeSubmenus(levels.length - 1);
        parentCard.forceActiveFocus();
    }

    function activate(card, entry, row) {
        if (!entry?.enabled || entry.isSeparator) return;
        if (!entry.hasChildren) {
            entry.triggered();
            dismiss();
            return;
        }

        if (card === mainCard) closeSubmenus(0);
        const opener = childOpener.createObject(popup, { menu: entry });
        if (!opener) return;
        const anchor = card.mapFromItem(row, 0, row.height / 2);
        subCard.resetSelection();
        levels = [...levels, { opener, entry, title: entry.text, anchorY: card.y + anchor.y }];
        subCard.forceActiveFocus();
    }

    onPanelVisibleChanged: if (!panelVisible) dismiss()
    onOpenedChanged: if (!opened) closeSubmenus(0)

    screen: targetScreen
    visible: panelVisible
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "linear-carbon-tray-menu"
    WlrLayershell.keyboardFocus: opened ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

    mask: Region {
        width: popup.opened ? popup.width : 0
        height: popup.opened ? popup.height : 0
    }

    HyprlandFocusGrab {
        active: popup.visible && popup.opened
        windows: [popup]
        onCleared: popup.dismiss()
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onClicked: popup.dismiss()
    }

    QsMenuOpener { id: rootOpener; menu: popup.menu }
    Component { id: childOpener; QsMenuOpener {} }

    FrameShoulder {
        width: popup.curveRadius
        anchors.right: popup.dockedCard.left
        anchors.rightMargin: -0.5
        anchors.bottom: popup.dockedCard.bottom
        anchors.bottomMargin: 1
        paintColor: popup.themePalette.frame
        inverted: true
        visible: popup.opened
    }

    FrameShoulder {
        width: popup.curveRadius
        anchors.left: popup.dockedCard.right
        anchors.leftMargin: -0.5
        anchors.bottom: popup.dockedCard.bottom
        anchors.bottomMargin: 1
        paintColor: popup.themePalette.frame
        mirrored: true
        inverted: true
        visible: popup.opened
    }

    MenuCard {
        id: mainCard
        visible: popup.opened && (popup.flyout || !popup.inSubmenu)
        x: popup.width - popup.edgeInset - width
        y: popup.height - popup.bottomInset - height
        width: Math.min(294, Math.max(0, popup.width - 2 * popup.edgeInset))
        availableHeight: popup.maxHeight
        entries: rootOpener.children
        docked: true
    }

    MenuCard {
        id: subCard
        visible: popup.opened && popup.inSubmenu
        x: popup.flyout ? mainCard.x - width - 5 : mainCard.x
        y: popup.flyout
            ? Math.max(8, Math.min(popup.height - popup.bottomInset - height, (popup.level?.anchorY ?? 0) - height / 2))
            : popup.height - popup.bottomInset - height
        width: popup.flyout ? 205 : mainCard.width
        availableHeight: popup.maxHeight
        entries: popup.level?.opener.children ?? null
        backTitle: popup.level?.title ?? ""
        backVisible: !popup.flyout || popup.levels.length > 1
        docked: !popup.flyout
    }

    component MenuCard: FocusScope {
        id: card
        required property var entries
        required property int availableHeight
        property bool docked: false
        property bool backVisible: false
        property string backTitle: ""

        function isSectionLabel(entry) {
            return !!entry && !entry.enabled && !entry.hasChildren && !entry.icon && entry.buttonType === QsMenuButtonType.None;
        }

        function rowHeight(entry, index) {
            if (!entry) return 0;
            if (entry.isSeparator) return index === 0 ? 0 : 7;
            return isSectionLabel(entry) ? 20 : 27;
        }

        function resetSelection() {
            list.currentIndex = -1;
            list.contentY = 0;
        }

        function select(step, start) {
            for (let offset = 1; offset <= list.count; ++offset) {
                const index = (start + offset * step + list.count * 2) % list.count;
                const entry = card.entries.values[index];
                if (!entry?.enabled || entry.isSeparator) continue;
                list.currentIndex = index;
                list.positionViewAtIndex(index, ListView.Contain);
                return;
            }
        }

        function triggerCurrent(submenuOnly) {
            const row = list.currentItem;
            const entry = card.entries?.values[list.currentIndex];
            if (row && entry && (!submenuOnly || entry.hasChildren)) popup.activate(card, entry, row);
        }

        height: {
            const rows = entries?.values ?? [];
            const rowsHeight = rows.reduce((total, entry, index) => total + rowHeight(entry, index), 0);
            return Math.min(availableHeight, rowsHeight + (backVisible ? backButton.height : 0) + 16);
        }
        Keys.onUpPressed: select(-1, list.currentIndex < 0 ? 0 : list.currentIndex)
        Keys.onDownPressed: select(1, list.currentIndex)
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Home) select(1, -1);
            else if (event.key === Qt.Key_End) select(-1, 0);
            else return;
            event.accepted = true;
        }
        Keys.onReturnPressed: triggerCurrent(false)
        Keys.onEnterPressed: triggerCurrent(false)
        Keys.onSpacePressed: triggerCurrent(false)
        Keys.onLeftPressed: triggerCurrent(true)
        Keys.onRightPressed: if (popup.inSubmenu) popup.back()
        Keys.onEscapePressed: {
            if (popup.inSubmenu) popup.back();
            else popup.dismiss();
        }

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }

        Rectangle {
            anchors.fill: parent
            radius: popup.curveRadius
            bottomLeftRadius: card.docked ? 0 : radius
            bottomRightRadius: card.docked ? 0 : radius
            color: card.docked ? popup.themePalette.frame : popup.themePalette.tile
        }

        Controls.Button {
            id: backButton
            anchors { top: parent.top; left: parent.left; right: parent.right; margins: 8 }
            visible: card.backVisible
            height: 27
            padding: 8
            hoverEnabled: true
            Accessible.name: "Back"
            contentItem: Text {
                renderType: Text.CurveRendering
                text: "‹  " + card.backTitle
                textFormat: Text.PlainText
                color: popup.themePalette.muted
                font.pixelSize: 12
                elide: Text.ElideRight
                verticalAlignment: Text.AlignVCenter
            }
            background: Rectangle {
                radius: 6
                color: backButton.hovered || backButton.visualFocus ? popup.themePalette.hover : "transparent"
            }
            onClicked: popup.back()
        }

        ListView {
            id: list
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 8 }
            anchors.top: card.backVisible ? backButton.bottom : parent.top
            anchors.topMargin: card.backVisible ? 0 : 8
            model: card.entries
            currentIndex: -1
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            Controls.ScrollBar.vertical: Controls.ScrollBar { policy: Controls.ScrollBar.AsNeeded }

            delegate: Controls.Button {
                id: row
                required property QsMenuEntry modelData
                required property int index
                readonly property bool sectionLabel: card.isSectionLabel(modelData)
                readonly property bool marked: !!modelData && modelData.buttonType !== QsMenuButtonType.None

                width: ListView.view.width
                height: card.rowHeight(modelData, index)
                visible: height > 0
                enabled: modelData?.enabled === true && !modelData.isSeparator
                hoverEnabled: true
                focusPolicy: Qt.NoFocus
                padding: 8
                Accessible.role: Accessible.MenuItem
                Accessible.name: modelData?.isSeparator ? "" : (modelData?.text ?? "")

                background: Rectangle {
                    radius: 6
                    readonly property bool keyboardSelected: row.index === list.currentIndex
                        && card === (popup.inSubmenu ? subCard : mainCard)
                    color: row.enabled && (row.hovered || keyboardSelected || popup.levels[0]?.entry === row.modelData)
                        ? popup.themePalette.hover : "transparent"
                }

                contentItem: Row {
                    visible: !!row.modelData && !row.modelData.isSeparator
                    spacing: 6

                    Text {
                        renderType: Text.CurveRendering
                        visible: row.marked
                        width: 13
                        height: parent.height
                        text: row.modelData?.checkState === Qt.PartiallyChecked ? "–"
                            : row.modelData?.buttonType === QsMenuButtonType.RadioButton
                                ? (row.modelData?.checkState === Qt.Checked ? "●" : "○")
                                : (row.modelData?.checkState === Qt.Checked ? "✓" : "")
                        color: popup.themePalette.ink
                        font.pixelSize: 12
                        verticalAlignment: Text.AlignVCenter
                    }

                    Image {
                        visible: !!row.modelData?.icon
                        anchors.verticalCenter: parent.verticalCenter
                        width: 14
                        height: width
                        source: row.modelData ? row.modelData.icon : ""
                        sourceSize: Qt.size(width * Screen.devicePixelRatio, height * Screen.devicePixelRatio)
                        fillMode: Image.PreserveAspectFit
                    }

                    Text {
                        renderType: Text.CurveRendering
                        readonly property int iconSpace: (row.marked ? 19 : 0) + (!!row.modelData?.icon ? 20 : 0)
                        width: Math.max(0, parent.width - iconSpace - (row.modelData?.hasChildren ? 16 : 0))
                        height: parent.height
                        text: row.modelData?.text ?? ""
                        textFormat: Text.PlainText
                        color: row.enabled ? popup.themePalette.ink : popup.themePalette.muted
                        font.pixelSize: row.sectionLabel ? 11 : 13
                        font.weight: row.sectionLabel ? Font.Medium : Font.Normal
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }

                    Text {
                        renderType: Text.CurveRendering
                        visible: row.modelData?.hasChildren ?? false
                        width: 10
                        height: parent.height
                        text: "‹"
                        color: popup.themePalette.muted
                        font.pixelSize: 17
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                onClicked: popup.activate(card, row.modelData, row)
            }
        }
    }
}
