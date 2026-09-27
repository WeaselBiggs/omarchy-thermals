# Thermals

System temperatures in the Omarchy bar. One thermometer with a reading beside
it, and a panel listing every temperature probe and fan the kernel exposes,
grouped by what they measure. Nothing is polled through `lm_sensors`; the
collector reads `/sys/class/hwmon` directly, so it works on a bare install
without root.

`Panel.qml` owns the bar button and the popup, `Main.qml` keeps the collector
running and answers the panel's questions, `bin/collect` does the reading.

## Install

```bash
omarchy plugin add https://github.com/WeaselBiggs/omarchy-thermals.git --enable
omarchy bar move dan.thermals --after omarchy.weather
```

Or drop the folder into `~/.config/omarchy/plugins/dan.thermals/` and run
`omarchy plugin enable dan.thermals`. Needs `python3`, which Omarchy ships.

## Bar

The thermometer shows the CPU temperature by default (`barSensor` picks GPU,
storage or the hottest probe instead). It switches to the "high" thermometer
glyph when any probe is warm and turns urgent when one is hot. Hover for a
one-line summary. Left = panel, right = `btop`, middle = restart the collector.

## Panel

- **Hero** — the chosen reading as a pill, then which probe it is, the
  hottest probe when that is a different one, and the fan state.
- **One section per group** — Processor, Graphics, Storage, Memory, Wireless,
  Board, Power, Other. Each row has a meter behind it that fills as the probe
  approaches its hot threshold; warm rows go bold, hot rows go urgent. Hover
  for the driver, raw label and thresholds. Click (or Enter) unfolds where the
  number comes from, including the sysfs path.
- **Fans** — speed in rpm, "off" at zero, "fault" when the driver flags one.
- **Footer** — probe count, how many duplicate readings are hidden, and when
  the last record arrived.

Keys: `j`/`k` move, Enter or Space unfold, `l`/`h` unfold/fold, `r` restart
the collector, `b` open btop, Tab moves to the neighbouring bar panel, Esc
closes.

IPC: `omarchy-shell dan.thermals <open|close|toggle|refresh|temps>`. `temps`
prints the summary line, which makes a notification keybinding a one-liner:

```bash
omarchy-notification-send "$(omarchy-shell dan.thermals temps)"
```

## Data

`bin/collect --watch 3` walks every `hwmon*` directory, reads `temp*_input`
and `fan*_input` with their labels and limits, and prints one JSON record per
line. The panel keeps it running rather than forking a process per tick.
`bin/collect --pretty` on its own prints one record and exits, which is the
quickest way to see what a machine exposes.

Rows are labelled from the driver name and the raw label: `k10temp` Tctl is
"CPU", `amdgpu` edge is "GPU", an NVMe's Composite reading is "NVMe" (with the
drive model in the tooltip), `spd5118` DIMMs become "RAM A" and "RAM B", the
Framework/Chromebook embedded controller's probes carry an "(EC)" suffix.
Anything unrecognised keeps its raw name under Other.

Thresholds: the driver's `max` is "warm" and `crit` is "hot" when it publishes
them (garbage values, such as an NVMe's 65261 °C, are ignored). Drivers that
publish nothing — `k10temp` and `amdgpu` among them — get a default per kind:
85/95 for a CPU, 90/100 for a GPU, 70/80 for storage, 60/80 for memory. Set
`warnAt` and `hotAt` to override every probe with one number each.

Hidden by default, shown with `showAll`: ACPI thermal zones (they repeat the
EC's probes), per-core CPU readings, an NVMe's individual sensors, and the
`acpi_fan` tachometer when another driver reads the same fan directly.

## Settings

Settings live on the widget's entry in `~/.config/omarchy/shell.json` and can
be set with `omarchy bar set dan.thermals <key> <value>` (numbers and booleans
need `--json`):

| Key | Default | What it does |
|---|---|---|
| `refreshIntervalSec` | `3` | Seconds between readings |
| `barSensor` | `"CPU"` | `"CPU"`, `"GPU"`, `"Storage"` or `"Hottest"`; falls back to the hottest probe when the kind is absent |
| `unit` | `"°C"` | Or `"°F"` |
| `showLabel` | `true` | Show the temperature next to the icon |
| `showAll` | `false` | List every probe, duplicates included |
| `warnAt` | `0` | Warm threshold in °C for every probe; 0 keeps each probe's own |
| `hotAt` | `0` | Hot threshold in °C for every probe; 0 keeps each probe's own |

## Files

```
manifest.json   plugin manifest
Panel.qml       bar button + popup
Main.qml        collector runner, record parser, threshold logic
bin/collect     python3, standard library only
```

Saving a file here logs "Local plugin changed, reloading", but QML edits only
take effect after `omarchy restart shell` on Quickshell builds without
`Qt.clearComponentCache`. The collector picks up edits when it is restarted
(middle-click the icon, or `r` in the panel).
