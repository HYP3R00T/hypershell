"""Add Carbon presentation IPC to an Omarchy notification plugin clone."""

import sys
from pathlib import Path


BRIDGE = """
  // Carbon borrows presentation while the corner renews its lease.
  property bool linearCarbonSelected: false
  property bool cornerBrowsing: false
  property var cornerRemoved: Object.create(null)
  readonly property bool cornerPresenting: linearCarbonSelected && (cornerLease.running || doNotDisturb) && !keyboardMode
  onDoNotDisturbChanged: if (linearCarbonSelected) cornerPulse.restart()

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
    preload: true
    printErrors: false
    watchChanges: true
    onFileChanged: reload()
    onLoaded: {
      service.linearCarbonSelected = ["carbon", "linear-carbon"].includes(text().trim())
      if (service.linearCarbonSelected) cornerPulse.restart()
      else cornerLease.stop()
    }
    onLoadFailed: {
      service.linearCarbonSelected = false
      cornerLease.stop()
    }
  }
  Timer { id: cornerLease; interval: 25000 }
  FileView {
    id: cornerSignal
    path: Quickshell.env("XDG_RUNTIME_DIR") + "/linear-carbon-notification-signal"
    atomicWrites: true
    printErrors: false
  }
  Timer {
    id: cornerPulse
    interval: 25
    onTriggered: if (service.linearCarbonSelected) cornerSignal.setText(String(Date.now()) + "\\n")
  }

  function cornerRows(browsing) {
    if (!linearCarbonSelected) return JSON.stringify({ dnd: doNotDisturb, rows: [] })
    cornerBrowsing = browsing === "1"
    cornerLease.restart()
    const rows = []
    for (let index = 0; index < toasts.count; index++) {
      const row = toasts.get(index)
      if (leaving[row.key]) continue
      rows.push({ key: row.key, ts: row.ts, app: row.app, appIcon: row.appIcon,
        summary: row.summary, body: String(row.body || "").slice(0, 4096),
        actions: service.deedsFor(row.key).slice(0, 4).map(deed =>
          deed.kind === "code" ? "Copy code" : String(deed.label || "Action")) })
    }
    return JSON.stringify({ dnd: doNotDisturb, rows })
  }
"""


def add_bridge(source: str) -> str:
    changes = [
        ("  // ------------------------------------------------------------- IPC\n", BRIDGE + "\n"),
        (
            '    function ping(): string { return "ok" }\n',
            """    function cornerSnapshot(browsing: string): string { return service.cornerRows(browsing) }
    function cornerAction(key: string, index: int): string {
      if (!service.linearCarbonSelected || service.rowIndexFor(key) < 0 || service.leaving[key]) return "none"
      if (index === -1) { service.activate(key, true); return "ok" }
      return service.runDeed(key, index) ? "ok" : "none"
    }
    function cornerDismiss(key: string): string {
      if (!service.linearCarbonSelected || !/^[A-Za-z0-9_-]{1,120}$/.test(key)) return "none"
      const active = !!service.liveKeys[key]
      if (active) {
        service.cornerRemoved[key] = true
        service.closeToast(key, "dismissed", true)
      }
      const kept = service.historyEntries.filter(row => row.key !== key)
      if (kept.length !== service.historyEntries.length) {
        service.historyEntries = kept
        service.saveSoon("history")
        return "ok"
      }
      return active ? "ok" : "none"
    }
    function cornerClearAll(): string {
      if (!service.linearCarbonSelected || !service.historyLoaded || !service.liveLoaded) return "none"
      const keys = Object.keys(service.liveKeys)
      for (const key of keys) service.cornerRemoved[key] = true
      service.clearAll("dismissed", true)
      if (service.historyEntries.length) {
        service.historyEntries = []
        service.saveSoon("history")
      }
      return "ok"
    }
""",
        ),
        ('    onCountChanged: {\n', '      if (service.linearCarbonSelected) cornerPulse.restart()\n'),
        (
            "        Store.applyTo(toasts, at, row)      // an update, in place\n",
            "        if (service.linearCarbonSelected) cornerPulse.restart()\n",
        ),
    ]
    for existing, extra in changes:
        if source.count(existing) != 1:
            raise ValueError(f"Unsupported Omarchy notification source near {existing.strip()!r}")
        source = source.replace(existing, existing + extra, 1)

    for existing, replacement in [
        (
            "    var muted = Delivery.quietReason(row, doNotDisturb)\n",
            '    var muted = linearCarbonSelected && doNotDisturb ? "silenced" : Delivery.quietReason(row, doNotDisturb)\n',
        ),
        (
            '    if (key.indexOf("placeholder") !== 0) storeClose(key, reason)\n',
            """    if (cornerRemoved[key]) {
      delete cornerRemoved[key]
      storeDrop(key)
    } else if (key.indexOf("placeholder") !== 0) storeClose(key, reason)
""",
        ),
        (
            "mask: Region { item: surface.showingNotifications ? deck : null }",
            "mask: Region { item: surface.showingNotifications && !service.cornerPresenting ? deck : null }",
        ),
        (
            "        visible: surface.showingNotifications\n",
            "        visible: surface.showingNotifications\n        opacity: service.cornerPresenting ? 0 : 1\n",
        ),
        (
            "              paused: service.expanded\n",
            "              paused: service.expanded || (service.cornerPresenting && service.cornerBrowsing)\n",
        ),
    ]:
        if source.count(existing) != 1:
            raise ValueError(f"Unsupported Omarchy notification surface near {existing.strip()!r}")
        source = source.replace(existing, replacement, 1)
    return source


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit("Usage: notification-service-bridge.py /path/to/upstream/Service.qml")
    try:
        print(add_bridge(Path(sys.argv[1]).read_text()), end="")
    except (OSError, ValueError) as error:
        sys.exit(str(error))
