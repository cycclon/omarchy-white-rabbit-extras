import QtQuick
import QtQuick.Window

// Development harness. RainScene is plain QtQuick, so the renderer can be
// tuned in a normal window without restarting the shell:
//
//   cd ~/.config/omarchy/plugins/cycclon.rain
//   QT_FORCE_STDERR_LOGGING=1 /usr/lib/qt6/bin/qml Preview.qml
//
// (Qt sends qml console output to the journal unless that variable is set,
// which makes a plain run look silent.)
//
// Note that the shell caches compiled QML per file: editing RainScene.qml or
// RainModel.js and running `omarchy-shell shell rescanPlugins` reloads the
// entry point but keeps the cached sub-components. Use `omarchy restart shell`
// after changing anything other than Rain.qml.
Window {
  width: 1280
  height: 720
  visible: true
  color: "#010604"
  title: "digital rain"

  RainScene {
    id: rain
    anchors.fill: parent
  }

  // Force an alignment every few seconds instead of waiting for one.
  Timer {
    interval: 8000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: console.log(rain.forceWord("LINUX", false))
  }
}
