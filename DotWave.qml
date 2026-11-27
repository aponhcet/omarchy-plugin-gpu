import QtQuick
import qs.Commons

// A traveling wave of dots. The motion is linear because it is a spinner:
// it keeps moving for as long as a read is in flight. Style.duration returns
// 0 when motion is reduced, and the dots then sit in a row.
Item {
  id: root

  property color color: "white"
  property int dots: 5
  property bool running: true
  property real phase: 0

  implicitWidth: Math.max(0, dots * Style.space(8) - Style.space(4))
  implicitHeight: Style.space(16)

  NumberAnimation on phase {
    from: 0
    to: Math.PI * 2
    duration: Style.duration(960)
    loops: Animation.Infinite
    running: root.running && !Style.reduceMotion
    easing.type: Easing.Linear
  }

  Repeater {
    model: root.dots

    Rectangle {
      required property int index
      readonly property real wave: root.running && !Style.reduceMotion
        ? Math.sin(root.phase - index * 0.85)
        : 0
      width: Style.space(4)
      height: width
      radius: width / 2
      x: index * Style.space(8)
      y: (root.implicitHeight - height) / 2 - Style.space(3) * wave
      color: root.color
      opacity: 0.3 + 0.7 * (0.5 + 0.5 * wave)
      scale: 0.74 + 0.26 * (0.5 + 0.5 * wave)
    }
  }
}
