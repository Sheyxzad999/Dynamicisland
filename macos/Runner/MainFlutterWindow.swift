import Cocoa
import FlutterMacOS
import IOKit.ps
import ServiceManagement

/// Notch ustida turadigan shaffof oyna.
/// Sichqoncha orol ichida bo'lmasa, oyna bosishlarni o'tkazib yuboradi.
class MainFlutterWindow: NSPanel {
  private var channel: FlutterMethodChannel!
  private let winW: CGFloat = 760
  private let winH: CGFloat = 320

  /// Flutter tomonidan xabar qilinadigan orol o'lchami.
  private var islandSize = NSSize(width: 200, height: 32)
  private var hovering = false
  private var mouseTimer: Timer?
  private var batteryTimer: Timer?
  private var mediaTimer: Timer?
  private var lastBattery: [String: Any] = [:]
  private var lastMedia: [String: Any] = [:]
  private let scriptQueue = DispatchQueue(label: "uz.dinamikorol.applescript")

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func awakeFromNib() {
    let vc = FlutterViewController()
    vc.backgroundColor = .clear
    contentViewController = vc
    RegisterGeneratedPlugins(registry: vc)

    styleMask = [.borderless, .nonactivatingPanel, .fullSizeContentView]
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    hidesOnDeactivate = false
    isFloatingPanel = true
    level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
    collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
    isMovable = false
    ignoresMouseEvents = true

    channel = FlutterMethodChannel(name: "orol/native", binaryMessenger: vc.engine.binaryMessenger)
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }

    positionWindow()
    NotificationCenter.default.addObserver(
      self, selector: #selector(screensChanged),
      name: NSApplication.didChangeScreenParametersNotification, object: nil)

    mouseTimer = Timer.scheduledTimer(withTimeInterval: 0.04, repeats: true) { [weak self] _ in
      self?.checkMouse()
    }
    batteryTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
      self?.pushBattery(force: false)
    }
    mediaTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
      self?.pollMedia()
    }

    super.awakeFromNib()
    orderFrontRegardless()
  }

  // MARK: - Ekran va notch

  private var notchScreen: NSScreen {
    NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens[0]
  }

  private func notchInfo() -> [String: Any] {
    let s = notchScreen
    var w: CGFloat = 190
    var h: CGFloat = NSStatusBar.system.thickness
    var hasNotch = false
    if s.safeAreaInsets.top > 0,
       let l = s.auxiliaryTopLeftArea, let r = s.auxiliaryTopRightArea {
      w = s.frame.width - l.width - r.width
      h = s.safeAreaInsets.top
      hasNotch = true
    }
    return ["width": Double(w), "height": Double(h), "hasNotch": hasNotch]
  }

  @objc private func screensChanged() {
    positionWindow()
    channel.invokeMethod("screen", arguments: notchInfo())
  }

  private func positionWindow() {
    let f = notchScreen.frame
    setFrame(NSRect(x: f.midX - winW / 2, y: f.maxY - winH, width: winW, height: winH), display: true)
  }

  // MARK: - Sichqoncha

  private func checkMouse() {
    let f = notchScreen.frame
    let p = NSEvent.mouseLocation
    let m: CGFloat = hovering ? 14 : 4
    let w = islandSize.width + m * 2
    let h = islandSize.height + m + (hovering ? 0 : 4)
    let rect = NSRect(x: f.midX - w / 2, y: f.maxY - h, width: w, height: h + 2)
    let inside = rect.contains(p)
    if inside != hovering {
      hovering = inside
      ignoresMouseEvents = !inside
      channel.invokeMethod("hover", arguments: inside)
    }
  }

  // MARK: - Flutter chaqiruvlari

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "getScreen":
      result(notchInfo())
    case "setIslandSize":
      let w = args["width"] as? Double ?? 200
      let h = args["height"] as? Double ?? 32
      islandSize = NSSize(width: w, height: h)
      result(nil)
    case "getBattery":
      result(batteryInfo())
    case "media":
      mediaCommand(args["command"] as? String ?? "")
      result(nil)
    case "openFile":
      if let p = args["path"] as? String { NSWorkspace.shared.open(URL(fileURLWithPath: p)) }
      result(nil)
    case "revealFile":
      if let p = args["path"] as? String {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: p)])
      }
      result(nil)
    case "fileExists":
      result(FileManager.default.fileExists(atPath: args["path"] as? String ?? ""))
    case "playSound":
      NSSound(named: NSSound.Name(args["name"] as? String ?? "Glass"))?.play()
      result(nil)
    case "getLaunchAtLogin":
      if #available(macOS 13.0, *) {
        result(SMAppService.mainApp.status == .enabled)
      } else { result(false) }
    case "setLaunchAtLogin":
      if #available(macOS 13.0, *) {
        do {
          if args["enabled"] as? Bool == true {
            try SMAppService.mainApp.register()
          } else {
            try SMAppService.mainApp.unregister()
          }
          result(SMAppService.mainApp.status == .enabled)
        } catch {
          result(FlutterError(code: "login", message: error.localizedDescription, details: nil))
        }
      } else { result(false) }
    case "quit":
      NSApp.terminate(nil)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Batareya

  private func batteryInfo() -> [String: Any] {
    guard let snap = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
          let list = IOPSCopyPowerSourcesList(snap)?.takeRetainedValue() as? [CFTypeRef]
    else { return ["available": false] }
    for ps in list {
      guard let d = IOPSGetPowerSourceDescription(snap, ps)?.takeUnretainedValue() as? [String: Any]
      else { continue }
      let cur = d[kIOPSCurrentCapacityKey] as? Int ?? 0
      let max = max(d[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
      let charging = d[kIOPSIsChargingKey] as? Bool ?? false
      let state = d[kIOPSPowerSourceStateKey] as? String ?? ""
      let toFull = d[kIOPSTimeToFullChargeKey] as? Int ?? -1
      let toEmpty = d[kIOPSTimeToEmptyKey] as? Int ?? -1
      return [
        "available": true,
        "percent": cur * 100 / max,
        "charging": charging,
        "plugged": state == kIOPSACPowerValue,
        "minutesToFull": toFull,
        "minutesToEmpty": toEmpty,
      ]
    }
    return ["available": false]
  }

  private func pushBattery(force: Bool) {
    let b = batteryInfo()
    if force || !NSDictionary(dictionary: b).isEqual(to: lastBattery) {
      lastBattery = b
      channel.invokeMethod("battery", arguments: b)
    }
  }

  // MARK: - Musiqa (Spotify va Apple Music)

  private let spotifyId = "com.spotify.client"
  private let musicId = "com.apple.Music"

  private func isRunning(_ id: String) -> Bool {
    NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == id }
  }

  private let sep = "\u{1F}"

  private func pollMedia() {
    let spotify = isRunning(spotifyId)
    let music = isRunning(musicId)
    scriptQueue.async { [weak self] in
      guard let self else { return }
      var candidates: [[String: Any]] = []
      if spotify, let s = self.readPlayer(app: "Spotify", spotify: true) { candidates.append(s) }
      if music, let s = self.readPlayer(app: "Music", spotify: false) { candidates.append(s) }
      let info = candidates.first(where: { $0["state"] as? String == "playing" })
        ?? candidates.first
        ?? ["state": "none"]
      DispatchQueue.main.async {
        if !NSDictionary(dictionary: info).isEqual(to: self.lastMedia) {
          self.lastMedia = info
          self.channel.invokeMethod("media", arguments: info)
        }
      }
    }
  }

  private func readPlayer(app: String, spotify: Bool) -> [String: Any]? {
    let art = spotify ? "artwork url of t" : "\"\""
    let dur = spotify ? "((duration of t) / 1000)" : "(duration of t)"
    let src = """
    tell application "\(app)"
      set s to player state as string
      if s is "stopped" then return "stopped"
      set t to current track
      set d to ASCII character 31
      return s & d & (name of t) & d & (artist of t) & d & \(art) & d & ((player position) as string) & d & (\(dur) as string)
    end tell
    """
    guard let script = NSAppleScript(source: src) else { return nil }
    var err: NSDictionary?
    let out = script.executeAndReturnError(&err)
    if err != nil { return nil }
    let text = out.stringValue ?? ""
    if text == "stopped" || text.isEmpty { return nil }
    let parts = text.components(separatedBy: sep)
    guard parts.count >= 6 else { return nil }
    func num(_ s: String) -> Double { Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
    return [
      "state": parts[0],
      "title": parts[1],
      "artist": parts[2],
      "artwork": parts[3],
      "position": num(parts[4]),
      "duration": num(parts[5]),
      "source": spotify ? "Spotify" : "Music",
    ]
  }

  private func mediaCommand(_ cmd: String) {
    let verb: String
    switch cmd {
    case "playpause": verb = "playpause"
    case "next": verb = "next track"
    case "previous": verb = "previous track"
    default: return
    }
    let source = lastMedia["source"] as? String
    let app: String? = source == "Spotify" ? "Spotify" : (source == "Music" ? "Music" : nil)
    guard let app else { return }
    scriptQueue.async { [weak self] in
      var err: NSDictionary?
      NSAppleScript(source: "tell application \"\(app)\" to \(verb)")?.executeAndReturnError(&err)
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.pollMedia() }
    }
  }
}
