import QtQuick
import QtQuick.Shapes
import qs.Common

// Original small-size mark inspired by Ente Auth's rounded e and shield.
Item {
    id: root
    implicitWidth: 24
    implicitHeight: 24
    property color color: Theme.primary
    property color accentColor: color
    Item {
        width: 24
        height: 24
        anchors.centerIn: parent
        scale: Math.min(root.width, root.height) / 24
        Shape {
            anchors.fill: parent
            ShapePath {
                strokeColor: root.color
                strokeWidth: 2.2
                capStyle: ShapePath.RoundCap
                joinStyle: ShapePath.RoundJoin
                fillColor: "transparent"
                PathSvg { path: "M11 12.5H19.4C22.5 12.5 22.3 9.6 20.7 7.4C18.5 4.1 13.8 3.5 10.6 5.1 M6.8 12.2C5.5 17.7 9.4 21.1 14.3 21.1C17.1 21.1 20.3 20.1 20.3 17.8C20.3 16.5 19.3 15.7 17.7 15.7H13.1" }
            }
            ShapePath {
                strokeColor: "transparent"
                fillColor: root.accentColor
                PathSvg { path: "M5.4 2.5L9.6 4.2V7.5C9.6 9.6 7.5 11.2 5.4 12.4C3.3 11.2 1.2 9.6 1.2 7.5V4.2Z" }
            }
        }
    }
}
