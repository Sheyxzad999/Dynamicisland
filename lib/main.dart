import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native.dart';
import 'prayer.dart';
import 'services/calendar.dart';
import 'services/clipboard.dart';
import 'services/currency.dart';
import 'services/weather.dart';
import 'tabs/calendar_tab.dart';
import 'tabs/clipboard_tab.dart';
import 'tabs/currency_tab.dart';
import 'tabs/weather_tab.dart';
import 'ui.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Native.instance.init();
  await ClipboardStore.instance.init();
  unawaited(PrayerService.instance.init().then((_) => WeatherService.instance.refresh()));
  unawaited(CurrencyService.instance.refresh());
  unawaited(CalendarService.instance.init());
  runApp(const OrolApp());
}

class OrolApp extends StatelessWidget {
  const OrolApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.transparent,
        canvasColor: Colors.transparent,
        colorScheme: const ColorScheme.dark(primary: Color(0xFF34C759)),
        splashFactory: NoSplash.splashFactory,
      ),
      home: const Material(type: MaterialType.transparency, child: Island()),
    );
  }
}

// ---------------------------------------------------------------------------
enum AlertKind { charging, timerDone, prayer, event }

class IslandAlert {
  final AlertKind kind;
  final String title;
  final String subtitle;
  final DateTime until;
  IslandAlert(this.kind, this.title, this.subtitle, Duration d) : until = DateTime.now().add(d);
}

// ---------------------------------------------------------------------------

/// Orolning animatsiyadagi shakli: o'lcham, burchak radiusi va shishalik darajasi.
class IslandShape {
  final double w, h, r, glass;
  const IslandShape(this.w, this.h, this.r, this.glass);
  static IslandShape lerp(IslandShape a, IslandShape b, double t) => IslandShape(
        lerpDouble(a.w, b.w, t)!,
        lerpDouble(a.h, b.h, t)!,
        lerpDouble(a.r, b.r, t)!,
        lerpDouble(a.glass, b.glass, t)!,
      );
  @override
  bool operator ==(Object other) =>
      other is IslandShape &&
      (other.w - w).abs() < 0.5 &&
      (other.h - h).abs() < 0.5 &&
      (other.r - r).abs() < 0.5 &&
      (other.glass > 0.01) == (glass > 0.01);
  @override
  int get hashCode => Object.hash(w.round(), h.round(), r.round(), glass > 0.01);
}

class IslandShapeTween extends Tween<IslandShape> {
  IslandShapeTween({super.begin, super.end});
  @override
  IslandShape lerp(double t) => IslandShape.lerp(begin!, end!, t);
}

/// Skrinshot va sinov uchun: `--dart-define=OROL_DEMO=0` — orol ochiq, 0-bo'lim.

class Island extends StatefulWidget {
  const Island({super.key});
  @override
  State<Island> createState() => _IslandState();
}

class _IslandState extends State<Island> with TickerProviderStateMixin {
  final native = Native.instance;
  final prayers = PrayerService.instance;

  bool expanded = false;
  bool dragging = false;
  int tab = 0;
  IslandAlert? alert;
  Timer? _collapseTimer;
  Timer? _ticker;
  Size _reported = Size.zero;

  // Taymer
  Duration timerTotal = Duration.zero;
  DateTime? timerEnd;
  Duration? timerPausedLeft;

  // Cho'ntak
  List<String> shelf = [];

  // Sozlamalar
  bool showPrayer = true;
  bool launchAtLogin = false;
  bool useGlass = true;
  bool glassNative = false;
  IslandShape? _sentGlass;
  String? _lastPrayerAlert;
  String? _lastEventAlert;
  String? _armedAction; // tasdiq kutayotgan tezkor amal
  Timer? _armTimer;
  Timer? _hoverTimer;

  late final AnimationController eq =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  BatteryInfo _prevBattery = const BatteryInfo();

  @override
  void initState() {
    super.initState();
    native.hover.addListener(_onHover);
    native.battery.addListener(_onBattery);
    native.media.addListener(_onMedia);
    native.notch.addListener(_refresh);
    prayers.today.addListener(_refresh);
    native.mic.addListener(_refresh);
    native.camera.addListener(_refresh);
    CalendarService.instance.events.addListener(_refresh);
    WeatherService.instance.current.addListener(_refresh);
    _prevBattery = native.battery.value;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _loadPrefs();
    native.glassSupported().then((v) => setState(() => glassNative = v));
    if (kDemo.isNotEmpty) {
      expanded = kDemo != 'compact' && kDemo != 'music';
      tab = int.tryParse(kDemo) ?? 0;
      if (kDemo != 'music') {
        timerTotal = const Duration(minutes: 25);
        timerEnd = DateTime.now().add(const Duration(minutes: 17, seconds: 32));
      }
      if (kDemo == 'cycle') {
        Timer.periodic(const Duration(seconds: 3), (_) => setState(() => tab = (tab + 1) % _tabs.length));
      }
      native.media.value = MediaInfo(
          state: 'playing', title: 'Tungi shahar', artist: 'Lo-fi Toshkent', position: 73, duration: 214, source: 'Music');
      eq.repeat();
    }
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    showPrayer = p.getBool('showPrayer') ?? true;
    useGlass = p.getBool('useGlass') ?? true;
    if (kDemo.isNotEmpty) {
      shelf = ['/demo/Taqdimot.pdf', '/demo/Logotip.png', '/demo/Montaj.mov', '/demo/Shartnoma.docx', '/demo/Loyiha'];
      if (mounted) setState(() {});
      return;
    }
    final saved = p.getStringList('shelf') ?? [];
    final ok = <String>[];
    for (final s in saved) {
      if (await native.fileExists(s)) ok.add(s);
    }
    shelf = ok;
    try {
      launchAtLogin = await native.getLaunchAtLogin();
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _saveShelf() async {
    if (kDemo.isNotEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setStringList('shelf', shelf);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onHover() {
    if (kDemo.isNotEmpty) return;
    _collapseTimer?.cancel();
    _hoverTimer?.cancel();
    if (native.hover.value) {
      // Kursor shunchaki ustidan o'tib ketsa ochilmasin: bir lahza to'xtashi kerak
      _hoverTimer = Timer(const Duration(milliseconds: 220), () {
        if (!native.hover.value || !mounted) return;
        setState(() {
          expanded = true;
          if (alert != null && alert!.kind != AlertKind.charging) alert = null;
        });
      });
    } else {
      _collapseTimer = Timer(const Duration(milliseconds: 300), () {
        if (!native.hover.value && mounted) {
          FocusManager.instance.primaryFocus?.unfocus();
          native.releaseKeyboard();
          setState(() {
            expanded = false;
            dragging = false;
            _armedAction = null;
          });
        }
      });
    }
  }

  void _onBattery() {
    final b = native.battery.value;
    if (b.plugged && !_prevBattery.plugged && _prevBattery.available) {
      alert = IslandAlert(AlertKind.charging, 'Zaryadlanmoqda', '${b.percent}%', const Duration(seconds: 4));
    }
    _prevBattery = b;
    _refresh();
  }

  void _onMedia() {
    if (native.media.value.isPlaying) {
      if (!eq.isAnimating) eq.repeat();
    } else {
      eq.stop();
    }
    _refresh();
  }

  void _tick() {
    final now = DateTime.now();
    if (alert != null && now.isAfter(alert!.until)) alert = null;

    // Taymer tugadimi?
    if (timerEnd != null && now.isAfter(timerEnd!)) {
      timerEnd = null;
      alert = IslandAlert(AlertKind.timerDone, 'Taymer tugadi', fmtClock(timerTotal), const Duration(seconds: 12));
      native.playSound('Glass');
      Timer(const Duration(milliseconds: 900), () => native.playSound('Glass'));
    }

    // Namoz vaqti kirdimi?
    if (showPrayer) {
      if (now.second == 0) prayers.refresh();
      for (final p in prayers.today.value) {
        if (p.name == 'Quyosh') continue;
        final diff = now.difference(p.time);
        final key = '${p.name}-${p.time.day}';
        if (!diff.isNegative && diff.inSeconds < 60 && _lastPrayerAlert != key) {
          _lastPrayerAlert = key;
          alert = IslandAlert(AlertKind.prayer, '${p.name} vaqti kirdi', fmtTime(p.time), const Duration(seconds: 15));
          native.playSound('Submarine');
        }
      }
    }
    // Har daqiqada ma'lumotlarni yangilash (xizmatlarning o'zi keraksiz so'rovlarni cheklaydi)
    if (now.second == 0) {
      CalendarService.instance.refresh();
      WeatherService.instance.refresh();
      CurrencyService.instance.refresh();
    }

    // Uchrashuv boshlandimi?
    for (final e in CalendarService.instance.events.value) {
      if (e.allDay) continue;
      final diff = now.difference(e.start);
      final key = '${e.title}-${e.start.millisecondsSinceEpoch}';
      if (!diff.isNegative && diff.inSeconds < 60 && _lastEventAlert != key) {
        _lastEventAlert = key;
        alert = IslandAlert(AlertKind.event, e.title, 'Hozir boshlanadi · ${fmtTime(e.start)}', const Duration(seconds: 15));
        native.playSound('Ping');
      }
    }
    _refresh();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _collapseTimer?.cancel();
    _hoverTimer?.cancel();
    _armTimer?.cancel();
    eq.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Taymer boshqaruvi

  bool get timerActive => timerEnd != null || timerPausedLeft != null;

  Duration get timerLeft {
    if (timerPausedLeft != null) return timerPausedLeft!;
    if (timerEnd == null) return Duration.zero;
    final d = timerEnd!.difference(DateTime.now());
    return d.isNegative ? Duration.zero : d;
  }

  void startTimer(Duration d) => setState(() {
        timerTotal = d;
        timerEnd = DateTime.now().add(d);
        timerPausedLeft = null;
      });

  void pauseResumeTimer() => setState(() {
        if (timerPausedLeft != null) {
          timerEnd = DateTime.now().add(timerPausedLeft!);
          timerPausedLeft = null;
        } else if (timerEnd != null) {
          timerPausedLeft = timerLeft;
          timerEnd = null;
        }
      });

  void stopTimer() => setState(() {
        timerEnd = null;
        timerPausedLeft = null;
      });

  void addMinute() => setState(() {
        timerTotal += const Duration(minutes: 1);
        if (timerPausedLeft != null) {
          timerPausedLeft = timerPausedLeft! + const Duration(minutes: 1);
        } else if (timerEnd != null) {
          timerEnd = timerEnd!.add(const Duration(minutes: 1));
        }
      });

  // -------------------------------------------------------------------------
  // Holatlar va o'lchamlar

  /// Yig'ilgan holatda notch yonida nima ko'rsatiladi.
  String get _compactMode {
    if (alert?.kind == AlertKind.charging) return 'charging';
    if (timerActive) return 'timer';
    if (native.media.value.isPlaying) return 'music';
    final ev = CalendarService.instance.next();
    if (ev != null && ev.start.isAfter(DateTime.now()) && ev.start.difference(DateTime.now()).inMinutes < 10) {
      return 'event';
    }
    if (showPrayer) {
      final n = prayers.next();
      if (n != null && n.time.difference(DateTime.now()).inMinutes < 15) return 'prayer';
    }
    if (native.mic.value || native.camera.value) return 'privacy';
    return 'idle';
  }

  bool get _bannerAlert =>
      alert != null && alert!.kind != AlertKind.charging;

  Size _targetSize(NotchInfo n) {
    if (expanded || dragging) return Size(680, n.height + 238);
    if (_bannerAlert) return Size(n.width + 200, n.height + 58);
    switch (_compactMode) {
      case 'charging':
        return Size(n.width + 220, n.height);
      case 'idle':
        return Size(n.width, n.height);
      case 'privacy':
        return Size(n.width + 48, n.height);
      case 'timer':
        // "1:05:30" kabi vaqt bir qatorga sig'ishi uchun kengroq qanot
        return Size(n.width + 150, n.height);
      default:
        return Size(n.width + 96, n.height);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = native.notch.value;
    final size = _targetSize(n);
    if (size != _reported) {
      _reported = size;
      WidgetsBinding.instance.addPostFrameCallback((_) => native.setIslandSize(size));
    }
    final open = expanded || dragging;
    final radius = open ? 30.0 : (_bannerAlert ? 24.0 : n.height * 0.32);
    final glassOn = useGlass && (open || _bannerAlert);

    final Widget content;
    if (open) {
      content = _expanded(n, size);
    } else if (_bannerAlert) {
      content = _banner(n);
    } else {
      content = _compact(n);
    }

    return DropTarget(
      acceptedKinds: const {DropItemKind.file, DropItemKind.directory},
      onEnter: (_) => setState(() {
        dragging = true;
        tab = 2;
      }),
      onLeave: () => setState(() => dragging = false),
      onDrop: (d) {
        setState(() {
          for (final item in d.items) {
            final path = switch (item) {
              DropFileItem f => f.localPath,
              DropDirectoryItem dir => dir.localPath,
              _ => null,
            };
            if (path != null && !shelf.contains(path)) shelf.insert(0, path);
          }
          dragging = false;
          tab = 2;
        });
        _saveShelf();
      },
      child: Align(
        alignment: Alignment.topCenter,
        child: TweenAnimationBuilder<IslandShape>(
          tween: IslandShapeTween(end: IslandShape(size.width, size.height, radius, glassOn ? 1 : 0)),
          duration: const Duration(milliseconds: 420),
          curve: Curves.easeOutBack,
          builder: (context, s, child) {
            _syncGlass(s);
            final g = s.glass.clamp(0.0, 1.0);
            // Notch bilan qo'shilib ketishi uchun yopiq holatda — sof qora,
            // ochilganda — ortidagi Liquid Glass ko'rinadi.
            final solid = glassNative ? 0.0 : 0.5;
            return Container(
              width: s.w,
              height: s.h,
              decoration: BoxDecoration(
                color: g > 0 ? null : Colors.black,
                borderRadius: BorderRadius.vertical(bottom: Radius.circular(s.r.clamp(0, 60))),
                gradient: g > 0
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color.lerp(Colors.black, Colors.black.withValues(alpha: solid + 0.10), g)!,
                          Color.lerp(Colors.black, Colors.black.withValues(alpha: solid), g)!,
                        ],
                      )
                    : null,
                boxShadow: open
                    ? [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 30, offset: const Offset(0, 12))]
                    : null,
              ),
              foregroundDecoration: g > 0
                  ? BoxDecoration(
                      borderRadius: BorderRadius.vertical(bottom: Radius.circular(s.r.clamp(0, 60))),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.14 * g), width: 0.8),
                    )
                  : null,
              clipBehavior: Clip.antiAlias,
              child: child,
            );
          },
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minWidth: size.width,
            maxWidth: size.width,
            minHeight: size.height,
            maxHeight: size.height,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: KeyedSubtree(
                key: ValueKey(open ? 'open$tab' : (_bannerAlert ? 'banner' : _compactMode)),
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Native shisha qatlamini Flutter'dagi animatsiyaga ergashtiradi.
  void _syncGlass(IslandShape s) {
    if (s == _sentGlass) return;
    _sentGlass = s;
    final visible = s.glass > 0.01;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      native.setGlass(s.w, s.h, s.r.clamp(0, 60), visible);
    });
  }

  // -------------------------------------------------------------------------
  // Yig'ilgan ko'rinish (notch yonidagi "qanotlar")

  Widget _compact(NotchInfo n) {
    final mode = _compactMode;
    if (mode == 'idle') return const SizedBox.expand();
    Widget left, right;
    switch (mode) {
      case 'charging':
        left = const Text('Zaryadlanmoqda', style: TextStyle(color: kGreen, fontSize: 13, fontWeight: FontWeight.w600));
        right = Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${native.battery.value.percent}%',
              style: const TextStyle(color: kGreen, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          BatteryIcon(percent: native.battery.value.percent, charging: true),
        ]);
      case 'timer':
        left = Icon(timerPausedLeft != null ? Icons.pause_circle_filled : Icons.timer, color: kOrange, size: 18);
        right = Text(fmtClock(timerLeft),
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: const TextStyle(color: kOrange, fontSize: 13, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]));
      case 'music':
        left = Artwork(media: native.media.value, size: 22, radius: 6);
        right = Equalizer(controller: eq, color: kGreen);
      case 'event':
        final e = CalendarService.instance.next()!;
        left = const Icon(Icons.event_rounded, color: kPurple, size: 17);
        right = Text(fmtLeft(e.start.difference(DateTime.now())),
            style: const TextStyle(color: kPurple, fontSize: 12, fontWeight: FontWeight.w600));
      case 'privacy':
        left = const SizedBox();
        right = const SizedBox();
      default: // prayer
        final p = prayers.next()!;
        left = const Icon(Icons.mosque, color: kTeal, size: 17);
        right = Text(fmtLeft(p.time.difference(DateTime.now())),
            style: const TextStyle(color: kTeal, fontSize: 12, fontWeight: FontWeight.w600));
    }
    return Row(children: [
      const SizedBox(width: 12),
      Expanded(child: Align(alignment: Alignment.centerLeft, child: left)),
      SizedBox(width: n.width),
      Expanded(
        child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Flexible(child: right),
          _privacyDots(),
        ]),
      ),
      const SizedBox(width: 12),
    ]);
  }

  /// Mikrofon (to'q sariq) yoki kamera (yashil) ishlayotganini bildiradi.
  Widget _privacyDots() {
    final dots = <Widget>[
      if (native.mic.value) _dot(kOrange, 'Mikrofon ishlatilmoqda'),
      if (native.camera.value) _dot(kGreen, 'Kamera ishlatilmoqda'),
    ];
    if (dots.isEmpty) return const SizedBox();
    return Padding(padding: const EdgeInsets.only(left: 6), child: Row(mainAxisSize: MainAxisSize.min, children: dots));
  }

  Widget _dot(Color c, String tip) => Tooltip(
        message: tip,
        child: Container(
          width: 7, height: 7,
          margin: const EdgeInsets.only(left: 3),
          decoration: BoxDecoration(color: c, shape: BoxShape.circle, boxShadow: [BoxShadow(color: c, blurRadius: 6)]),
        ),
      );

  // Taymer tugashi yoki namoz vaqti kirishi haqida xabar
  Widget _banner(NotchInfo n) {
    final a = alert!;
    final (icon, color) = switch (a.kind) {
      AlertKind.prayer => (Icons.mosque, kTeal),
      AlertKind.event => (Icons.event_rounded, kPurple),
      _ => (Icons.alarm, kOrange),
    };
    return Padding(
      padding: EdgeInsets.fromLTRB(18, n.height + 6, 18, 10),
      child: Row(children: [
        Icon(icon, color: color, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            Text(a.subtitle, style: const TextStyle(color: kDim, fontSize: 12)),
          ]),
        ),
        GestureDetector(
          onTap: () => setState(() => alert = null),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: glassTile(radius: 14, tint: color, active: true),
            child: Text('OK', style: TextStyle(color: color, fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }

  // -------------------------------------------------------------------------
  // Ochilgan ko'rinish

  static const _tabs = [
    (Icons.home_rounded, 'Asosiy'),
    (Icons.timer_outlined, 'Taymer'),
    (Icons.inventory_2_outlined, "Cho'ntak"),
    (Icons.content_paste_rounded, 'Nusxalar'),
    (Icons.currency_exchange_rounded, 'Valyuta'),
    (Icons.wb_sunny_outlined, 'Ob-havo'),
    (Icons.event_outlined, 'Kalendar'),
    (Icons.mosque_outlined, 'Namoz'),
    (Icons.settings_outlined, 'Sozlamalar'),
  ];

  static const _actions = [
    (Icons.lock_rounded, 'Ekranni qulflash', 'lock'),
    (Icons.desktop_access_disabled_rounded, 'Ekranni o‘chirish', 'display'),
    (Icons.bedtime_rounded, 'Uyqu rejimi', 'sleep'),
    (Icons.screenshot_monitor_rounded, 'Ekran rasmi', 'screenshot'),
  ];

  /// Qulflash/uyqu kabi amallar ikki bosishni talab qiladi (tasodifan bosilmasligi uchun).
  Widget _actionButton(IconData icon, String label, String id) {
    final needsConfirm = id != 'screenshot';
    final armed = _armedAction == id;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Tap(
        tooltip: armed ? null : label,
        onTap: () {
          if (!needsConfirm || armed) {
            _armTimer?.cancel();
            setState(() => _armedAction = null);
            native.action(id);
            return;
          }
          _armTimer?.cancel();
          setState(() => _armedAction = id);
          _armTimer = Timer(const Duration(seconds: 3), () {
            if (mounted) setState(() => _armedAction = null);
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: armed ? kRed.withValues(alpha: 0.2) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: armed ? kRed : kDim),
            if (armed) ...[
              const SizedBox(width: 5),
              const Text('Yana bosing', style: TextStyle(color: kRed, fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ]),
        ),
      ),
    );
  }

  Widget _expanded(NotchInfo n, Size size) {
    final side = (size.width - n.width) / 2;
    final b = native.battery.value;
    final w = WeatherService.instance.current.value;
    return Column(children: [
      // Yuqori qator: tezkor amallar | notch | holat
      SizedBox(
        height: n.height,
        child: Row(children: [
          SizedBox(
            width: side,
            child: Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Row(children: [
                Text(
                  '${fmtTime(DateTime.now())}  ·  ${DateTime.now().day}-${uzMonths[DateTime.now().month - 1]}',
                  style: const TextStyle(color: kDim, fontSize: 12),
                ),
              ]),
            ),
          ),
          SizedBox(width: n.width),
          SizedBox(
            width: side,
            child: Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                _privacyDots(),
                const Spacer(),
                if (w != null) ...[
                  Icon(weatherIcon(w.code, day: w.isDay), size: 14, color: weatherColor(w.code, day: w.isDay)),
                  const SizedBox(width: 4),
                  Text('${w.temp.round()}°', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  const SizedBox(width: 12),
                ],
                if (b.available) ...[
                  Text('${b.percent}%', style: TextStyle(color: b.plugged ? kGreen : Colors.white, fontSize: 12)),
                  const SizedBox(width: 5),
                  BatteryIcon(percent: b.percent, charging: b.plugged),
                ],
              ]),
            ),
          ),
        ]),
      ),
      // Bo'limlar paneli
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
        child: SizedBox(
          height: 32,
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(2),
              decoration: glassTile(radius: 16),
              child: Row(children: [
            for (var i = 0; i < _tabs.length; i++)
              Tap(
                tooltip: tab == i ? null : _tabs[i].$2,
                onTap: () => setState(() => tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  decoration: tab == i
                      ? BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Colors.white.withValues(alpha: 0.30), Colors.white.withValues(alpha: 0.16)],
                          ),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 0.8),
                          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 8, offset: const Offset(0, 2))],
                        )
                      : const BoxDecoration(),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(_tabs[i].$1, size: 15, color: tab == i ? Colors.white : kDim),
                    if (tab == i) ...[
                      const SizedBox(width: 6),
                      Text(_tabs[i].$2,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ],
                  ]),
                ),
              ),
              ]),
            ),
            const Spacer(),
            for (final a in _actions) _actionButton(a.$1, a.$2, a.$3),
          ]),
        ),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
          child: switch (tab) {
            0 => _homeTab(),
            1 => _timerTab(),
            2 => _shelfTab(),
            3 => const ClipboardTab(),
            4 => const CurrencyTab(),
            5 => const WeatherTab(),
            6 => const CalendarTab(),
            7 => _prayerTab(),
            _ => _settingsTab(),
          },
        ),
      ),
    ]);
  }

  // --- Asosiy -------------------------------------------------------------

  Widget _homeTab() {
    return Row(children: [
      Expanded(child: _musicPlayer()),
      Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 14), color: kHair),
      SizedBox(width: 190, child: _sideInfo()),
    ]);
  }

  Widget _musicPlayer() {
    final m = native.media.value;
    if (!m.hasTrack) {
      return const Row(children: [
        Icon(Icons.music_off_rounded, color: kDim, size: 34),
        SizedBox(width: 12),
        Expanded(
          child: Text('Musiqa ijro etilmayapti\nSpotify yoki Apple Music’da qo‘shiq qo‘ying',
              style: TextStyle(color: kDim, fontSize: 12, height: 1.4)),
        ),
      ]);
    }
    final pos = m.livePosition;
    final frac = m.duration > 0 ? (pos / m.duration).clamp(0.0, 1.0) : 0.0;
    return Row(children: [
      Artwork(media: m, size: 84, radius: 14),
      const SizedBox(width: 14),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Row(children: [
            Expanded(
              child: Text(m.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            if (m.isPlaying) Equalizer(controller: eq, color: kGreen),
          ]),
          Text(m.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kDim, fontSize: 12)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac, minHeight: 4,
              backgroundColor: Colors.white.withValues(alpha: 0.16),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 4),
          Row(children: [
            Text(fmtClock(Duration(seconds: pos.round())), style: const TextStyle(color: kDim, fontSize: 10)),
            const Spacer(),
            Text(fmtClock(Duration(seconds: m.duration.round())), style: const TextStyle(color: kDim, fontSize: 10)),
          ]),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _iconBtn(Icons.skip_previous_rounded, 26, () => native.media_('previous')),
            const SizedBox(width: 14),
            _iconBtn(m.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded, 32, () => native.media_('playpause')),
            const SizedBox(width: 14),
            _iconBtn(Icons.skip_next_rounded, 26, () => native.media_('next')),
          ]),
        ]),
      ),
    ]);
  }

  Widget _sideInfo() {
    final b = native.battery.value;
    final next = prayers.next();
    final ev = CalendarService.instance.next();
    final w = WeatherService.instance.current.value;
    final usd = CurrencyService.instance.byCode('USD');
    final now = DateTime.now();
    final rows = <Widget>[
      if (showPrayer && next != null)
        _infoRow(Icons.mosque, kTeal, '${next.name} · ${fmtTime(next.time)}', '${fmtLeft(next.time.difference(now))} qoldi',
            onTap: () => setState(() => tab = 7)),
      if (ev != null)
        _infoRow(Icons.event_rounded, kPurple, ev.title,
            ev.start.isBefore(now) ? 'Hozir · ${fmtTime(ev.end)} gacha' : '${dayLabel(ev.start)}, ${fmtTime(ev.start)}',
            onTap: () => setState(() => tab = 6)),
      if (w != null)
        _infoRow(weatherIcon(w.code, day: w.isDay), weatherColor(w.code, day: w.isDay), '${w.temp.round()}° · ${weatherText(w.code)}',
            '${w.city}, his qilinadi ${w.feels.round()}°', onTap: () => setState(() => tab = 5)),
      if (usd != null)
        _infoRow(Icons.attach_money_rounded, kGreen, '1 \$ = ${formatMoney(usd.rate)} so‘m',
            '${usd.diff >= 0 ? '▲' : '▼'} ${formatMoney(usd.diff.abs())} · Markaziy bank', onTap: () => setState(() => tab = 4)),
      if (b.available)
        _infoRow(b.plugged ? Icons.battery_charging_full_rounded : Icons.battery_std_rounded,
            b.plugged ? kGreen : (b.percent <= 20 ? kRed : Colors.white), 'Batareya ${b.percent}%', _batteryText(b)),
    ];
    return ListView(padding: EdgeInsets.zero, children: rows);
  }

  Widget _infoRow(IconData icon, Color color, String title, String sub, {VoidCallback? onTap}) => Tap(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Row(children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 9),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 11.5, fontWeight: FontWeight.w600)),
                Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kDim, fontSize: 10)),
              ]),
            ),
          ]),
        ),
      );

  String _batteryText(BatteryInfo b) {
    if (b.plugged) {
      if (b.percent >= 100 || !b.charging) return 'Quvvat manbaiga ulangan';
      if (b.minutesToFull > 0) return "To'lishiga ${fmtLeft(Duration(minutes: b.minutesToFull))}";
      return 'Zaryadlanmoqda';
    }
    if (b.minutesToEmpty > 0) return "Taxminan ${fmtLeft(Duration(minutes: b.minutesToEmpty))} yetadi";
    return 'Batareyadan ishlamoqda';
  }

  // --- Taymer ---------------------------------------------------------------

  Widget _timerTab() {
    if (timerActive) {
      final left = timerLeft;
      final frac = timerTotal.inMilliseconds > 0 ? left.inMilliseconds / timerTotal.inMilliseconds : 0.0;
      return Row(children: [
        SizedBox(
          width: 110, height: 110,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: frac, strokeWidth: 7,
                backgroundColor: kOrange.withValues(alpha: 0.18),
                valueColor: const AlwaysStoppedAnimation(kOrange),
                strokeCap: StrokeCap.round,
              ),
            ),
            Text(fmtClock(left),
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: Colors.white, fontFeatures: [FontFeature.tabularFigures()])),
          ]),
        ),
        const SizedBox(width: 28),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(timerPausedLeft != null ? "To'xtatilgan" : 'Taymer ishlamoqda',
                style: const TextStyle(color: kOrange, fontSize: 14, fontWeight: FontWeight.w600)),
            Text('Jami: ${fmtClock(timerTotal)}', style: const TextStyle(color: kDim, fontSize: 12)),
            const SizedBox(height: 14),
            Row(children: [
              _pill(timerPausedLeft != null ? 'Davom etish' : 'Pauza', kOrange, pauseResumeTimer),
              const SizedBox(width: 8),
              _pill('+1 daq', Colors.white, addMinute),
              const SizedBox(width: 8),
              _pill("To'xtatish", const Color(0xFFFF453A), stopTimer),
            ]),
          ]),
        ),
      ]);
    }
    const presets = [1, 3, 5, 10, 15, 20, 25, 30, 45, 60, 90, 120];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Necha daqiqaga?', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final m in presets)
          GestureDetector(
            onTap: () => startTimer(Duration(minutes: m)),
            child: Container(
              width: 76, height: 40,
              alignment: Alignment.center,
              decoration: glassTile(radius: 12),
              child: Text(m < 60 ? '$m daq' : '${m ~/ 60}${m % 60 == 0 ? '' : ',5'} soat',
                  style: const TextStyle(color: kOrange, fontWeight: FontWeight.w600, fontSize: 13)),
            ),
          ),
      ]),
    ]);
  }

  // --- Cho'ntak -------------------------------------------------------------

  Widget _shelfTab() {
    if (shelf.isEmpty || dragging) {
      return Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: dragging ? kGreen : Colors.white24, width: 1.5),
          color: dragging ? kGreen.withValues(alpha: 0.08) : Colors.transparent,
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.move_to_inbox_rounded, size: 34, color: dragging ? kGreen : kDim),
            const SizedBox(height: 6),
            Text(dragging ? "Qo'yib yuboring" : "Fayllarni notch ustiga sudrab tashlang",
                style: TextStyle(color: dragging ? kGreen : kDim, fontSize: 13)),
            if (!dragging)
              const Text("Ular shu yerda saqlanib turadi", style: TextStyle(color: Colors.white24, fontSize: 11)),
          ]),
        ),
      );
    }
    return Column(children: [
      Row(children: [
        Text('${shelf.length} ta fayl', style: const TextStyle(color: kDim, fontSize: 12)),
        const Spacer(),
        const Text('Bosing: ochish · O‘ng tugma: Finder’da ko‘rsatish  ',
            style: TextStyle(color: Colors.white24, fontSize: 10)),
        GestureDetector(
          onTap: () {
            setState(() => shelf.clear());
            _saveShelf();
          },
          child: const Text('Tozalash', style: TextStyle(color: Color(0xFFFF453A), fontSize: 12)),
        ),
      ]),
      const SizedBox(height: 8),
      Expanded(
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: shelf.length,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: (_, i) => _fileTile(shelf[i]),
        ),
      ),
    ]);
  }

  Widget _fileTile(String path) {
    final name = path.split('/').where((s) => s.isNotEmpty).last;
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    final (icon, color) = _fileIcon(ext);
    return GestureDetector(
      onTap: () => native.openFile(path),
      onSecondaryTap: () => native.revealFile(path),
      child: Container(
        width: 92,
        padding: const EdgeInsets.all(8),
        decoration: glassTile(radius: 14),
        child: Stack(children: [
          Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(icon, color: color, size: 34),
            const SizedBox(height: 6),
            Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 10.5)),
          ]),
          Positioned(
            right: 0, top: 0,
            child: GestureDetector(
              onTap: () {
                setState(() => shelf.remove(path));
                _saveShelf();
              },
              child: const Icon(Icons.close_rounded, size: 14, color: kDim),
            ),
          ),
        ]),
      ),
    );
  }

  (IconData, Color) _fileIcon(String ext) {
    const img = {'png', 'jpg', 'jpeg', 'heic', 'gif', 'webp', 'svg', 'bmp', 'tiff'};
    const vid = {'mp4', 'mov', 'mkv', 'avi', 'webm', 'm4v'};
    const aud = {'mp3', 'wav', 'm4a', 'aac', 'flac', 'ogg'};
    const arc = {'zip', 'rar', '7z', 'tar', 'gz', 'dmg'};
    const doc = {'doc', 'docx', 'txt', 'rtf', 'pages', 'md'};
    const sheet = {'xls', 'xlsx', 'csv', 'numbers'};
    if (ext == 'pdf') return (Icons.picture_as_pdf_rounded, const Color(0xFFFF453A));
    if (img.contains(ext)) return (Icons.image_rounded, kTeal);
    if (vid.contains(ext)) return (Icons.movie_rounded, const Color(0xFFBF5AF2));
    if (aud.contains(ext)) return (Icons.audiotrack_rounded, const Color(0xFFFF375F));
    if (arc.contains(ext)) return (Icons.folder_zip_rounded, kOrange);
    if (doc.contains(ext)) return (Icons.description_rounded, const Color(0xFF0A84FF));
    if (sheet.contains(ext)) return (Icons.table_chart_rounded, kGreen);
    if (ext.isEmpty) return (Icons.folder_rounded, const Color(0xFF0A84FF));
    return (Icons.insert_drive_file_rounded, kDim);
  }

  // --- Namoz ----------------------------------------------------------------

  Widget _prayerTab() {
    final list = prayers.today.value;
    if (list.isEmpty) {
      return const Center(
        child: Text("Namoz vaqtlari yuklanmoqda...\nInternet aloqasini tekshiring",
            textAlign: TextAlign.center, style: TextStyle(color: kDim, fontSize: 12)),
      );
    }
    final next = prayers.next();
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(prayers.cityName.value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text('${now.day}-${uzMonths[now.month - 1]}, ${uzWeekdays[now.weekday - 1]}',
            style: const TextStyle(color: kDim, fontSize: 12)),
      ]),
      const SizedBox(height: 10),
      Expanded(
        child: Row(children: [
          for (final p in list)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: glassTile(
                    radius: 14,
                    tint: next?.name == p.name && next?.time == p.time ? kTeal : null,
                    active: next?.name == p.name && next?.time == p.time),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(p.name, style: TextStyle(color: p.time.isBefore(now) ? kDim : Colors.white, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(fmtTime(p.time),
                      style: TextStyle(
                          color: p.time.isBefore(now) ? kDim : Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }


  // --- Sozlamalar -----------------------------------------------------------

  Widget _settingsTab() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Shahar (namoz vaqtlari uchun)', style: TextStyle(color: kDim, fontSize: 11)),
      const SizedBox(height: 6),
      SizedBox(
        height: 28,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final c in cities)
            GestureDetector(
              onTap: () => prayers.setCity(c.name).then((_) => WeatherService.instance.refresh(force: true)),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: glassTile(
                    radius: 14,
                    tint: prayers.cityName.value == c.name ? kTeal : null,
                    active: prayers.cityName.value == c.name),
                child: Text(c.name,
                    style: TextStyle(color: prayers.cityName.value == c.name ? kTeal : Colors.white, fontSize: 12)),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
      _toggle(glassNative ? 'Liquid Glass ko‘rinishi' : 'Shaffof (shisha) ko‘rinish', useGlass, (v) async {
        setState(() => useGlass = v);
        final p = await SharedPreferences.getInstance();
        await p.setBool('useGlass', v);
      }),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(
          child: _toggle('Kompyuter yonganda ochilsin', launchAtLogin, (v) async {
            try {
              final r = await native.setLaunchAtLogin(v);
              setState(() => launchAtLogin = r);
            } catch (_) {}
          }),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _toggle("Namoz vaqtlarini ko'rsatish", showPrayer, (v) async {
            setState(() => showPrayer = v);
            final p = await SharedPreferences.getInstance();
            await p.setBool('showPrayer', v);
          }),
        ),
      ]),
      const Spacer(),
      Row(children: [
        const Text('Dinamik Orol 1.2.2', style: TextStyle(color: Colors.white38, fontSize: 11)),
        const Spacer(),
        _pill('Dasturdan chiqish', const Color(0xFFFF453A), native.quit),
      ]),
    ]);
  }

  Widget _toggle(String label, bool value, ValueChanged<bool> onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: glassTile(radius: 12),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12))),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 34, height: 20,
            padding: const EdgeInsets.all(2),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: value ? kGreen : Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              boxShadow: value ? [BoxShadow(color: kGreen.withValues(alpha: 0.45), blurRadius: 8)] : null,
            ),
            child: Container(width: 16, height: 16, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle)),
          ),
        ]),
      ),
    );
  }

  // --- Umumiy tugmalar ------------------------------------------------------

  Widget _iconBtn(IconData icon, double size, VoidCallback onTap) =>
      GestureDetector(onTap: onTap, child: Icon(icon, size: size, color: Colors.white));

  Widget _pill(String label, Color color, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: glassTile(radius: 14, tint: color, active: true),
          child: Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
        ),
      );
}

// ---------------------------------------------------------------------------
// Kichik vidjetlar

class Artwork extends StatelessWidget {
  final MediaInfo media;
  final double size;
  final double radius;
  const Artwork({super.key, required this.media, required this.size, required this.radius});

  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size, height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: media.source == 'Spotify'
              ? const [Color(0xFF1DB954), Color(0xFF0E5C2A)]
              : const [Color(0xFFFF375F), Color(0xFFBF5AF2)],
        ),
      ),
      child: Icon(Icons.music_note_rounded, color: Colors.white, size: size * 0.55),
    );
    if (media.artwork.isEmpty) return fallback;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Image.network(media.artwork, width: size, height: size, fit: BoxFit.cover,
          gaplessPlayback: true, errorBuilder: (_, _, _) => fallback),
    );
  }
}

class Equalizer extends StatelessWidget {
  final AnimationController controller;
  final Color color;
  const Equalizer({super.key, required this.controller, required this.color});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (_, _) {
        final t = controller.value * 2 * math.pi;
        const phases = [0.0, 1.7, 3.1, 4.6];
        const speeds = [1.0, 2.0, 1.0, 2.0];
        return SizedBox(
          height: 16,
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
            for (var i = 0; i < 4; i++)
              Container(
                width: 3,
                height: 4 + 12 * (0.5 + 0.5 * math.sin(t * speeds[i] + phases[i])).abs(),
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
              ),
          ]),
        );
      },
    );
  }
}

class BatteryIcon extends StatelessWidget {
  final int percent;
  final bool charging;
  const BatteryIcon({super.key, required this.percent, required this.charging});

  @override
  Widget build(BuildContext context) {
    final color = charging ? kGreen : (percent <= 20 ? const Color(0xFFFF453A) : Colors.white);
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 24, height: 12,
        padding: const EdgeInsets.all(1.5),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white54, width: 1),
          borderRadius: BorderRadius.circular(3.5),
        ),
        child: Stack(children: [
          FractionallySizedBox(
            widthFactor: (percent / 100).clamp(0.05, 1.0),
            child: Container(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(1.5))),
          ),
          if (charging) const Center(child: Icon(Icons.bolt, size: 10, color: Colors.black)),
        ]),
      ),
      Container(
        width: 1.5, height: 4,
        margin: const EdgeInsets.only(left: 1),
        decoration: const BoxDecoration(color: Colors.white54, borderRadius: BorderRadius.horizontal(right: Radius.circular(1))),
      ),
    ]);
  }
}
