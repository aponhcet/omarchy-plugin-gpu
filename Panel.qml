import QtQuick
import QtQuick.Controls as Controls
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
  property var apps: []
  property bool appsAdvanced: false
  property bool detailSeen: false
  readonly property bool gpuRefreshing: opened && statusProc.running
  readonly property bool appsLoading: opened && !detailSeen && error === ""
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
      var found = []
      if (Array.isArray(data.apps)) {
        var appCount = Math.min(data.apps.length, 8)
        for (var a = 0; a < appCount; a++) {
          var app = data.apps[a]
          if (!app) continue
          var appName = Model.plain(app.name)
          if (appName === "") continue
          var appGpu = app.gpu === "intel" || app.gpu === "nvidia" || app.gpu === "both" || app.gpu === "none" ? app.gpu : ""
          if (appGpu === "") continue
          var appId = Model.allowedAppId(app.id) ? app.id : ""
          if (appId === "" && appGpu === "none") continue
          var appPref = app.preference === "intel" || app.preference === "nvidia" ? app.preference : "desktop"
          found.push({
            id: appId,
            name: appName,
            gpu: appGpu,
            preference: appPref,
            launchable: app.launchable === true && appId !== "",
            attached: app.attached === true
          })
        }
      }
      apps = found
      detailSeen = true
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

  function setAppPref(id, mode) {
    if (!Model.allowedAppId(id) || !Model.allowedAppPref(mode)) return
    if (mode === "intel" && !intelPresent) return
    if (mode === "nvidia" && !nvidiaPresent) return
    if (scriptPath === "" || setProc.running) return
    requestId += 1
    setProc.command = ["bash", scriptPath, "set-app", id, mode]
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
    if (!opened) {
      appsAdvanced = false
      detailSeen = false
    } else {
      detailSeen = false
      apps = []
    }
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
    function pin(id: string, mode: string): string {
      root.setAppPref(id, mode)
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

            Item {
              width: parent.width
              height: gpuName.implicitHeight

              Text {
                id: gpuName
                width: parent.width - (gpuWave.visible ? gpuWave.implicitWidth + Style.space(8) : 0)
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
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

              DotWave {
                id: gpuWave
                visible: root.gpuRefreshing
                running: root.gpuRefreshing
                color: root.foreground
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
              }
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
          spacing: Style.space(8)

          Item {
            width: parent.width
            height: Math.max(appsHeader.implicitHeight, advancedChevron.height)

            PanelSectionHeader {
              id: appsHeader
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: strings.t("gpu.apps")
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            DotWave {
              visible: root.opened && root.statusProc.running && root.detailSeen
              running: visible
              anchors.left: appsHeader.right
              anchors.leftMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              color: root.foreground
            }

            Rectangle {
              id: advancedChevron
              visible: root.apps.length > 0 && !root.appsLoading
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Style.space(22)
              height: Style.space(22)
              radius: Math.min(width / 2, Style.cornerRadius)
              color: advancedHover.containsMouse
                ? Style.hoverFillFor(root.foreground, Commons.Color.accent)
                : "transparent"

              Text {
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "󰅀"
                color: root.appsAdvanced ? root.foreground : Qt.darker(root.foreground, 1.35)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                rotation: root.appsAdvanced ? 180 : 0
                transformOrigin: Item.Center
                Behavior on rotation {
                  RotationAnimation {
                    duration: Style.duration(180)
                    direction: RotationAnimation.Shortest
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Style.easeOut
                  }
                }
              }

              MouseArea {
                id: advancedHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                Accessible.name: strings.t("gpu.advanced")
                Accessible.role: Accessible.Button
                onClicked: root.appsAdvanced = !root.appsAdvanced
              }

              PanelToolTip {
                visible: advancedHover.containsMouse
                text: strings.t("gpu.advanced")
                delay: 400
              }
            }
          }

          DotWave {
            visible: root.appsLoading
            running: root.appsLoading
            dots: 7
            anchors.horizontalCenter: parent.horizontalCenter
            color: root.foreground
          }

          Text {
            width: parent.width
            visible: root.apps.length === 0 && !root.appsLoading && root.error === ""
            textFormat: Text.PlainText
            text: strings.t("gpu.noApps")
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Repeater {
            model: root.apps
            Column {
              id: appRow
              required property var modelData
              width: column.width
              spacing: 0
              readonly property string appId: modelData && modelData.id ? modelData.id : ""
              readonly property string appPref: modelData && (modelData.preference === "intel" || modelData.preference === "nvidia") ? modelData.preference : "desktop"
              readonly property bool appLaunchable: !!(modelData && modelData.launchable && appId !== "")
              readonly property bool appAttached: !!(modelData && modelData.attached)
              readonly property bool showChoices: root.appsAdvanced && (appLaunchable || (appPref !== "desktop" && !appAttached))

              Text {
                width: parent.width
                textFormat: Text.PlainText
                text: {
                  var _lang = strings.language
                  if (appRow.modelData.gpu === "both") {
                    return strings.t("gpu.appBoth")
                      .arg(appRow.modelData.name)
                      .arg(strings.t("gpu.nvidia"))
                      .arg(strings.t("gpu.intel"))
                  }
                  if (appRow.modelData.gpu === "none")
                    return strings.t("gpu.appIdle").arg(appRow.modelData.name)
                  return strings.t("gpu.appOne").arg(appRow.modelData.name).arg(root.gpuWord(appRow.modelData.gpu))
                }
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
              }

              Item {
                id: reveal
                width: parent.width
                clip: true
                height: appRow.showChoices ? revealBody.implicitHeight : 0
                Behavior on height {
                  NumberAnimation {
                    duration: Style.duration(root.appsAdvanced ? 180 : 120)
                    easing.type: Easing.Bezier
                    easing.bezierCurve: Style.easeOut
                  }
                }

                Column {
                  id: revealBody
                  width: parent.width
                  spacing: Style.space(4)
                  topPadding: Style.space(6)
                  y: root.appsAdvanced ? 0 : -Style.space(8)
                  opacity: root.appsAdvanced ? 1 : 0
                  Behavior on y {
                    NumberAnimation {
                      duration: Style.duration(root.appsAdvanced ? 180 : 120)
                      easing.type: Easing.Bezier
                      easing.bezierCurve: Style.easeOut
                    }
                  }
                  Behavior on opacity {
                    NumberAnimation {
                      duration: Style.duration(root.appsAdvanced ? 160 : 100)
                      easing.type: Easing.OutCubic
                    }
                  }

                  Row {
                    id: appModeRow
                    visible: appRow.appLaunchable
                    width: parent.width
                    spacing: Style.space(6)
                    readonly property real cellWidth: (width - spacing * 2) / 3

                    Repeater {
                      model: ["desktop", "intel", "nvidia"]
                      Button {
                        id: gpuChoice
                        required property var modelData
                        width: appModeRow.cellWidth
                        text: {
                          var _lang = strings.language
                          if (modelData === "intel") return strings.t("gpu.intel")
                          if (modelData === "nvidia") return strings.t("gpu.nvidia")
                          return strings.t("gpu.appDesktop")
                        }
                        fontSize: Style.font.bodySmall
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        bordered: true
                        enabled: root.appsAdvanced && (modelData === "desktop" || (modelData === "intel" && root.intelPresent) || (modelData === "nvidia" && root.nvidiaPresent))
                        opacity: enabled ? 1 : 0.35
                        active: appRow.appPref === modelData
                        hasCursor: false
                        onClicked: root.setAppPref(appRow.appId, modelData)

                        HoverHandler {
                          id: pointer
                          onHoveredChanged: {
                            if (hovered && gpuChoice.modelData === "desktop") tipWait.restart()
                            else {
                              tipWait.stop()
                              tip.tipOpen = false
                            }
                          }
                        }

                        Timer {
                          id: tipWait
                          interval: Math.max(Style.duration(90), 1)
                          onTriggered: tip.tipOpen = true
                        }

                        // The choice row is clipped while it slides open, so the
                        // note is parented to the window overlay and tracks the pointer.
                        PanelToolTip {
                          id: tip
                          property bool tipOpen: false
                          parent: Controls.Overlay.overlay
                          visible: root.opened && root.appsAdvanced && gpuChoice.modelData === "desktop" && tipOpen && pointer.hovered
                          text: strings.t("gpu.appDesktopTip")
                          delay: 0
                          closePolicy: Controls.Popup.NoAutoClose
                          transformOrigin: Item.Top
                          x: {
                            var overlay = Controls.Overlay.overlay
                            var raw = pointer.point.scenePosition.x - width / 2
                            if (!overlay) return raw
                            return Math.max(Style.space(8), Math.min(raw, overlay.width - width - Style.space(8)))
                          }
                          y: pointer.point.scenePosition.y + Style.space(18)
                          enter: Transition {
                            ParallelAnimation {
                              NumberAnimation {
                                property: "opacity"
                                from: 0
                                to: 1
                                duration: Style.duration(140)
                                easing.type: Easing.OutCubic
                              }
                              NumberAnimation {
                                property: "scale"
                                from: 0.96
                                to: 1
                                duration: Style.duration(140)
                                easing.type: Easing.Bezier
                                easing.bezierCurve: Style.easeOut
                              }
                            }
                          }
                          exit: Transition {
                            NumberAnimation {
                              property: "opacity"
                              from: 1
                              to: 0
                              duration: Style.duration(100)
                              easing.type: Easing.OutCubic
                            }
                          }
                        }
                      }
                    }
                  }

                  Text {
                    width: parent.width
                    visible: appRow.appPref !== "desktop" && !appRow.appAttached
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    text: strings.t("gpu.appNoLauncher")
                    color: Qt.darker(root.foreground, 1.4)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          Item {
            width: parent.width
            clip: true
            visible: root.apps.length > 0
            height: root.appsAdvanced ? launchNote.implicitHeight : 0
            Behavior on height {
              NumberAnimation {
                duration: Style.duration(root.appsAdvanced ? 180 : 120)
                easing.type: Easing.Bezier
                easing.bezierCurve: Style.easeOut
              }
            }

            Text {
              id: launchNote
              width: parent.width
              topPadding: Style.space(6)
              wrapMode: Text.WordWrap
              textFormat: Text.PlainText
              text: strings.t("gpu.appLaunch")
              color: Qt.darker(root.foreground, 1.4)
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              y: root.appsAdvanced ? 0 : -Style.space(8)
              opacity: root.appsAdvanced ? 1 : 0
              Behavior on y {
                NumberAnimation {
                  duration: Style.duration(root.appsAdvanced ? 180 : 120)
                  easing.type: Easing.Bezier
                  easing.bezierCurve: Style.easeOut
                }
              }
              Behavior on opacity {
                NumberAnimation {
                  duration: Style.duration(root.appsAdvanced ? 160 : 100)
                  easing.type: Easing.OutCubic
                }
              }
            }
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
