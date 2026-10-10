import QtQuick
import qs.Common
import "testplugin"

// Match the typography and framing of the DankChat project preview.
Rectangle {
    id: root
    required property var service
    gradient: Gradient {
        GradientStop { position: 0; color: "#211a30" }
        GradientStop { position: 1; color: "#100e16" }
    }
    Text { x: 64; y: 90; text: "DANKMATERIALSHELL PLUGIN"; color: "#cbb7fa"; font.pixelSize: 16; font.letterSpacing: 3 }
    Text { x: 64; y: 190; text: "DankAuth"; color: "#f2ecfa"; font.pixelSize: 56 }
    Text { x: 64; y: 316; text: "Your codes. One place."; color: "#c9bfd5"; font.pixelSize: 23 }
    Rectangle { x: 64; y: 364; width: 68; height: 3; color: "#cbb7fa" }
    Text { x: 64; y: 391; text: "DankAuth 0.4.0"; color: "#e5ddec"; font.pixelSize: 23 }
    Text {
        x: 64; y: 443
        text: "Ente Auth · encrypted sync\nSearch, favorites & tags\nDropdown + desktop window"
        color: "#baadc9"; font.pixelSize: 20; lineHeight: 1.8
    }
    Text { x: 64; y: 674; text: "NATIVE DMS CLIENT  /  OPEN SOURCE"; color: "#a69ab5"; font.pixelSize: 12; font.letterSpacing: 2 }
    Rectangle { x: 600; y: 64; width: 622; height: 540; radius: 20; color: Theme.surface; border.color: Theme.outline }
    Item {
        x: 610; y: 76; width: 800; height: 696
        scale: 0.75; transformOrigin: Item.TopLeft
        AuthView { service: root.service; compact: false; now: root.service.snapshotAt }
    }
    Text { x: 600; y: 620; text: "Sample entries • No private accounts"; color: "#a69ab5"; font.pixelSize: 14 }
}
