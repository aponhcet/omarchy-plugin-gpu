import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "aponhcet.gpu"
  ipcTarget: "aponhcet.gpu"
  manageIpc: false

  // Brief polls read /proc and connector status only. nvidia-smi wakes the
  // discrete GPU out of runtime suspend, so the detailed read runs only
  // while this panel is open.
  readonly property string scriptPath: decodeScript(Qt.resolvedUrl("gpu-status"))
  property string active: "unknown"
  property string preference: "auto"
  property string next: "unknown"
  property string intelName: ""
  property string nvidiaName: ""
  property bool needsLogout: false
  property bool intelPresent: true
  property bool nvidiaPresent: true
  property bool nvidiaConnected: false
  property var nvidiaUtil: null
  property var nvidiaPower: null
  property var nvidiaMem: null
  property var outputs: []
  property string error: ""
  property bool logoutArmed: false
  property string focusSection: "modes"
  property int modeIndex: 0
  property bool cursorActive: false
  property int requestId: 0
  property int statusToken: 0
  property bool refreshQueued: false
  property bool refreshAfterSet: false

  readonly property var modes: ["auto", "intel", "nvidia"]
  readonly property color foreground: bar ? bar.foreground : Commons.Color.foreground
  readonly property color urgent: bar ? bar.urgent : Commons.Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property bool barVertical: bar ? bar.vertical : false
  readonly property bool statsReady: typeof nvidiaUtil === "number" && typeof nvidiaPower === "number" && typeof nvidiaMem === "number"

  readonly property string mark: {
    var _lang = strings.language
    var full = active === "nvidia" ? strings.t("gpu.markNvidia")
      : active === "intel" ? strings.t("gpu.markIntel")
      : strings.t("gpu.markUnknown")
    return barVertical && full.length > 0 ? full.charAt(0) : full
  }

  readonly property string tooltipLine: {
    var _lang = strings.language
    var now = gpuWord(active)
    if (!needsLogout) return strings.t("gpu.tooltipSame").arg(now)
    return strings.t("gpu.tooltip").arg(now).arg(gpuWord(next))
  }

  function decodeScript(url) {
    var path = String(url || "")
    if (path.indexOf("file://") === 0) path = path.substring(7)
    try {
      path = decodeURIComponent(path)
    } catch (e) {
    }
    return path
  }

  function gpuWord(id) {
    if (id === "nvidia") return strings.t("gpu.nvidia")
    if (id === "intel") return strings.t("gpu.intel")
    if (id === "other") return strings.t("gpu.other")
    return strings.t("gpu.unknown")
  }

  function modeAvailable(mode) {
    if (mode === "intel") return intelPresent
    if (mode === "nvidia") return nvidiaPresent
    return true
  }

  function shownName(id) {
    var custom = id === "nvidia" ? nvidiaName : id === "intel" ? intelName : ""
    if (custom !== "") return custom
    return gpuWord(id)
  }

  function asNumber(value) {
    return typeof value === "number" && isFinite(value) ? value : null
  }

  function applyStatus(raw) {
    var data
    try {
      data = JSON.parse(String(raw || ""))
    } catch (e) {
      error = strings.t("gpu.readFailed")
      return
    }
    if (!data || (data.active !== "intel" && data.active !== "nvidia" && data.active !== "unknown")) {
      error = strings.t("gpu.readFailed")
      return
    }
    active = data.active
    if (data.preference === "auto" || data.preference === "intel" || data.preference === "nvidia")
      preference = data.preference
    if (data.next === "intel" || data.next === "nvidia")
      next = data.next
    if (typeof data.needsLogout === "boolean") needsLogout = data.needsLogout
    if (typeof data.intelPresent === "boolean") intelPresent = data.intelPresent
    if (typeof data.nvidiaPresent === "boolean") nvidiaPresent = data.nvidiaPresent
    if (typeof data.nvidiaConnected === "boolean") nvidiaConnected = data.nvidiaConnected
    if (data.detail === true) {
      intelName = Model.plain(data.intelName)
      nvidiaName = Model.plain(data.nvidiaName)
      nvidiaUtil = asNumber(data.nvidiaUtil)
      nvidiaPower = asNumber(data.nvidiaPower)
      nvidiaMem = asNumber(data.nvidiaMem)
    }
    var list = []
    if (Array.isArray(data.outputs)) {
      var count = Math.min(data.outputs.length, 8)
      for (var i = 0; i < count; i++) {
        var row = data.outputs[i]
        if (!row) continue
        var connector = Model.plain(row.connector)
        if (!/^[A-Za-z0-9][A-Za-z0-9_.-]*$/.test(connector)) continue
        var gpu = row.gpu === "intel" || row.gpu === "nvidia" || row.gpu === "other" ? row.gpu : ""
        if (gpu === "") continue
        list.push({ connector: connector, gpu: gpu, desktop: row.desktop === true })
      }
    }
    outputs = list
    error = ""
    if (!needsLogout) logoutArmed = false
    if (!needsLogout && focusSection === "logout") focusSection = "modes"
  }

  function refresh() {
    if (scriptPath === "") return
    if (setProc.running) {
      refreshAfterSet = true
      return
    }
    if (statusProc.running) {
      refreshQueued = true
      return
    }
    requestId += 1
    statusToken = requestId
    statusProc.command = ["bash", scriptPath, opened ? "status" : "brief"]
    statusProc.running = true
  }

  function setMode(mode) {
    if (!Model.allowedMode(mode) || !modeAvailable(mode)) return
    if (scriptPath === "" || setProc.running) return
    logoutArmed = false
    requestId += 1
    setProc.command = ["bash", scriptPath, "set", mode]
    setProc.running = true
  }

  function cyclePreference() {
    var index = modes.indexOf(preference)
    if (index < 0) index = 0
    for (var guard = 0; guard < modes.length; guard++) {
      index = (index + 1) % modes.length
      if (modeAvailable(modes[index])) {
        setMode(modes[index])
        return
      }
    }
  }

  function requestLogout() {
    if (!needsLogout || !bar) return
    if (!logoutArmed) {
      logoutArmed = true
      focusSection = "logout"
      cursorActive = true
      return
    }
    bar.run("omarchy system logout")
  }

  function moveCursor(dx, dy) {
    if (dy > 0 && focusSection === "modes" && needsLogout) focusSection = "logout"
    else if (dy < 0 && focusSection === "logout") focusSection = "modes"
    else if (dx !== 0 && focusSection === "modes") {
      var index = modeIndex + dx
      if (index < 0) index = 0
      if (index > modes.length - 1) index = modes.length - 1
      modeIndex = index
    }
  }

  function activateCursor() {
    if (focusSection === "logout") requestLogout()
    else setMode(modes[modeIndex])
  }

  function statusLine() {
    return active + " preference=" + preference + " next=" + next + (needsLogout ? " pending" : " current")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: refresh()

  onOpenedChanged: {
    logoutArmed = false
    cursorActive = false
    modeIndex = Math.max(0, modes.indexOf(preference))
    refresh()
    poll.restart()
    if (opened) {
      Qt.callLater(function() {
        if (panel.loadedContent) panel.loadedContent.forceActiveFocus()
      })
    }
  }

  onNeedsLogoutChanged: if (!needsLogout) logoutArmed = false

  Commons.Translations {
    id: strings
    directory: Qt.resolvedUrl("i18n")
  }

  Timer {
    id: poll
    interval: root.opened ? 4000 : 8000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      id: statusOut
      waitForEnd: true
    }
    onExited: function(code) {
      if (root.statusToken === root.requestId) {
        if (code === 0) root.applyStatus(statusOut.text)
        else root.error = strings.t("gpu.readFailed")
      }
      if (root.refreshQueued) {
        root.refreshQueued = false
        root.refresh()
      }
    }
  }

  Process {
    id: setProc
    stdout: StdioCollector {
      id: setOut
      waitForEnd: true
    }
    onExited: function(code) {
      if (code === 0) root.applyStatus(setOut.text)
      else root.error = strings.t("gpu.writeFailed")
      if (root.opened || root.refreshAfterSet) {
        root.refreshAfterSet = false
        root.refresh()
      }
    }
  }

  ShellIpc {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { root.refresh(); return root.statusLine() }
    function status(): string { return root.statusLine() }
    function choose(id: string): string {
      root.setMode(id)
      return "ok"
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.mark
    fontSize: Style.font.subtitle
    tooltipText: root.tooltipLine
    active: root.needsLogout
    activeColor: Commons.Color.accent
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.cyclePreference()
      else if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: panel.loadedContent
    contentWidth: panel.fittedContentWidth(Style.space(360))
    contentHeight: panel.fittedContentHeight(panel.loadedContentHeight)

    content: PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      implicitHeight: column.implicitHeight
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) {
          root.cursorActive = true
          return
        }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "a" || t === "A") root.setMode("auto")
        else if (t === "i" || t === "I") root.setMode("intel")
        else if (t === "n" || t === "N") root.setMode("nvidia")
        else if (t === "r" || t === "R") root.refresh()
      }

      Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        Row {
          width: parent.width
          spacing: Style.space(14)

          Text {
            id: heroMark
            textFormat: Text.PlainText
            text: root.mark
            color: root.needsLogout ? Commons.Color.accent : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            width: parent.width - heroMark.width - parent.spacing
            spacing: Style.space(2)

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: strings.t("gpu.title")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: {
                var _lang = strings.language
                return root.needsLogout ? strings.t("gpu.pending") : strings.t("gpu.inUse")
              }
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              elide: Text.ElideRight
            }

            Text {
              width: parent.width
              textFormat: Text.PlainText
              text: {
                var _lang = strings.language
                return root.shownName(root.active)
              }
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(8)

          PanelSectionHeader {
            text: strings.t("gpu.displays")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Text {
            width: parent.width
            visible: root.outputs.length === 0
            textFormat: Text.PlainText
            text: strings.t("gpu.noDisplays")
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Repeater {
            model: root.outputs
            Text {
              required property var modelData
              width: column.width
              textFormat: Text.PlainText
              text: {
                var _lang = strings.language
                var key = modelData.desktop ? "gpu.outputDesktop" : "gpu.outputConnected"
                return strings.t(key).arg(modelData.connector).arg(root.gpuWord(modelData.gpu))
              }
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }
          }

          Text {
            width: parent.width
            visible: root.statsReady
            textFormat: Text.PlainText
            text: {
              var _lang = strings.language
              if (!root.statsReady) return ""
              return strings.t("gpu.nvidiaStats")
                .arg(Commons.I18n.formatNumber(root.nvidiaUtil, 0))
                .arg(Commons.I18n.formatNumber(root.nvidiaPower, 1))
                .arg(Commons.I18n.formatNumber(root.nvidiaMem, 0))
            }
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(10)

          PanelSectionHeader {
            text: strings.t("gpu.nextLogin")
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Row {
            id: modeRow
            width: parent.width
            spacing: Style.space(6)
            readonly property real cellWidth: (width - spacing * 2) / 3

            Repeater {
              model: root.modes
              Button {
                required property var modelData
                required property int index
                width: modeRow.cellWidth
                text: {
                  var _lang = strings.language
                  if (modelData === "intel") return strings.t("gpu.intel")
                  if (modelData === "nvidia") return strings.t("gpu.nvidia")
                  return strings.t("gpu.auto")
                }
                fontSize: Style.font.bodySmall
                foreground: root.foreground
                fontFamily: root.fontFamily
                bordered: true
                enabled: root.modeAvailable(modelData)
                opacity: enabled ? 1 : 0.35
                active: root.preference === modelData
                hasCursor: root.cursorActive && root.focusSection === "modes" && root.modeIndex === index
                onClicked: root.setMode(modelData)
                onHovered: function(h) {
                  if (!h) return
                  root.cursorActive = true
                  root.focusSection = "modes"
                  root.modeIndex = index
                }
              }
            }
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: {
              var _lang = strings.language
              if (root.preference === "intel") return strings.t("gpu.intelHint")
              if (root.preference === "nvidia") return strings.t("gpu.nvidiaHint")
              return strings.t("gpu.autoHint")
            }
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          Text {
            width: parent.width
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: strings.t("gpu.appsNote")
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }
        }

        Button {
          visible: root.needsLogout
          width: parent.width
          text: {
            var _lang = strings.language
            return root.logoutArmed ? strings.t("gpu.logoutConfirm") : strings.t("gpu.logout")
          }
          fontSize: Style.font.body
          foreground: root.logoutArmed ? root.urgent : root.foreground
          fontFamily: root.fontFamily
          bordered: true
          hasCursor: root.cursorActive && root.focusSection === "logout"
          onClicked: root.requestLogout()
          onHovered: function(h) {
            if (!h) return
            root.cursorActive = true
            root.focusSection = "logout"
          }
        }

        Text {
          width: parent.width
          visible: root.needsLogout
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: strings.t("gpu.logoutDetail")
          color: Qt.darker(root.foreground, 1.4)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          width: parent.width
          visible: root.error !== ""
          wrapMode: Text.WordWrap
          textFormat: Text.PlainText
          text: root.error
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }
  }
}
