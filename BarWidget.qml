import QtQuick
import Quickshell
import qs.Commons as Commons
import qs.Ui

BarWidget {
    id: root
    moduleName: "io.github.amiradelevich.omarchy-addons"
    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    Commons.Translations {
        id: strings
        directory: Qt.resolvedUrl("i18n")
    }

    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: "󰏗"
        tooltipText: strings.t("tooltip")
        onPressed: {
            const script = decodeURIComponent(Qt.resolvedUrl("addons-menu.sh").toString().replace(/^file:\/\//, ""));
            Quickshell.execDetached(["omarchy", "launch", "terminal", "bash", script]);
        }
    }
}
