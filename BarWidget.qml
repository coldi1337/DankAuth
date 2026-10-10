import QtQuick
import Quickshell
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: root
    readonly property var vault: PluginService.pluginDaemonInstances[pluginId] || null
    pillClickAction: () => {
        if (!vault) return;
        const screen = parentScreen || Quickshell.screens[0];
        const edge = axis?.edge === "left" ? 2 : axis?.edge === "right" ? 3 : axis?.edge === "bottom" ? 1 : 0;
        const pos = SettingsData.getPopupTriggerPosition(mapToItem(null, 0, 0), screen, barThickness, width, barSpacing, edge, barConfig);
        vault.setAnchor(pos.x, pos.y, pos.width, section, screen, edge, barThickness, barSpacing, barConfig);
        vault.toggle();
    }
    pillRightClickAction: () => vault?.openWindow()
    horizontalBarPill: Component {
        Item {
            implicitWidth: root.iconSize
            implicitHeight: root.widgetThickness
            Loader { anchors.centerIn: parent; width: root.iconSize; height: root.iconSize; source: Qt.resolvedUrl("AuthLogo.qml"); onLoaded: item.color = Qt.binding(() => root.vault?.unlocked ? Theme.primary : Theme.widgetIconColor) }
        }
    }
    verticalBarPill: Component {
        Item {
            implicitWidth: root.widgetThickness
            implicitHeight: root.iconSize
            Loader { anchors.centerIn: parent; width: root.iconSize; height: root.iconSize; source: Qt.resolvedUrl("AuthLogo.qml"); onLoaded: item.color = Qt.binding(() => root.vault?.unlocked ? Theme.primary : Theme.widgetIconColor) }
        }
    }
}
