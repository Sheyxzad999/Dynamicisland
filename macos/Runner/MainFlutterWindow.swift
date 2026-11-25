import Cocoa
import Network
import ApplicationServices
import FlutterMacOS
import CoreAudio
import CoreMediaIO
import EventKit
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
  private var clipTimer: Timer?
  private var privacyTimer: Timer?
  private var lastChangeCount = NSPasteboard.general.changeCount
  private var lastPrivacy: [String: Bool] = [:]
  private let eventStore = EKEventStore()
  private var agentServer: AgentServer?
  private var glassView: NSView?
  private var glassVisible = false

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
    installGlass()
    agentServer = AgentServer { [weak self] payload in
      self?.channel.invokeMethod("agentEvent", arguments: payload)
    }
    agentServer?.start()
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

    clipTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
      self?.checkClipboard()
    }
    privacyTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
      self?.checkPrivacy()
    }
    NotificationCenter.default.addObserver(
      forName: .EKEventStoreChanged, object: eventStore, queue: .main
    ) { [weak self] _ in self?.channel.invokeMethod("calendarChanged", arguments: nil) }

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
      channel.invokeMethod("hover", arguments: inside)
    }
    // Menyu qatori (notch'dan chap va o'ngdagi tasma) doim bosiladigan bo'lib qolsin:
    // orol ochiq bo'lsa ham u yerdagi bosishlar orqadagi menyuga o'tadi.
    let info = notchInfo()
    let nw = CGFloat(info["width"] as? Double ?? 190)
    let nh = CGFloat(info["height"] as? Double ?? 32)
    let inMenuBar = p.y > f.maxY - nh && abs(p.x - f.midX) > nw / 2
    let ignore = !inside || inMenuBar
    if ignoresMouseEvents != ignore { ignoresMouseEvents = ignore }
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
    case "setGlass":
      updateGlass(
        width: CGFloat(args["width"] as? Double ?? 0),
        height: CGFloat(args["height"] as? Double ?? 0),
        radius: CGFloat(args["radius"] as? Double ?? 0),
        visible: args["visible"] as? Bool ?? false)
      result(nil)
    case "glassSupported":
      result(GlassFactory.liquidGlassAvailable)
    case "activateTerminal":
      activateTerminal(args["term"] as? String ?? "")
      result(nil)
    case "mediaKeysAllowed":
      result(AXIsProcessTrusted())
    case "requestMediaKeys":
      requestAccessibility()
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
    case "copyText":
      let pb = NSPasteboard.general
      pb.clearContents()
      pb.setString(args["text"] as? String ?? "", forType: .string)
      lastChangeCount = pb.changeCount
      result(nil)
    case "focusKeyboard":
      makeKey()
      result(nil)
    case "releaseKeyboard":
      if isKeyWindow {
        resignKey()
        NSWorkspace.shared.frontmostApplication?.activate()
      }
      result(nil)
    case "action":
      quickAction(args["name"] as? String ?? "")
      result(nil)
    case "calendarStatus":
      result(calendarStatus())
    case "requestCalendar":
      requestCalendar { granted in result(granted) }
    case "getEvents":
      result(upcomingEvents())
    case "openCalendar":
      NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Calendar.app"))
      result(nil)
    case "quit":
      NSApp.terminate(nil)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Liquid Glass

  /// Shisha qatlami Flutter ko'rinishining ortiga, oyna ramkasiga qo'yiladi.
  /// Flutter'ning o'zi (va uning sichqoncha hodisalari) o'zgarishsiz qoladi.
  private func installGlass() {
    guard glassView == nil, let content = contentView, let frameView = content.superview else { return }
    let g = GlassFactory.makeGlass()
    g.alphaValue = 0
    g.frame = .zero
    frameView.addSubview(g, positioned: .below, relativeTo: content)
    glassView = g
  }

  /// Shisha qatlamini orolning hozirgi (animatsiyadagi) shakliga moslaydi.
  private func updateGlass(width: CGFloat, height: CGFloat, radius: CGFloat, visible: Bool) {
    guard let g = glassView, let host = g.superview else { return }
    let b = host.bounds
    // Yuqori qirra oyna chegarasidan radius qadar tashqariga chiqadi —
    // shunda faqat pastki burchaklar yumaloq ko'rinadi (notch'ga yopishgan shakl).
    g.frame = NSRect(x: ((b.width - width) / 2).rounded(), y: b.height - height,
                     width: width.rounded(), height: height + radius)
    GlassFactory.setCornerRadius(g, radius)
    if visible != glassVisible {
      glassVisible = visible
      NSAnimationContext.runAnimationGroup { ctx in
        ctx.duration = visible ? 0.18 : 0.28
        g.animator().alphaValue = visible ? 1 : 0
      }
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

  // Brauzerlar: ichidagi <video>/<audio> va Media Session maʼlumoti JavaScript orqali o'qiladi.
  // Buning uchun brauzerda bir marta "Allow JavaScript from Apple Events" yoqiladi.
  private struct Browser { let id: String; let name: String; let safari: Bool }
  private let browsers = [
    Browser(id: "com.apple.Safari", name: "Safari", safari: true),
    Browser(id: "com.google.Chrome", name: "Google Chrome", safari: false),
    Browser(id: "com.brave.Browser", name: "Brave Browser", safari: false),
    Browser(id: "com.microsoft.edgemac", name: "Microsoft Edge", safari: false),
  ]
  private var lastBrowserPoll = Date.distantPast
  private var lastBrowserInfo: [String: Any]?   // faqat scriptQueue'da
  private var jsBlocked = Set<String>()          // faqat scriptQueue'da

  /// Sahifadagi ijro etilayotgan (yoki to'xtatilgan) media haqida JSON qaytaradi.
  private let mediaJS = """
  (function(){var ms=[].slice.call(document.querySelectorAll('video,audio'));var m=null,i;\
  for(i=0;i<ms.length;i++){if(!ms[i].paused&&!ms[i].ended&&ms[i].currentTime>0){m=ms[i];break}}\
  if(!m){for(i=0;i<ms.length;i++){if(ms[i].currentTime>0&&!ms[i].ended&&ms[i].duration>0){m=ms[i];break}}}\
  if(!m)return '';var md=navigator.mediaSession&&navigator.mediaSession.metadata;var art='';\
  if(md&&md.artwork&&md.artwork.length){art=md.artwork[md.artwork.length-1].src}\
  return JSON.stringify({t:(md&&md.title)||document.title,a:(md&&md.artist)||location.hostname.replace(/^www\\./,''),\
  art:art,p:m.currentTime,d:isFinite(m.duration)?m.duration:0,s:m.paused?'paused':'playing',h:location.hostname})})()
  """

  private let toggleJS = """
  (function(){var ms=[].slice.call(document.querySelectorAll('video,audio'));\
  for(var i=0;i<ms.length;i++){var m=ms[i];if(m.currentTime>0&&!m.ended){if(m.paused){m.play()}else{m.pause()}return 'ok'}}return ''})()
  """

  private func pollMedia() {
    let spotify = isRunning(spotifyId)
    let music = isRunning(musicId)
    let running = browsers.filter { isRunning($0.id) }
    let pollBrowsers = Date().timeIntervalSince(lastBrowserPoll) > 2.5
    if pollBrowsers { lastBrowserPoll = Date() }
    scriptQueue.async { [weak self] in
      guard let self else { return }
      var candidates: [[String: Any]] = []
      if spotify, let s = self.readPlayer(app: "Spotify", spotify: true) { candidates.append(s) }
      if music, let s = self.readPlayer(app: "Music", spotify: false) { candidates.append(s) }
      let nativePlaying = candidates.contains { $0["state"] as? String == "playing" }
      if !nativePlaying {
        if pollBrowsers {
          var found: [String: Any]?
          for b in running {
            if let i = self.readBrowser(b) {
              found = i
              if i["state"] as? String == "playing" { break }
            }
          }
          self.lastBrowserInfo = found
        }
        if let b = self.lastBrowserInfo { candidates.append(b) }
      }
      var info = candidates.first(where: { $0["state"] as? String == "playing" })
        ?? candidates.first
        ?? ["state": "none"]
      let blocked = self.jsBlocked.intersection(running.map(\.name))
      if info["state"] as? String == "none", !blocked.isEmpty {
        info["blocked"] = blocked.sorted().joined(separator: ", ")
      }
      DispatchQueue.main.async {
        if !NSDictionary(dictionary: info).isEqual(to: self.lastMedia) {
          self.lastMedia = info
          self.channel.invokeMethod("media", arguments: info)
        }
      }
    }
  }

  /// Brauzerning barcha varaqlarida JavaScript bajaradi va birinchi bo'sh bo'lmagan natijani qaytaradi.
  private func runInTabs(_ b: Browser, _ js: String) -> String? {
    let escaped = js.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    let run = b.safari ? "do JavaScript \"\(escaped)\" in t" : "execute t javascript \"\(escaped)\""
    let src = """
    tell application "\(b.name)"
      repeat with w in windows
        repeat with t in tabs of w
          try
            set r to \(run)
            if r is not missing value and r is not "" then return r
          on error e
            -- Bitta tab (PDF, sozlamalar sahifasi) xato bersa, qolganlari tekshirilaveradi
            if e contains "Apple Events" then return "__JSBLOCKED__"
          end try
        end repeat
      end repeat
      return ""
    end tell
    """
    var err: NSDictionary?
    let out = NSAppleScript(source: src)?.executeAndReturnError(&err)
    if let err {
      let msg = (err[NSAppleScript.errorMessage] as? String) ?? ""
      if msg.localizedCaseInsensitiveContains("JavaScript") { jsBlocked.insert(b.name) }
      return nil
    }
    let text = out?.stringValue ?? ""
    if text == "__JSBLOCKED__" {
      jsBlocked.insert(b.name)
      return nil
    }
    jsBlocked.remove(b.name)
    return text.isEmpty ? nil : text
  }

  private func readBrowser(_ b: Browser) -> [String: Any]? {
    guard let text = runInTabs(b, mediaJS),
          let data = text.data(using: .utf8),
          let j = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    let host = (j["h"] as? String ?? "").replacingOccurrences(of: "www.", with: "")
    return [
      "state": j["s"] as? String ?? "playing",
      "title": j["t"] as? String ?? "",
      "artist": j["a"] as? String ?? host,
      "artwork": j["art"] as? String ?? "",
      "position": (j["p"] as? NSNumber)?.doubleValue ?? 0,
      "duration": (j["d"] as? NSNumber)?.doubleValue ?? 0,
      "source": b.name,
      "site": host,
    ]
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
    let source = lastMedia["source"] as? String
    // 1) Spotify / Music — AppleScript
    if source == "Spotify" || source == "Music" {
      let verb = cmd == "next" ? "next track" : (cmd == "previous" ? "previous track" : "playpause")
      let app = source!
      scriptQueue.async { [weak self] in
        var err: NSDictionary?
        NSAppleScript(source: "tell application \"\(app)\" to \(verb)")?.executeAndReturnError(&err)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self?.pollMedia() }
      }
      return
    }
    // 2) Brauzer — ⏯ to'g'ridan-to'g'ri sahifada (ruxsatsiz ham ishlaydi)
    if cmd == "playpause", let b = browsers.first(where: { $0.name == source }) {
      scriptQueue.async { [weak self] in
        guard let self else { return }
        let ok = self.runInTabs(b, self.toggleJS) != nil
        DispatchQueue.main.async {
          if !ok { self.postMediaKey(cmd) }
          self.lastBrowserPoll = .distantPast
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.pollMedia() }
        }
      }
      return
    }
    // 3) Istalgan boshqa ilova — tizim media tugmalari
    postMediaKey(cmd)
    lastBrowserPoll = .distantPast
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in self?.pollMedia() }
  }

  /// Klaviaturadagi ⏯ ⏮ ⏭ tugmalarini taqlid qiladi — hozir ovoz chiqarayotgan
  /// istalgan ilovani boshqaradi. Accessibility ruxsati talab qilinadi.
  private func postMediaKey(_ cmd: String) {
    guard AXIsProcessTrusted() else {
      requestAccessibility()
      return
    }
    let key: Int = cmd == "next" ? 17 : (cmd == "previous" ? 18 : 16)  // NX_KEYTYPE_*
    for down in [true, false] {
      let flags = down ? 0xA00 : 0xB00
      let ev = NSEvent.otherEvent(
        with: .systemDefined, location: .zero,
        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(flags)),
        timestamp: 0, windowNumber: 0, context: nil,
        subtype: 8, data1: (key << 16) | flags, data2: -1)
      ev?.cgEvent?.post(tap: .cghidEventTap)
    }
  }

  /// TERM_PROGRAM qiymati bo'yicha agent ishlayotgan terminalni oldinga chiqaradi.
  private func activateTerminal(_ term: String) {
    let map: [String: [String]] = [
      "Apple_Terminal": ["com.apple.Terminal"],
      "iTerm.app": ["com.googlecode.iterm2"],
      "WarpTerminal": ["dev.warp.Warp-Stable", "dev.warp.Warp"],
      "ghostty": ["com.mitchellh.ghostty"],
      "vscode": ["com.microsoft.VSCode", "com.todesktop.230313mzl4w4u92", "com.exafunction.windsurf"],
      "WezTerm": ["com.github.wez.wezterm"],
      "Hyper": ["co.zeit.hyper"],
      "kitty": ["net.kovidgoyal.kitty"],
      "Alacritty": ["org.alacritty"],
    ]
    let ids = (map[term] ?? []) + ["com.apple.Terminal"]
    for id in ids {
      if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
        app.activate()
        return
      }
    }
  }

  private func requestAccessibility() {
    let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
    if !AXIsProcessTrustedWithOptions(opts),
       let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
      NSWorkspace.shared.open(url)
    }
  }

  // MARK: - Nusxalar tarixi

  private func checkClipboard() {
    let pb = NSPasteboard.general
    guard pb.changeCount != lastChangeCount else { return }
    lastChangeCount = pb.changeCount
    let types = pb.types?.map { $0.rawValue } ?? []
    // Parol menejerlari maxfiy matnni shu belgilar bilan nusxalaydi
    if types.contains("org.nspasteboard.ConcealedType") || types.contains("org.nspasteboard.TransientType") {
      return
    }
    guard let text = pb.string(forType: .string),
          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
    let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? ""
    channel.invokeMethod("clipboard", arguments: ["text": String(text.prefix(20000)), "app": app])
  }

  // MARK: - Mikrofon va kamera

  private func isMicInUse() -> Bool {
    var dev = AudioDeviceID(0)
    var size = UInt32(MemoryLayout<AudioDeviceID>.size)
    var addr = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyDefaultInputDevice,
      mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &dev) == noErr,
          dev != 0 else { return false }
    var running: UInt32 = 0
    size = UInt32(MemoryLayout<UInt32>.size)
    addr.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere
    guard AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &running) == noErr else { return false }
    return running != 0
  }

  private func isCameraInUse() -> Bool {
    var addr = CMIOObjectPropertyAddress(
      mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
      mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
      mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
    var dataSize: UInt32 = 0
    let sys = CMIOObjectID(kCMIOObjectSystemObject)
    guard CMIOObjectGetPropertyDataSize(sys, &addr, 0, nil, &dataSize) == 0, dataSize > 0 else { return false }
    var devices = [CMIOObjectID](repeating: 0, count: Int(dataSize) / MemoryLayout<CMIOObjectID>.size)
    var used: UInt32 = 0
    guard CMIOObjectGetPropertyData(sys, &addr, 0, nil, dataSize, &used, &devices) == 0 else { return false }
    for d in devices {
      var a = CMIOObjectPropertyAddress(
        mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
        mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
        mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
      var running: UInt32 = 0
      var u: UInt32 = 0
      if CMIOObjectGetPropertyData(d, &a, 0, nil, UInt32(MemoryLayout<UInt32>.size), &u, &running) == 0,
         running != 0 { return true }
    }
    return false
  }

  private func checkPrivacy() {
    let p = ["mic": isMicInUse(), "camera": isCameraInUse()]
    if p != lastPrivacy {
      lastPrivacy = p
      channel.invokeMethod("privacy", arguments: p)
    }
  }

  // MARK: - Tezkor amallar

  private func run(_ path: String, _ args: [String]) {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: path)
    p.arguments = args
    try? p.run()
  }

  private func quickAction(_ name: String) {
    switch name {
    case "lock":
      if let h = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
         let sym = dlsym(h, "SACLockScreenImmediate") {
        typealias Lock = @convention(c) () -> Int32
        _ = unsafeBitCast(sym, to: Lock.self)()
      } else {
        run("/usr/bin/pmset", ["displaysleepnow"])
      }
    case "display":
      run("/usr/bin/pmset", ["displaysleepnow"])
    case "sleep":
      run("/usr/bin/pmset", ["sleepnow"])
    case "screenshot":
      NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Screenshot.app"))
    default:
      break
    }
  }

  // MARK: - Kalendar

  private func calendarStatus() -> String {
    let s = EKEventStore.authorizationStatus(for: .event)
    switch s {
    case .notDetermined: return "notDetermined"
    case .denied, .restricted: return "denied"
    default:
      if #available(macOS 14.0, *), s == .writeOnly { return "denied" }
      return "granted"
    }
  }

  private func requestCalendar(_ done: @escaping (Bool) -> Void) {
    let finish: (Bool, Error?) -> Void = { granted, _ in DispatchQueue.main.async { done(granted) } }
    if #available(macOS 14.0, *) {
      eventStore.requestFullAccessToEvents(completion: finish)
    } else {
      eventStore.requestAccess(to: .event, completion: finish)
    }
  }

  private func upcomingEvents() -> [[String: Any]] {
    guard calendarStatus() == "granted" else { return [] }
    let cal = Calendar.current
    let start = cal.startOfDay(for: Date())
    let end = cal.date(byAdding: .day, value: 3, to: start)!
    let pred = eventStore.predicateForEvents(withStart: start, end: end, calendars: nil)
    return eventStore.events(matching: pred)
      .sorted { $0.startDate < $1.startDate }
      .prefix(40)
      .map { e in
        let c = e.calendar.color.usingColorSpace(.sRGB) ?? .systemBlue
        let hex = String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
        return [
          "title": e.title ?? "",
          "start": e.startDate.timeIntervalSince1970 * 1000,
          "end": e.endDate.timeIntervalSince1970 * 1000,
          "allDay": e.isAllDay,
          "location": e.location ?? "",
          "color": hex,
        ]
      }
  }
}


// MARK: - Liquid Glass yordamchilari

enum GlassFactory {
  /// Apple Liquid Glass (macOS 26+) mavjudmi
  static var liquidGlassAvailable: Bool {
    #if compiler(>=6.2)
    if #available(macOS 26.0, *) { return true }
    #endif
    return false
  }

  static func makeGlass() -> NSView {
    #if compiler(>=6.2)
    if #available(macOS 26.0, *) {
      let g = PassthroughGlassView()
      g.style = .regular
      g.cornerRadius = 28
      // Oq matn har qanday fon ustida o'qilishi uchun shisha biroz qoraytiriladi
      g.tintColor = NSColor.black.withAlphaComponent(0.22)
      // macOS 27+: shisha sichqoncha bosishlarini o'ziga olmasin —
      // aks holda Flutter tugmalari bosilmaydi (faqat dekor qatlam).
      let sel = NSSelectorFromString("setEffectIsInteractive:")
      if g.responds(to: sel) { g.setValue(false, forKey: "effectIsInteractive") }
      return g
    }
    #endif
    let v = PassthroughEffectView()
    v.material = .hudWindow
    v.blendingMode = .behindWindow
    v.state = .active
    v.appearance = NSAppearance(named: .darkAqua)
    v.wantsLayer = true
    v.layer?.cornerRadius = 28
    v.layer?.masksToBounds = true
    return v
  }

  static func setCornerRadius(_ v: NSView, _ r: CGFloat) {
    #if compiler(>=6.2)
    if #available(macOS 26.0, *), let g = v as? NSGlassEffectView {
      if g.cornerRadius != r { g.cornerRadius = r }
      return
    }
    #endif
    if v.layer?.cornerRadius != r { v.layer?.cornerRadius = r }
  }
}

// MARK: - Sichqoncha uchun "ko'rinmas" shisha

/// Shisha faqat bezak: hech qachon sichqoncha hodisasini qabul qilmaydi,
/// aks holda Flutter tugmalari bosilmay qoladi.
#if compiler(>=6.2)
@available(macOS 26.0, *)
final class PassthroughGlassView: NSGlassEffectView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
}
#endif

final class PassthroughEffectView: NSVisualEffectView {
  override func hitTest(_ point: NSPoint) -> NSView? { nil }
  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }
}

// MARK: - AI agentlar uchun mahalliy server

/// Faqat 127.0.0.1 da tinglaydi. Claude Code / Codex hook'lari bu yerga
/// `POST /event` (JSON) yuboradi, server uni Flutter'ga uzatadi.
final class AgentServer {
  static let port: UInt16 = 47811
  private var listener: NWListener?
  private let onEvent: (String) -> Void
  private let queue = DispatchQueue(label: "uz.dinamikorol.agents")

  init(onEvent: @escaping (String) -> Void) { self.onEvent = onEvent }

  func start() {
    let params = NWParameters.tcp
    params.requiredLocalEndpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
    params.allowLocalEndpointReuse = true
    guard let l = try? NWListener(using: params) else { return }
    l.newConnectionHandler = { [weak self] c in self?.handle(c) }
    l.start(queue: queue)
    listener = l
  }

  private func handle(_ c: NWConnection) {
    c.start(queue: queue)
    receive(c, buffer: Data())
  }

  private func receive(_ c: NWConnection, buffer: Data) {
    c.receive(minimumIncompleteLength: 1, maximumLength: 256 * 1024) { [weak self] data, _, done, err in
      guard let self else { return }
      var buf = buffer
      if let data { buf.append(data) }
      if let req = Self.parse(buf) {
        let ok = req.method == "POST" && req.path.hasPrefix("/event")
        if ok, let body = String(data: req.body, encoding: .utf8) {
          let tagged = "{\"source\":\"\(req.query)\",\"term\":\"\(req.term)\",\"payload\":\(body.isEmpty ? "{}" : body)}"
          DispatchQueue.main.async { self.onEvent(tagged) }
        }
        let status = ok ? "204 No Content" : "404 Not Found"
        let resp = "HTTP/1.1 \(status)\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        c.send(content: resp.data(using: .utf8), completion: .contentProcessed { _ in c.cancel() })
        return
      }
      if done || err != nil || buf.count > 1_000_000 { c.cancel(); return }
      self.receive(c, buffer: buf)
    }
  }

  private struct Request { let method: String; let path: String; let query: String; let term: String; let body: Data }

  /// Oddiy HTTP/1.1 tahlili: sarlavhalar + Content-Length bo'yicha tana.
  private static func parse(_ data: Data) -> Request? {
    guard let sep = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
    let head = String(decoding: data[..<sep.lowerBound], as: UTF8.self)
    let lines = head.components(separatedBy: "\r\n")
    let first = lines.first?.split(separator: " ") ?? []
    guard first.count >= 2 else { return nil }
    var length = 0
    var term = ""
    for l in lines.dropFirst() {
      let kv = l.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
      guard kv.count == 2 else { continue }
      if kv[0].lowercased() == "content-length" { length = Int(kv[1]) ?? 0 }
      if kv[0].lowercased() == "x-term" { term = kv[1].filter { $0.isLetter || $0.isNumber || $0 == "." || $0 == "_" || $0 == "-" } }
    }
    let bodyStart = sep.upperBound
    guard data.count - bodyStart >= length else { return nil }
    let full = String(first[1])
    let parts = full.split(separator: "?", maxSplits: 1)
    let query = parts.count > 1 ? String(parts[1]).replacingOccurrences(of: "source=", with: "").filter { $0.isLetter } : "claude"
    return Request(method: String(first[0]), path: String(parts[0]), query: query, term: term,
                   body: data[bodyStart..<(bodyStart + length)])
  }
}
