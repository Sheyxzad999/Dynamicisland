import 'dart:async';
import 'dart:math' as math;

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'native.dart';
import 'prayer.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Native.instance.init();
  unawaited(PrayerService.instance.init());
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
// Ranglar va yordamchilar

const _green = Color(0xFF34C759);
const _orange = Color(0xFFFF9F0A);
const _teal = Color(0xFF64D2FF);
const _dim = Color(0xFF8E8E93);
const _card = Color(0xFF1C1C1E);

String two(int n) => n.toString().padLeft(2, '0');

String fmtClock(Duration d) {
  final s = d.inSeconds.clamp(0, 1 << 30);
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

String fmtLeft(Duration d) {
  final m = (d.inSeconds / 60).ceil();
  if (m < 60) return '$m daq';
  return '${m ~/ 60} soat ${m % 60} daq';
}

String fmtTime(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

enum AlertKind { charging, timerDone, prayer }

class IslandAlert {
  final AlertKind kind;
  final String title;
  final String subtitle;
  final DateTime until;
  IslandAlert(this.kind, this.title, this.subtitle, Duration d) : until = DateTime.now().add(d);
}

// ---------------------------------------------------------------------------

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
  String? _lastPrayerAlert;

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
    _prevBattery = native.battery.value;
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final p = await SharedPreferences.getInstance();
    showPrayer = p.getBool('showPrayer') ?? true;
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
    final p = await SharedPreferences.getInstance();
    await p.setStringList('shelf', shelf);
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  void _onHover() {
    _collapseTimer?.cancel();
    if (native.hover.value) {
      setState(() {
        expanded = true;
        if (alert != null && alert!.kind != AlertKind.charging) alert = null;
      });
    } else {
      _collapseTimer = Timer(const Duration(milliseconds: 300), () {
        if (!native.hover.value && mounted) {
          setState(() {
            expanded = false;
            dragging = false;
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
    _refresh();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _collapseTimer?.cancel();
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
    if (showPrayer) {
      final n = prayers.next();
      if (n != null && n.time.difference(DateTime.now()).inMinutes < 15) return 'prayer';
    }
    return 'idle';
  }

  bool get _bannerAlert =>
      alert != null && (alert!.kind == AlertKind.timerDone || alert!.kind == AlertKind.prayer);

  Size _targetSize(NotchInfo n) {
    if (expanded || dragging) return Size(580, n.height + 168);
    if (_bannerAlert) return Size(n.width + 200, n.height + 58);
    switch (_compactMode) {
      case 'charging':
        return Size(n.width + 220, n.height);
      case 'idle':
        return Size(n.width, n.height);
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
    final radius = open ? 28.0 : (_bannerAlert ? 22.0 : n.height * 0.32);

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
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 380),
          curve: Curves.easeOutBack,
          width: size.width,
          height: size.height,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(radius)),
            boxShadow: open
                ? [BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 8))]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
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

  // -------------------------------------------------------------------------
  // Yig'ilgan ko'rinish (notch yonidagi "qanotlar")

  Widget _compact(NotchInfo n) {
    final mode = _compactMode;
    if (mode == 'idle') return const SizedBox.expand();
    Widget left, right;
    switch (mode) {
      case 'charging':
        left = const Text('Zaryadlanmoqda', style: TextStyle(color: _green, fontSize: 13, fontWeight: FontWeight.w600));
        right = Row(mainAxisSize: MainAxisSize.min, children: [
          Text('${native.battery.value.percent}%',
              style: const TextStyle(color: _green, fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(width: 6),
          BatteryIcon(percent: native.battery.value.percent, charging: true),
        ]);
      case 'timer':
        left = Icon(timerPausedLeft != null ? Icons.pause_circle_filled : Icons.timer, color: _orange, size: 18);
        right = Text(fmtClock(timerLeft),
            style: const TextStyle(color: _orange, fontSize: 13, fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()]));
      case 'music':
        left = Artwork(media: native.media.value, size: 22, radius: 6);
        right = Equalizer(controller: eq, color: _green);
      default: // prayer
        final p = prayers.next()!;
        left = const Icon(Icons.mosque, color: _teal, size: 17);
        right = Text(fmtLeft(p.time.difference(DateTime.now())),
            style: const TextStyle(color: _teal, fontSize: 12, fontWeight: FontWeight.w600));
    }
    return Row(children: [
      const SizedBox(width: 12),
      Expanded(child: Align(alignment: Alignment.centerLeft, child: left)),
      SizedBox(width: n.width),
      Expanded(child: Align(alignment: Alignment.centerRight, child: right)),
      const SizedBox(width: 12),
    ]);
  }

  // Taymer tugashi yoki namoz vaqti kirishi haqida xabar
  Widget _banner(NotchInfo n) {
    final a = alert!;
    final isPrayer = a.kind == AlertKind.prayer;
    final color = isPrayer ? _teal : _orange;
    return Padding(
      padding: EdgeInsets.fromLTRB(18, n.height + 6, 18, 10),
      child: Row(children: [
        Icon(isPrayer ? Icons.mosque : Icons.alarm, color: color, size: 30),
        const SizedBox(width: 12),
        Expanded(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(a.title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
            Text(a.subtitle, style: const TextStyle(color: _dim, fontSize: 12)),
          ]),
        ),
        GestureDetector(
          onTap: () => setState(() => alert = null),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(14)),
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
    (Icons.mosque_outlined, 'Namoz'),
    (Icons.settings_outlined, 'Sozlamalar'),
  ];

  Widget _expanded(NotchInfo n, Size size) {
    final side = (size.width - n.width) / 2;
    final b = native.battery.value;
    return Column(children: [
      SizedBox(
        height: n.height,
        child: Row(children: [
          SizedBox(
            width: side,
            child: Padding(
              padding: const EdgeInsets.only(left: 14),
              child: Row(children: [
                for (var i = 0; i < _tabs.length; i++)
                  Tooltip(
                    message: _tabs[i].$2,
                    waitDuration: const Duration(milliseconds: 600),
                    child: GestureDetector(
                      onTap: () => setState(() => tab = i),
                      child: Container(
                        width: 30,
                        height: 24,
                        margin: const EdgeInsets.only(right: 3),
                        decoration: BoxDecoration(
                          color: tab == i ? Colors.white.withValues(alpha: 0.14) : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(_tabs[i].$1, size: 16, color: tab == i ? Colors.white : _dim),
                      ),
                    ),
                  ),
              ]),
            ),
          ),
          SizedBox(width: n.width),
          SizedBox(
            width: side,
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                Text(_tabs[tab].$2, style: const TextStyle(color: _dim, fontSize: 12)),
                const Spacer(),
                if (b.available) ...[
                  Text('${b.percent}%', style: TextStyle(color: b.plugged ? _green : Colors.white, fontSize: 12)),
                  const SizedBox(width: 5),
                  BatteryIcon(percent: b.percent, charging: b.plugged),
                ],
              ]),
            ),
          ),
        ]),
      ),
      Expanded(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
          child: switch (tab) {
            0 => _homeTab(),
            1 => _timerTab(),
            2 => _shelfTab(),
            3 => _prayerTab(),
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
      Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 14), color: Colors.white10),
      SizedBox(width: 160, child: _sideInfo()),
    ]);
  }

  Widget _musicPlayer() {
    final m = native.media.value;
    if (!m.hasTrack) {
      return const Row(children: [
        Icon(Icons.music_off_rounded, color: _dim, size: 34),
        SizedBox(width: 12),
        Expanded(
          child: Text('Musiqa ijro etilmayapti\nSpotify yoki Apple Music’da qo‘shiq qo‘ying',
              style: TextStyle(color: _dim, fontSize: 12, height: 1.4)),
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
            if (m.isPlaying) Equalizer(controller: eq, color: _green),
          ]),
          Text(m.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: _dim, fontSize: 12)),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac, minHeight: 4,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation(Colors.white),
            ),
          ),
          const SizedBox(height: 4),
          Row(children: [
            Text(fmtClock(Duration(seconds: pos.round())), style: const TextStyle(color: _dim, fontSize: 10)),
            const Spacer(),
            Text(fmtClock(Duration(seconds: m.duration.round())), style: const TextStyle(color: _dim, fontSize: 10)),
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
    return Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      if (showPrayer && next != null) ...[
        Row(children: [
          const Icon(Icons.mosque, size: 14, color: _teal),
          const SizedBox(width: 6),
          Text('Keyingi: ${next.name}', style: const TextStyle(color: _teal, fontSize: 12)),
        ]),
        const SizedBox(height: 2),
        Text(fmtTime(next.time),
            style: const TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600)),
        Text('${fmtLeft(next.time.difference(DateTime.now()))} qoldi', style: const TextStyle(color: _dim, fontSize: 11)),
        const SizedBox(height: 12),
      ],
      if (b.available) ...[
        Row(children: [
          BatteryIcon(percent: b.percent, charging: b.plugged),
          const SizedBox(width: 8),
          Text('${b.percent}%', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 2),
        Text(_batteryText(b), style: const TextStyle(color: _dim, fontSize: 11)),
      ],
    ]);
  }

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
                backgroundColor: _orange.withValues(alpha: 0.18),
                valueColor: const AlwaysStoppedAnimation(_orange),
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
                style: const TextStyle(color: _orange, fontSize: 14, fontWeight: FontWeight.w600)),
            Text('Jami: ${fmtClock(timerTotal)}', style: const TextStyle(color: _dim, fontSize: 12)),
            const SizedBox(height: 14),
            Row(children: [
              _pill(timerPausedLeft != null ? 'Davom etish' : 'Pauza', _orange, pauseResumeTimer),
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
              decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
              child: Text(m < 60 ? '$m daq' : '${m ~/ 60}${m % 60 == 0 ? '' : ',5'} soat',
                  style: const TextStyle(color: _orange, fontWeight: FontWeight.w600, fontSize: 13)),
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
          border: Border.all(color: dragging ? _green : Colors.white24, width: 1.5),
          color: dragging ? _green.withValues(alpha: 0.08) : Colors.transparent,
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.move_to_inbox_rounded, size: 34, color: dragging ? _green : _dim),
            const SizedBox(height: 6),
            Text(dragging ? "Qo'yib yuboring" : "Fayllarni notch ustiga sudrab tashlang",
                style: TextStyle(color: dragging ? _green : _dim, fontSize: 13)),
            if (!dragging)
              const Text("Ular shu yerda saqlanib turadi", style: TextStyle(color: Colors.white24, fontSize: 11)),
          ]),
        ),
      );
    }
    return Column(children: [
      Row(children: [
        Text('${shelf.length} ta fayl', style: const TextStyle(color: _dim, fontSize: 12)),
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
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14)),
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
              child: const Icon(Icons.close_rounded, size: 14, color: _dim),
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
    if (img.contains(ext)) return (Icons.image_rounded, _teal);
    if (vid.contains(ext)) return (Icons.movie_rounded, const Color(0xFFBF5AF2));
    if (aud.contains(ext)) return (Icons.audiotrack_rounded, const Color(0xFFFF375F));
    if (arc.contains(ext)) return (Icons.folder_zip_rounded, _orange);
    if (doc.contains(ext)) return (Icons.description_rounded, const Color(0xFF0A84FF));
    if (sheet.contains(ext)) return (Icons.table_chart_rounded, _green);
    if (ext.isEmpty) return (Icons.folder_rounded, const Color(0xFF0A84FF));
    return (Icons.insert_drive_file_rounded, _dim);
  }

  // --- Namoz ----------------------------------------------------------------

  Widget _prayerTab() {
    final list = prayers.today.value;
    if (list.isEmpty) {
      return const Center(
        child: Text("Namoz vaqtlari yuklanmoqda...\nInternet aloqasini tekshiring",
            textAlign: TextAlign.center, style: TextStyle(color: _dim, fontSize: 12)),
      );
    }
    final next = prayers.next();
    final now = DateTime.now();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(prayers.cityName.value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(width: 8),
        Text('${now.day}-${_months[now.month - 1]}, ${_weekdays[now.weekday - 1]}',
            style: const TextStyle(color: _dim, fontSize: 12)),
      ]),
      const SizedBox(height: 10),
      Expanded(
        child: Row(children: [
          for (final p in list)
            Expanded(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: next?.name == p.name && next?.time == p.time ? _teal.withValues(alpha: 0.18) : _card,
                  borderRadius: BorderRadius.circular(14),
                  border: next?.name == p.name && next?.time == p.time ? Border.all(color: _teal.withValues(alpha: 0.6)) : null,
                ),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(p.name, style: TextStyle(color: p.time.isBefore(now) ? _dim : Colors.white, fontSize: 12)),
                  const SizedBox(height: 4),
                  Text(fmtTime(p.time),
                      style: TextStyle(
                          color: p.time.isBefore(now) ? _dim : Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
        ]),
      ),
    ]);
  }

  static const _months = [
    'yanvar', 'fevral', 'mart', 'aprel', 'may', 'iyun',
    'iyul', 'avgust', 'sentabr', 'oktabr', 'noyabr', 'dekabr'
  ];
  static const _weekdays = ['dushanba', 'seshanba', 'chorshanba', 'payshanba', 'juma', 'shanba', 'yakshanba'];

  // --- Sozlamalar -----------------------------------------------------------

  Widget _settingsTab() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('Shahar (namoz vaqtlari uchun)', style: TextStyle(color: _dim, fontSize: 11)),
      const SizedBox(height: 6),
      SizedBox(
        height: 28,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final c in cities)
            GestureDetector(
              onTap: () => prayers.setCity(c.name),
              child: Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: prayers.cityName.value == c.name ? _teal.withValues(alpha: 0.25) : _card,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(c.name,
                    style: TextStyle(color: prayers.cityName.value == c.name ? _teal : Colors.white, fontSize: 12)),
              ),
            ),
        ]),
      ),
      const SizedBox(height: 10),
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
        const Text('Dinamik Orol 1.0', style: TextStyle(color: Colors.white24, fontSize: 11)),
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
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12))),
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 34, height: 20,
            padding: const EdgeInsets.all(2),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(color: value ? _green : Colors.white24, borderRadius: BorderRadius.circular(10)),
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
          decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
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
    final color = charging ? _green : (percent <= 20 ? const Color(0xFFFF453A) : Colors.white);
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
