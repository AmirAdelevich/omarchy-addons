import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
    id: root
    Commons.Translations { id: strings; directory: Qt.resolvedUrl("i18n") }
    property int wheelDelta: 0
    readonly property bool showRpm: setting("showRpm", true)
    readonly property string rpmText: value(stats.rpm[0], "") + " / " + value(stats.rpm[1], "")
    component PlainText: Text {
        textFormat: Text.PlainText
        color: Commons.Color.foreground
        font.family: root.shellFont
        font.pixelSize: Style.font.bodySmall
    }
    readonly property string shellFont: bar ? bar.fontFamily : Style.font.family
    moduleName: "msi.katana-fans"
    property var stats: ({
            rpm: [],
            temp: []
        })
    property var curves: []
    property bool backup: false
    property string error: ""
    readonly property bool busy: control.running
    readonly property string helper: "/usr/local/libexec/katana-fans"
    readonly property bool opened: popup.opened
    readonly property bool popoutSwitchClosing: popup.popoutSwitchClosing
    function open() {
        popup.controller.show();
    }
    function close() {
        popup.controller.hide();
    }
    function closeForPopoutSwitch() {
        popup.closeForPopoutSwitch();
    }
    function act(args) {
        if (busy)
            return;
        error = "";
        control.command = ["/usr/bin/sudo", "-n", "--", helper].concat(args);
        control.running = true;
    }
    function result(text) {
        try {
            var data = JSON.parse(text);
            if (data.error)
                error = data.error;
            else if (data.curves) {
                if (!poll.running)
                    poll.running = true;
                curves = data.curves;
                backup = data.backup;
            } else if (data.rpm)
                stats = data;
        } catch (_) {
            error = "failed";
        }
    }
    function value(v, unit) {
        return v !== undefined && v !== null ? v + unit : "—";
    }
    Process {
        id: poll
        command: [root.helper, "metrics"]
        stdout: StdioCollector {
            onStreamFinished: if (text.length)
                root.result(text)
        }
    }
    Process {
        id: control
        stdout: StdioCollector {
            onStreamFinished: root.result(text)
        }
    }
    Timer {
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!poll.running)
            poll.running = true
    }
    ShellIpc {
        target: "msi.katana-fans"
        function open(): void {
            root.open();
        }
    }
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight
    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: root.showRpm ? "󰈐 " + root.rpmText : "󰈐"
        tooltipText: "MSI Katana Fan · " + root.rpmText + strings.t("rpm")
        onWheelMoved: function(delta) {
            root.wheelDelta += delta;
            if (Math.abs(root.wheelDelta) < 120)
                return;
            root.wheelDelta = 0;
            root.settings = Object.assign({}, root.settings, {showRpm: !root.showRpm});
        }
        onPressed: root.opened ? root.close() : root.open()
    }
    Panel {
        id: popup
        moduleName: root.moduleName
        manageIpc: false
        bar: root.bar
        KeyboardPanel {
            id: panel
            anchorItem: button
            owner: root
            bar: root.bar
            open: popup.opened
            contentWidth: panel.fittedContentWidth(Style.space(440))
            contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)
            content: Column {
                spacing: Style.space(8)
                PlainText {
                    text: strings.t("title")
                    font.pixelSize: Style.font.body
                }
                PlainText {
                    text: "CPU " + root.value(root.stats.temp[0], " °C") + "   ·   GPU " + root.value(root.stats.temp[1], " °C")
                }
                PlainText {
                    text: strings.t("fan1") + root.value(root.stats.rpm[0], strings.t("rpm")) + strings.t("fan2") + root.value(root.stats.rpm[1], strings.t("rpm"))
                }
                Flow {
                    width: parent.width
                    spacing: Style.space(4)
                    Repeater {
                        model: ["auto", "silent", "advanced"]
                        Button {
                            fontFamily: root.shellFont
                            required property string modelData
                            text: ({
                                    auto: "Auto",
                                    silent: "Silent",
                                    advanced: "Advanced"
                                })[modelData]
                            active: root.stats.mode === modelData
                            enabled: !root.busy && !!root.stats.mode && (modelData !== "advanced" || root.curves.length === 2)
                            onClicked: root.act(["mode", modelData])
                        }
                    }
                    Button {
                        fontFamily: root.shellFont
                        text: "Cooler Boost"
                        active: root.stats.boost === "on"
                        enabled: !root.busy && !!root.stats.mode
                        onClicked: root.act(["boost", active ? "off" : "on"])
                    }
                }
                Button {
                    fontFamily: root.shellFont
                    text: strings.t("read")
                    enabled: !root.busy && !!root.stats.mode
                    onClicked: root.act(["read"])
                }
                Repeater {
                    id: editors
                    model: root.curves
                    Column {
                        required property var modelData
                        required property int index
                        property alias points: points
                        width: parent.width
                        spacing: Style.space(4)
                        PlainText {
                            text: parent.index === 0 ? strings.t("cpu") : strings.t("gpu")
                        }
                        Row {
                            width: parent.width
                            spacing: Style.space(4)
                            Repeater {
                                id: points
                                model: parent.parent.modelData[0]
                                Column {
                                    id: point
                                    required property int modelData
                                    required property int index
                                    property alias input: field.text
                                    width: (parent.width - parent.spacing * 5) / 6
                                    PlainText {
                                        text: point.index === 0 ? strings.t("start") : point.modelData + " °C"
                                    }
                                    Rectangle {
                                        width: parent.width
                                        height: Style.space(28)
                                        radius: Style.cornerRadius
                                        color: Commons.Color.background
                                        border.color: Commons.Color.foreground
                                        TextInput {
                                            id: field
                                            font.family: root.shellFont
                                            font.pixelSize: Style.font.bodySmall
                                            anchors.fill: parent
                                            color: Commons.Color.foreground
                                            horizontalAlignment: TextInput.AlignHCenter
                                            verticalAlignment: TextInput.AlignVCenter
                                            selectByMouse: true
                                            maximumLength: 3
                                            validator: IntValidator {
                                                bottom: 0
                                                top: 100
                                            }
                                            text: point.parent.parent.modelData[1][point.index]
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                Flow {
                    width: parent.width
                    spacing: Style.space(4)
                    visible: root.curves.length === 2
                    Button {
                        fontFamily: root.shellFont
                        text: strings.t("apply")
                        enabled: !root.busy
                        onClicked: {
                            var args = ["apply"];
                            for (var i = 0; i < 2; ++i) {
                                var points = editors.itemAt(i).points;
                                for (var j = 0; j < 6; ++j)
                                    args.push(points.itemAt(j).input);
                            }
                            root.act(args);
                        }
                    }
                    Button {
                        fontFamily: root.shellFont
                        text: strings.t("restore")
                        enabled: root.backup && !root.busy
                        onClicked: root.act(["restore"])
                    }
                }
                PlainText {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    visible: text.length > 0
                    text: (root.error === "failed" ? strings.t("failed") : root.error) || (root.stats.mode ? "" : strings.t("unavailable"))
                }
            }
        }
    }
}
