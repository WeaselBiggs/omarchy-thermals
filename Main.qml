import QtQuick
import Quickshell
import Quickshell.Io

// The data side of Thermals. bin/collect walks /sys/class/hwmon and streams one
// JSON record per tick; this file keeps that process alive, parses what it
// prints, and answers the questions the panel asks (which probe is hottest,
// what goes in the bar, how warm is "warm"). Nothing here touches the screen.
Item {
  id: root
  visible: false

  property var settings: ({})

  // The collector ships inside the plugin folder so a git checkout is the whole install.
  readonly property string collectorPath: String(Qt.resolvedUrl("bin/collect")).replace(/^file:\/\//, "")

  // ---------------------------------------------------------------- settings

  readonly property int refreshIntervalSec: Math.max(1, numberValue(setting("refreshIntervalSec", 3)))
  readonly property bool showAll: setting("showAll", false) === true
  readonly property bool fahrenheit: String(setting("unit", "°C")).toUpperCase().indexOf("F") >= 0
  readonly property string barSensor: String(setting("barSensor", "CPU"))
  readonly property int warnAt: numberValue(setting("warnAt", 0))
  readonly property int hotAt: numberValue(setting("hotAt", 0))

  // ---------------------------------------------------------------- record

  property var record: null
  property string collectorError: ""

  readonly property var sensors: record && Array.isArray(record.sensors) ? record.sensors : []
  readonly property var fans: record && Array.isArray(record.fans) ? record.fans : []
  readonly property int hidden: record ? numberValue(record.hidden) : 0
  readonly property double updatedAtMs: record ? Number(record.updatedAtMs || 0) : 0
  readonly property bool ready: record !== null

  readonly property var hottest: {
    var best = null
    for (var i = 0; i < sensors.length; i++)
      if (!best || Number(sensors[i].c) > Number(best.c)) best = sensors[i]
    return best
  }

  // The reading beside the bar icon. A kind that this machine does not have
  // (a desktop without a battery, a NAS without a GPU) falls back to the
  // hottest probe rather than leaving the bar blank.
  readonly property var primary: {
    var want = barSensor.toLowerCase()
    var group = want === "cpu" ? "cpu" : want === "gpu" ? "gpu" : want === "storage" ? "storage" : ""
    if (group !== "")
      for (var i = 0; i < sensors.length; i++)
        if (sensors[i].group === group) return sensors[i]
    return hottest
  }

  readonly property int maxLevel: {
    var level = 0
    for (var i = 0; i < sensors.length; i++) level = Math.max(level, levelOf(sensors[i]))
    return level
  }

  // Sensors folded into their groups, in the collector's order, for the panel
  // to draw one section per group.
  readonly property var groups: {
    var out = []
    var byKey = {}
    for (var i = 0; i < sensors.length; i++) {
      var s = sensors[i]
      var key = String(s.group || "other")
      if (!byKey[key]) {
        byKey[key] = { key: key, title: String(s.groupTitle || key), sensors: [] }
        out.push(byKey[key])
      }
      byKey[key].sensors.push(s)
    }
    return out
  }

  function parse(line) {
    var text = String(line || "").trim()
    if (text === "") return
    try {
      var parsed = JSON.parse(text)
      if (parsed && typeof parsed === "object") {
        root.record = parsed
        root.collectorError = ""
      }
    } catch (e) {
      console.warn("thermals", "Ignoring bad record from collector", e)
    }
  }

  // --------------------------------------------------------------- collector

  readonly property var collectorCommand: {
    var command = [collectorPath, "--watch", String(refreshIntervalSec)]
    if (showAll) command.push("--all")
    return command
  }

  // A changed command only takes effect on a fresh process.
  onCollectorCommandChanged: restart()

  Process {
    id: collector
    command: root.collectorCommand
    running: true

    stdout: SplitParser {
      onRead: function(data) { root.parse(data) }
    }

    stderr: SplitParser {
      onRead: function(data) {
        var message = String(data || "").trim()
        if (message !== "") {
          console.warn("thermals", message)
          root.collectorError = message
        }
      }
    }

    // The collector only stops when told to or when something is badly wrong
    // (python missing, hwmon unreadable). Either way, come back in a moment;
    // a deliberate restart has already set running again by then.
    onExited: function(exitCode, exitStatus) {
      if (exitCode !== 0 && root.collectorError === "")
        root.collectorError = "Collector exited with status " + exitCode
      if (!collector.running) restartTimer.restart()
    }
  }

  Timer {
    id: restartTimer
    interval: 2000
    repeat: false
    onTriggered: if (!collector.running) collector.running = true
  }

  function restart() {
    collector.running = false
    Qt.callLater(function() { collector.running = true })
  }

  function refresh() { restart() }

  // ---------------------------------------------------------------- readings

  // 0 = fine, 1 = warm, 2 = hot. Thresholds come from the driver when it
  // publishes them, otherwise from a per-kind default, unless the settings
  // force one number for everything.
  function warnOf(sensor) { return warnAt > 0 ? warnAt : Number(sensor && sensor.warn || 85) }
  function hotOf(sensor) { return hotAt > 0 ? hotAt : Number(sensor && sensor.hot || 95) }

  function levelOf(sensor) {
    if (!sensor) return 0
    var c = Number(sensor.c)
    if (c >= hotOf(sensor)) return 2
    if (c >= warnOf(sensor)) return 1
    return 0
  }

  // How far up its own scale a probe sits: the meter fills at "hot".
  function ratioOf(sensor) {
    if (!sensor) return 0
    var hot = hotOf(sensor)
    return hot > 0 ? Math.max(0, Math.min(1, Number(sensor.c) / hot)) : 0
  }

  function toDisplay(celsius) {
    var c = Number(celsius)
    return fahrenheit ? c * 9 / 5 + 32 : c
  }

  // "39°" for the bar and rows, "39°C" where the unit is worth stating.
  function formatTemp(celsius, withUnit) {
    var value = Number(celsius)
    if (!isFinite(value)) return "—"
    var text = String(Math.round(toDisplay(value))) + "°"
    return withUnit ? text + (fahrenheit ? "F" : "C") : text
  }

  function formatRpm(fan) {
    if (!fan) return ""
    if (fan.fault === true) return "fault"
    var rpm = numberValue(fan.rpm)
    return rpm <= 0 ? "off" : rpm + " rpm"
  }

  // "Fan off", "Fan 2400 rpm", "Fans 2400 · 2100 rpm" — or nothing on a
  // machine with no tachometer.
  function fanSummary() {
    if (fans.length === 0) return ""
    var spinning = []
    for (var i = 0; i < fans.length; i++) {
      var rpm = numberValue(fans[i].rpm)
      if (fans[i].fault === true) return fans.length === 1 ? "Fan fault" : "Fan fault"
      if (rpm > 0) spinning.push(String(rpm))
    }
    if (spinning.length === 0) return fans.length === 1 ? "Fan off" : "Fans off"
    return (fans.length === 1 ? "Fan " : "Fans ") + spinning.join(" · ") + " rpm"
  }

  // One line for the bar tooltip and the IPC `temps` call.
  function summary() {
    var parts = []
    for (var i = 0; i < sensors.length && parts.length < 4; i++) {
      var s = sensors[i]
      // First probe of each group only: the summary is a glance, not a list.
      if (i > 0 && sensors[i - 1].group === s.group) continue
      parts.push(String(s.label) + " " + formatTemp(s.c, false))
    }
    var fan = fanSummary()
    if (fan !== "") parts.push(fan)
    return parts.join(" · ")
  }

  // ---------------------------------------------------------------- helpers

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function numberValue(value) {
    var n = Number(value || 0)
    return isFinite(n) ? Math.round(n) : 0
  }

  function formatAgo(ms, nowMs) {
    if (!(ms > 0)) return ""
    var seconds = Math.max(0, Math.floor((nowMs - ms) / 1000))
    if (seconds < 2) return "just now"
    if (seconds < 60) return seconds + "s ago"
    var minutes = Math.floor(seconds / 60)
    if (minutes < 60) return minutes + "m ago"
    return Math.floor(minutes / 60) + "h ago"
  }
}
