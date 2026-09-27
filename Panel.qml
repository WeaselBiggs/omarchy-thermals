import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Thermals: a thermometer and one temperature in the bar, and a panel with
// every probe hwmon knows about. Layout follows the Vapour/agents panels —
// hero, section headers, a meter behind each row — with the readings coming
// from bin/collect via Main.qml.
Panel {
  id: root
  moduleName: "dan.thermals"
  ipcTarget: "dan.thermals"
  manageIpc: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color track: Style.selectedFillFor(foreground, Color.accent)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // nf-md-thermometer, and its "high" variant once anything is warm. Written
  // as surrogate pairs: the glyphs live above the BMP.
  readonly property string glyphCool: "󰔏"
  readonly property string glyphWarm: "󱃂"
  readonly property string glyphFan: "󰈐"
  readonly property string barGlyph: thermals.maxLevel > 0 ? glyphWarm : glyphCool

  readonly property var sensors: thermals.sensors
  readonly property var fans: thermals.fans
  readonly property int level: thermals.maxLevel

  // The cursor and the unfolded row follow the probe, not its slot, so a tick
  // that reorders nothing still cannot swap what you are reading.
  property string cursorId: ""
  property string expandedId: ""
  property bool cursorActive: false

  // Every navigable row in panel order: sensors first, then fans.
  readonly property var rowIds: {
    var ids = []
    for (var i = 0; i < sensors.length; i++) ids.push(String(sensors[i].id))
    for (var j = 0; j < fans.length; j++) ids.push(String(fans[j].id))
    return ids
  }
  readonly property int cursorIndex: rowIds.indexOf(cursorId)

  // "Updated 3s ago" reads this instead of Date.now() so it moves while open.
  property double nowMs: Date.now()

  function clamp(v, lo, hi) { return Math.max(lo, Math.min(hi, v)) }
  function alpha(c, a) { return Qt.rgba(c.r, c.g, c.b, a) }

  function moveCursor(delta) {
    if (rowIds.length === 0) return
    var index = cursorIndex < 0 ? (delta > 0 ? -1 : 0) : cursorIndex
    index = clamp(index + delta, 0, rowIds.length - 1)
    cursorActive = true
    cursorId = rowIds[index]
    Qt.callLater(ensureCursorVisible)
  }

  function toggleExpanded(id) {
    var key = String(id || "")
    expandedId = expandedId === key ? "" : key
  }

  function launchMonitor() {
    if (root.bar) root.bar.run("omarchy-launch-or-focus-tui btop")
    root.close()
  }

  function refreshNow() {
    thermals.refresh()
    nowMs = Date.now()
  }

  // Colour for a reading at a given level: quiet, then plain, then urgent.
  function toneFor(level, quiet) {
    if (level >= 2) return root.urgent
    if (level === 1) return root.foreground
    return quiet ? root.dim : root.foreground
  }

  function levelWord(level) {
    return level >= 2 ? "hot" : level === 1 ? "warm" : "fine"
  }

  // Keep the keyboard cursor's row inside the scrolled viewport.
  function ensureCursorVisible() {
    if (!panelFlick || cursorIndex < 0) return
    var row = rowItemFor(cursorId)
    if (!row) return
    var top = row.mapToItem(column, 0, 0).y
    var bottom = top + row.height
    if (top < panelFlick.contentY) panelFlick.contentY = Math.max(0, top - Style.space(8))
    else if (bottom > panelFlick.contentY + panelFlick.height)
      panelFlick.contentY = clamp(bottom - panelFlick.height + Style.space(8), 0, Math.max(0, panelFlick.contentHeight - panelFlick.height))
  }

  // Rows live inside nested repeaters, so finding one by id means walking them.
  function rowItemFor(id) {
    for (var g = 0; g < groupsRepeater.count; g++) {
      var section = groupsRepeater.itemAt(g)
      if (!section || !section.rows) continue
      for (var i = 0; i < section.rows.count; i++) {
        var row = section.rows.itemAt(i)
        if (row && row.rowId === id) return row
      }
    }
    for (var f = 0; f < fansRepeater.count; f++) {
      var fanRow = fansRepeater.itemAt(f)
      if (fanRow && fanRow.rowId === id) return fanRow
    }
    return null
  }

  // ------------------------------------------------- open / close plumbing

  // Summoning by hotkey moves no pointer, so a hover the bar was still holding
  // must not keep the center section revealed behind the panel. Clicking the
  // button is a real hover and needs none of this.
  function setCenterHoverRevealSuppressed(value) {
    if (root.bar && typeof root.bar.setCenterHoverRevealSuppressed === "function")
      root.bar.setCenterHoverRevealSuppressed(value)
  }

  function open() {
    setCenterHoverRevealSuppressed(false)
    root.controller.show()
  }

  function openFromHotkey() {
    root.controller.show()
    Qt.callLater(function() {
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }

  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }

  function toggle() { root.opened ? root.close() : root.open() }
  function toggleFromHotkey() { root.opened ? root.close() : root.openFromHotkey() }

  // ---------------------------------------------------------------- content

  function heroDetail() {
    return thermals.primary ? thermals.formatTemp(thermals.primary.c, true) : ""
  }

  function heroMeta() {
    var parts = []
    if (thermals.primary) parts.push(String(thermals.primary.label))
    if (thermals.hottest && (!thermals.primary || thermals.hottest.id !== thermals.primary.id))
      parts.push("Hottest " + thermals.hottest.label + " " + thermals.formatTemp(thermals.hottest.c, false))
    var fan = thermals.fanSummary()
    if (fan !== "") parts.push(fan)
    if (parts.length === 0) parts.push("Reading sensors")
    return parts.join(" · ")
  }

  function footerText() {
    var parts = []
    parts.push(sensors.length + (sensors.length === 1 ? " probe" : " probes"))
    if (thermals.hidden > 0 && !thermals.showAll) parts.push(thermals.hidden + " duplicates hidden")
    if (thermals.updatedAtMs > 0) parts.push("Updated " + thermals.formatAgo(thermals.updatedAtMs, root.nowMs))
    return parts.join(" · ")
  }

  function sensorTooltip(sensor) {
    if (!sensor) return ""
    var text = String(sensor.chip || "")
    if (sensor.raw) text += " · " + sensor.raw
    if (sensor.model) text += " · " + sensor.model
    text += " · warm " + thermals.formatTemp(thermals.warnOf(sensor), false)
      + " · hot " + thermals.formatTemp(thermals.hotOf(sensor), false)
    return text
  }

  function thresholdNote(sensor) {
    if (!sensor) return ""
    if (thermals.warnAt > 0 || thermals.hotAt > 0) return "Thresholds from your settings"
    return sensor.thresholdSource === "hwmon"
      ? "Thresholds reported by the driver"
      : "Driver reports no limits — using the default for its kind"
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    nowMs = Date.now()
    if (panelFlick) panelFlick.contentY = 0
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Main {
    id: thermals
    settings: root.settings
  }

  Timer {
    interval: 1000
    running: root.opened
    repeat: true
    onTriggered: root.nowMs = Date.now()
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.openFromHotkey() }
    function close(): void { root.close() }
    function show(): void { root.openFromHotkey() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggleFromHotkey() }
    function refresh(): string { root.refreshNow(); return "ok" }
    // One line of readings, for notifications and scripts.
    function temps(): string { return thermals.summary() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    readonly property bool labelShown: thermals.setting("showLabel", true) !== false && !root.vertical && !!thermals.primary
    text: labelShown
      ? root.barGlyph + " " + thermals.formatTemp(thermals.primary.c, false)
      : root.barGlyph
    // An icon slot is a fixed 21px; with a temperature beside the glyph the
    // text would overflow it on both sides and sit on top of the neighbours.
    // Size the slot to the painted text plus a margin each side instead.
    slotSize: labelShown
      ? Math.ceil(button.glyphPaintedWidth) + Style.space(24)
      : Style.bar.statusSlot
    active: root.level >= 2
    tooltipText: root.opened ? "" : thermals.summary()
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.launchMonitor()
      else if (buttonCode === Qt.MiddleButton) root.refreshNow()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(340))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent

      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy)
        if (dx !== 0 && root.cursorId !== "") {
          if (dx > 0) root.expandedId = root.cursorId
          else if (root.expandedId === root.cursorId) root.expandedId = ""
        }
      }
      onActivateRequested: if (root.cursorId !== "") root.toggleExpanded(root.cursorId)
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "r" || t === "R") root.refreshNow()
        else if (t === "b" || t === "B") root.launchMonitor()
        else if (t === " " && root.cursorId !== "") root.toggleExpanded(root.cursorId)
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          // ---------- Hero: thermometer · Thermals · primary reading ----------
          PanelHero {
            width: parent.width
            title: "Thermals"
            detail: root.heroDetail()
            meta: root.heroMeta()
            foreground: root.foreground
            fontFamily: root.fontFamily

            iconComponent: Component {
              Text {
                textFormat: Text.PlainText
                text: root.barGlyph
                color: root.toneFor(root.level, true)
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          // ---------- Status ----------
          BorderSurface {
            visible: thermals.collectorError !== ""
            width: parent.width
            implicitHeight: statusText.implicitHeight + Style.spacing.xl * 2
            color: root.alpha(root.urgent, 0.10)
            borderSpec: Border.flat(root.alpha(root.urgent, 0.35), 1)
            radius: Style.cornerRadius

            Text {
              id: statusText
              textFormat: Text.PlainText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(12)
              anchors.rightMargin: Style.space(12)
              text: thermals.collectorError
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
            }
          }

          Text {
            visible: root.sensors.length === 0 && thermals.collectorError === ""
            width: parent.width
            topPadding: Style.space(24)
            text: thermals.ready
              ? "No temperature sensors found under /sys/class/hwmon."
              : "Reading sensors…"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }

          // ---------- One section per group ----------
          Repeater {
            id: groupsRepeater
            model: thermals.groups

            Column {
              id: section
              required property var modelData
              readonly property alias rows: sectionRows
              width: column.width
              spacing: Style.spacing.md

              PanelSeparator { foreground: root.foreground }

              PanelSectionHeader {
                width: parent.width
                text: String(section.modelData.title || "").toUpperCase()
                foreground: root.foreground
                fontFamily: root.fontFamily
              }

              Column {
                width: parent.width
                spacing: Style.spacing.sm

                Repeater {
                  id: sectionRows
                  model: section.modelData.sensors

                  SensorRow {
                    required property var modelData
                    width: section.width
                    sensor: modelData
                  }
                }
              }
            }
          }

          // ---------- Fans ----------
          PanelSeparator {
            visible: fansSection.visible
            foreground: root.foreground
          }

          Column {
            id: fansSection
            visible: root.fans.length > 0
            width: parent.width
            spacing: Style.spacing.md

            PanelSectionHeader {
              width: parent.width
              text: root.fans.length === 1 ? "FAN" : "FANS"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.spacing.sm

              Repeater {
                id: fansRepeater
                model: root.fans

                FanRow {
                  required property var modelData
                  width: fansSection.width
                  fan: modelData
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: root.sensors.length > 0
            width: parent.width
            topPadding: Style.space(2)
            text: root.footerText()
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
          }
        }
      }
    }
  }

  // A probe: name at the left, its temperature at the right, and a meter
  // behind the row that fills as it approaches "hot". Click unfolds where the
  // reading comes from.
  component SensorRow: Column {
    id: sensorRow
    property var sensor: null

    readonly property string rowId: sensor ? String(sensor.id) : ""
    readonly property int level: thermals.levelOf(sensor)
    readonly property real ratio: thermals.ratioOf(sensor)
    readonly property bool expanded: rowId !== "" && root.expandedId === rowId
    readonly property bool hasCursor: root.cursorActive && root.cursorId === rowId

    spacing: 0

    CursorSurface {
      id: rowSurface
      width: parent.width
      implicitHeight: sensorName.implicitHeight + Style.spacing.lg * 2
      hasCursor: sensorRow.hasCursor
      current: sensorRow.expanded
      foreground: root.foreground

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: root.alpha(root.foreground, 0.05)
        visible: !sensorRow.hasCursor && !sensorRow.expanded
      }

      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * root.clamp(sensorRow.ratio, 0, 1)
        radius: Style.cornerRadius
        color: sensorRow.level >= 2 ? root.alpha(root.urgent, 0.28)
             : sensorRow.level === 1 ? root.alpha(root.foreground, 0.22)
             : root.alpha(root.foreground, 0.14)

        Behavior on width {
          NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }
        Behavior on color {
          ColorAnimation { duration: 240 }
        }
      }

      MouseArea {
        id: rowHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) {
          root.cursorActive = true
          root.cursorId = sensorRow.rowId
        }
        onClicked: {
          root.cursorActive = true
          root.cursorId = sensorRow.rowId
          root.toggleExpanded(sensorRow.rowId)
        }
      }

      Text {
        id: sensorName
        textFormat: Text.PlainText
        text: sensorRow.sensor ? String(sensorRow.sensor.label || "") : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: sensorRow.level >= 1
        elide: Text.ElideRight
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.right: sensorValue.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: sensorValue
        textFormat: Text.PlainText
        text: sensorRow.sensor ? thermals.formatTemp(sensorRow.sensor.c, false) : ""
        color: root.toneFor(sensorRow.level, true)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }

      PanelToolTip {
        visible: rowHover.containsMouse && !sensorRow.expanded
        text: root.sensorTooltip(sensorRow.sensor)
        fontFamily: root.fontFamily
      }
    }

    // ---------- Where the number comes from ----------
    Item {
      width: parent.width
      clip: true
      implicitHeight: sensorRow.expanded ? detailColumn.implicitHeight + Style.space(10) : 0
      visible: implicitHeight > 0

      Behavior on implicitHeight {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }

      Column {
        id: detailColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Style.space(6)
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(6)

        StatLine { label: "Driver"; value: sensorRow.sensor ? String(sensorRow.sensor.chip || "") : "" }
        StatLine {
          visible: value !== ""
          label: "Probe"
          value: sensorRow.sensor ? String(sensorRow.sensor.raw || "") : ""
        }
        StatLine {
          visible: value !== ""
          label: "Device"
          value: sensorRow.sensor ? String(sensorRow.sensor.model || "") : ""
        }
        StatLine {
          label: "Warm from"
          value: sensorRow.sensor ? thermals.formatTemp(thermals.warnOf(sensorRow.sensor), true) : ""
        }
        StatLine {
          label: "Hot from"
          value: sensorRow.sensor ? thermals.formatTemp(thermals.hotOf(sensorRow.sensor), true) : ""
        }
        StatLine { label: "Now"; value: root.levelWord(sensorRow.level) }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.thresholdNote(sensorRow.sensor)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: sensorRow.sensor ? String(sensorRow.sensor.path || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }
      }
    }
  }

  // A fan: name, speed. The meter fills against the fastest speed the driver
  // reports, or a plausible ceiling when it reports none.
  component FanRow: Column {
    id: fanRow
    property var fan: null

    readonly property string rowId: fan ? String(fan.id) : ""
    readonly property int rpm: fan ? thermals.numberValue(fan.rpm) : 0
    readonly property int ceiling: fan && thermals.numberValue(fan.max) > 0 ? thermals.numberValue(fan.max) : 6000
    readonly property bool hasCursor: root.cursorActive && root.cursorId === rowId
    readonly property bool expanded: rowId !== "" && root.expandedId === rowId

    spacing: 0

    CursorSurface {
      width: parent.width
      implicitHeight: fanName.implicitHeight + Style.spacing.lg * 2
      hasCursor: fanRow.hasCursor
      current: fanRow.expanded
      foreground: root.foreground

      Rectangle {
        anchors.fill: parent
        radius: Style.cornerRadius
        color: root.alpha(root.foreground, 0.05)
        visible: !fanRow.hasCursor && !fanRow.expanded
      }

      Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: parent.width * root.clamp(fanRow.rpm / fanRow.ceiling, 0, 1)
        radius: Style.cornerRadius
        color: root.alpha(root.foreground, 0.14)

        Behavior on width {
          NumberAnimation { duration: 240; easing.type: Easing.OutCubic }
        }
      }

      MouseArea {
        id: fanHover
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onContainsMouseChanged: if (containsMouse) {
          root.cursorActive = true
          root.cursorId = fanRow.rowId
        }
        onClicked: {
          root.cursorActive = true
          root.cursorId = fanRow.rowId
          root.toggleExpanded(fanRow.rowId)
        }
      }

      Text {
        id: fanGlyph
        textFormat: Text.PlainText
        text: root.glyphFan
        color: fanRow.rpm > 0 ? root.foreground : root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        anchors.left: parent.left
        anchors.leftMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: fanName
        textFormat: Text.PlainText
        text: fanRow.fan ? String(fanRow.fan.label || "Fan") : ""
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
        anchors.left: fanGlyph.right
        anchors.leftMargin: Style.space(8)
        anchors.right: fanValue.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }

      Text {
        id: fanValue
        textFormat: Text.PlainText
        text: thermals.formatRpm(fanRow.fan)
        color: fanRow.fan && fanRow.fan.fault === true ? root.urgent : (fanRow.rpm > 0 ? root.foreground : root.dim)
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.bold: true
        anchors.right: parent.right
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
      }

      PanelToolTip {
        visible: fanHover.containsMouse && !fanRow.expanded
        text: fanRow.fan ? String(fanRow.fan.chip || "") + (thermals.numberValue(fanRow.fan.target) > 0 ? " · target " + thermals.numberValue(fanRow.fan.target) + " rpm" : "") : ""
        fontFamily: root.fontFamily
      }
    }

    Item {
      width: parent.width
      clip: true
      implicitHeight: fanRow.expanded ? fanDetail.implicitHeight + Style.space(10) : 0
      visible: implicitHeight > 0

      Behavior on implicitHeight {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }

      Column {
        id: fanDetail
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: Style.space(6)
        anchors.leftMargin: Style.space(10)
        anchors.rightMargin: Style.space(10)
        spacing: Style.space(6)

        StatLine { label: "Driver"; value: fanRow.fan ? String(fanRow.fan.chip || "") : "" }
        StatLine {
          visible: fanRow.fan && fanRow.fan.target !== null && fanRow.fan.target !== undefined
          label: "Target"
          value: fanRow.fan ? thermals.numberValue(fanRow.fan.target) + " rpm" : ""
        }
        StatLine {
          visible: fanRow.fan && thermals.numberValue(fanRow.fan.max) > 0
          label: "Maximum"
          value: fanRow.fan ? thermals.numberValue(fanRow.fan.max) + " rpm" : ""
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: fanRow.fan ? String(fanRow.fan.path || "") : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideMiddle
        }
      }
    }
  }

  // Label on the left, value on the right — one line of a rundown.
  component StatLine: Item {
    id: statLine
    property string label: ""
    property string value: ""

    width: parent ? parent.width : implicitWidth
    implicitHeight: Math.max(statLabel.implicitHeight, statValue.implicitHeight)

    Text {
      id: statLabel
      textFormat: Text.PlainText
      text: statLine.label
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
    }

    Text {
      id: statValue
      textFormat: Text.PlainText
      text: statLine.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.bold: true
      anchors.right: parent.right
      anchors.left: statLabel.right
      anchors.leftMargin: Style.space(12)
      horizontalAlignment: Text.AlignRight
      elide: Text.ElideLeft
      anchors.verticalCenter: parent.verticalCenter
    }
  }
}
