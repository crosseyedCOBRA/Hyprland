import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import QtQuick
import QtQuick.Layouts

ShellRoot {
    id: root

    // Palette pulled from assets/wallpaper.jpg (deep space navy, nebula
    // blue/purple, warm cloud orange, coral planet surface). Keep in sync
    // with the `colors` let-binding in home.nix.
    readonly property color colorBg: "#0a0e1a"
    readonly property color colorSurface: "#1a1b26"
    readonly property color colorBorder: "#292e42"
    readonly property color colorText: "#c0caf5"
    readonly property color colorMuted: "#565f89"
    readonly property color colorBlue: "#7aa2f7"
    readonly property color colorOrange: "#ff9e64"
    readonly property color colorPink: "#f7768e"

    // Awesome has no native IPC, so its rc.lua pushes per-screen tag state
    // to this file (keyed by output name) whenever it changes.
    FileView {
        id: awesomeTagsFile
        path: "/home/mike/.cache/awesome/tags.json"
        watchChanges: true
        onFileChanged: this.reload()
    }
    readonly property var awesomeTags: {
        try {
            return JSON.parse(awesomeTagsFile.text());
        } catch (e) {
            return {};
        }
    }

    // Fire-and-forget helper for clicking a workspace pill.
    Process {
        id: awesomeViewTag
    }

    Variants {
        // HDMI-A-0 mirrors DisplayPort-0 (--same-as in the xrandr setup), so
        // it reports as its own screen too; without this filter it would
        // get a second PanelWindow drawn on top of DisplayPort-0's.
        model: Quickshell.screens.filter(screen => screen.name !== "HDMI-A-0")

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: 32
            color: root.colorBg

            Item {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8

                // --- Far left: launcher ---
                Item {
                    id: launcher
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 22
                    height: 22

                    Image {
                        anchors.fill: parent
                        anchors.margins: 3
                        source: "/home/mike/.config/quickshell/nix-snowflake-white.svg"
                        sourceSize: Qt.size(16, 16)
                        fillMode: Image.PreserveAspectFit
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: rofiProcess.running = true
                    }

                    Process {
                        id: rofiProcess
                        command: [ "rofi", "-show", "drun", "-show-icons" ]
                    }
                }

                // --- Left: workspaces ---
                RowLayout {
                    id: workspaces
                    anchors.left: launcher.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Repeater {
                        model: (root.awesomeTags[bar.screen.name] || {}).tags || []

                        Rectangle {
                            width: 28
                            height: 22
                            radius: 4
                            border.width: modelData.focused ? 0 : 1
                            border.color: root.colorBorder
                            color: modelData.focused ? root.colorBlue
                                : modelData.urgent ? root.colorPink
                                : root.colorSurface

                            Text {
                                anchors.centerIn: parent
                                text: modelData.name
                                color: modelData.focused ? root.colorBg : root.colorMuted
                                font.pixelSize: 12
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    awesomeViewTag.command = [
                                        "/home/mike/.config/quickshell/awesome-view-tag.sh",
                                        bar.screen.name,
                                        modelData.name
                                    ];
                                    awesomeViewTag.running = true;
                                }
                            }
                        }
                    }
                }

                // --- Layout indicator: this monitor's current layout ---
                Rectangle {
                    anchors.left: workspaces.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    radius: 4
                    color: root.colorSurface
                    border.width: 1
                    border.color: root.colorBorder
                    width: layoutLabel.implicitWidth + 12
                    height: 22

                    Text {
                        id: layoutLabel
                        anchors.centerIn: parent
                        text: (root.awesomeTags[bar.screen.name] || {}).layout || ""
                        color: root.colorMuted
                        font.pixelSize: 12
                    }
                }

                // --- Center: clock / date ---
                Item {
                    id: clockArea
                    anchors.centerIn: parent
                    width: clock.implicitWidth
                    height: clock.implicitHeight

                    Text {
                        id: clock
                        anchors.centerIn: parent
                        color: root.colorText
                        font.pixelSize: 13
                        font.bold: true
                        text: Qt.formatDateTime(new Date(), "ddd, MMM dd  HH:mm:ss")

                        Timer {
                            interval: 1000
                            running: true
                            repeat: true
                            onTriggered: clock.text = Qt.formatDateTime(new Date(), "ddd, MMM dd  HH:mm:ss")
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: calendarPopup.visible = !calendarPopup.visible
                    }
                }

                // --- Calendar popup (toggled by clicking the clock) ---
                PopupWindow {
                    id: calendarPopup
                    visible: false
                    color: "transparent"
                    implicitWidth: 220
                    implicitHeight: 250

                    anchor {
                        item: clockArea
                        edges: Edges.Bottom
                        gravity: Edges.Bottom
                        margins.top: 6
                    }

                    property date shownMonth: new Date()

                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: root.colorSurface
                        border.width: 1
                        border.color: root.colorBorder

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: "‹"
                                    color: root.colorText
                                    font.pixelSize: 16

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        onClicked: calendarPopup.shownMonth = new Date(
                                            calendarPopup.shownMonth.getFullYear(),
                                            calendarPopup.shownMonth.getMonth() - 1, 1)
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: Qt.formatDate(calendarPopup.shownMonth, "MMMM yyyy")
                                    color: root.colorText
                                    font.pixelSize: 14
                                    font.bold: true
                                }

                                Text {
                                    text: "›"
                                    color: root.colorText
                                    font.pixelSize: 16

                                    MouseArea {
                                        anchors.fill: parent
                                        anchors.margins: -4
                                        onClicked: calendarPopup.shownMonth = new Date(
                                            calendarPopup.shownMonth.getFullYear(),
                                            calendarPopup.shownMonth.getMonth() + 1, 1)
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Repeater {
                                    model: ["S", "M", "T", "W", "T", "F", "S"]

                                    Text {
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData
                                        color: root.colorMuted
                                        font.pixelSize: 11
                                    }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                columns: 7
                                rowSpacing: 4
                                columnSpacing: 0

                                Repeater {
                                    model: {
                                        const y = calendarPopup.shownMonth.getFullYear();
                                        const m = calendarPopup.shownMonth.getMonth();
                                        const firstDow = new Date(y, m, 1).getDay();
                                        const daysInMonth = new Date(y, m + 1, 0).getDate();
                                        const cells = [];
                                        for (let i = 0; i < firstDow; i++) cells.push(0);
                                        for (let d = 1; d <= daysInMonth; d++) cells.push(d);
                                        while (cells.length % 7 !== 0) cells.push(0);
                                        return cells;
                                    }

                                    Rectangle {
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 24
                                        radius: 4
                                        readonly property bool isToday: {
                                            if (modelData === 0) return false;
                                            const now = new Date();
                                            return modelData === now.getDate()
                                                && calendarPopup.shownMonth.getMonth() === now.getMonth()
                                                && calendarPopup.shownMonth.getFullYear() === now.getFullYear();
                                        }
                                        color: isToday ? root.colorBlue : "transparent"

                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData === 0 ? "" : modelData
                                            color: parent.isToday ? root.colorBg : root.colorText
                                            font.pixelSize: 12
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // --- Right: system tray + audio (audio stays furthest right) ---
                RowLayout {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 12

                    // System tray
                    RowLayout {
                        spacing: 6

                        Repeater {
                            model: SystemTray.items

                            Item {
                                id: trayItem
                                required property var modelData
                                width: 20
                                height: 20

                                Image {
                                    anchors.fill: parent
                                    source: trayItem.modelData.icon
                                    sourceSize: Qt.size(20, 20)
                                }

                                QsMenuOpener {
                                    id: menuOpener
                                    menu: trayItem.modelData.menu
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton) {
                                            if (trayItem.modelData.hasMenu) trayMenu.visible = !trayMenu.visible;
                                        } else if (trayItem.modelData.onlyMenu) {
                                            if (trayItem.modelData.hasMenu) trayMenu.visible = !trayMenu.visible;
                                        } else {
                                            trayItem.modelData.activate();
                                        }
                                    }
                                }

                                // Themed replacement for modelData.display(), which pops
                                // an unstyled native menu — this renders the same DBusMenu
                                // entries ourselves so they pick up the bar's palette.
                                PopupWindow {
                                    id: trayMenu
                                    visible: false
                                    color: "transparent"
                                    implicitWidth: Math.max(140, menuColumn.implicitWidth + 16)
                                    implicitHeight: menuColumn.implicitHeight + 16

                                    anchor {
                                        item: trayItem
                                        edges: Edges.Bottom
                                        gravity: Edges.Bottom
                                        margins.top: 6
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        radius: 8
                                        color: root.colorSurface
                                        border.width: 1
                                        border.color: root.colorBorder

                                        ColumnLayout {
                                            id: menuColumn
                                            anchors.fill: parent
                                            anchors.margins: 8
                                            spacing: 2

                                            Repeater {
                                                model: menuOpener.children

                                                Item {
                                                    required property var modelData
                                                    Layout.fillWidth: true
                                                    implicitHeight: modelData.isSeparator ? 9 : 24
                                                    visible: modelData.text !== "" || !modelData.isSeparator

                                                    Rectangle {
                                                        visible: modelData.isSeparator
                                                        anchors.left: parent.left
                                                        anchors.right: parent.right
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        height: 1
                                                        color: root.colorBorder
                                                    }

                                                    Rectangle {
                                                        visible: !modelData.isSeparator
                                                        anchors.fill: parent
                                                        radius: 4
                                                        color: entryMouse.containsMouse && modelData.enabled
                                                            ? root.colorBlue : "transparent"

                                                        Text {
                                                            anchors.left: parent.left
                                                            anchors.right: parent.right
                                                            anchors.leftMargin: 8
                                                            anchors.rightMargin: 8
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: modelData.text
                                                            elide: Text.ElideRight
                                                            opacity: modelData.enabled ? 1 : 0.5
                                                            color: entryMouse.containsMouse && modelData.enabled
                                                                ? root.colorBg : root.colorText
                                                            font.pixelSize: 12
                                                        }

                                                        MouseArea {
                                                            id: entryMouse
                                                            anchors.fill: parent
                                                            hoverEnabled: true
                                                            enabled: modelData.enabled
                                                            onClicked: {
                                                                modelData.triggered();
                                                                trayMenu.visible = false;
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Audio (default sink volume)
                    Item {
                        id: audioWidget
                        implicitWidth: volumeIcon.implicitWidth + volumeText.implicitWidth + 12
                        implicitHeight: 22

                        property var sink: Pipewire.defaultAudioSink

                        PwObjectTracker {
                            objects: [ Pipewire.defaultAudioSink ]
                        }

                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 4

                            Text {
                                id: volumeIcon
                                font.family: "JetBrainsMono Nerd Font"
                                font.pixelSize: 14
                                color: root.colorText
                                text: {
                                    const sink = audioWidget.sink;
                                    if (!sink || !sink.ready || !sink.audio) return "";
                                    if (sink.audio.muted) return "";
                                    return "";
                                }
                            }

                            Text {
                                id: volumeText
                                color: root.colorText
                                font.pixelSize: 13
                                text: {
                                    const sink = audioWidget.sink;
                                    if (!sink || !sink.ready || !sink.audio) return "--";
                                    if (sink.audio.muted) return "muted";
                                    return Math.round(sink.audio.volume * 100) + "%";
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    const sink = audioWidget.sink;
                                    if (sink && sink.audio) sink.audio.muted = !sink.audio.muted;
                                } else {
                                    pavucontrolProcess.running = true;
                                }
                            }
                            onWheel: (wheel) => {
                                const sink = audioWidget.sink;
                                if (!sink || !sink.audio) return;
                                const step = wheel.angleDelta.y > 0 ? 0.05 : -0.05;
                                sink.audio.volume = Math.max(0, Math.min(1.5, sink.audio.volume + step));
                            }
                        }

                        Process {
                            id: pavucontrolProcess
                            command: [ "pavucontrol" ]
                        }
                    }

                    // Power menu
                    Item {
                        width: 22
                        height: 22

                        Text {
                            anchors.centerIn: parent
                            text: "⏻"
                            color: root.colorText
                            font.pixelSize: 15
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: powerMenuProcess.running = true
                        }

                        Process {
                            id: powerMenuProcess
                            command: [ "power-menu" ]
                        }
                    }
                }
            }
        }
    }
}
