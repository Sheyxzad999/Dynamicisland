import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class BatteryInfo {
  final bool available;
  final int percent;
  final bool charging;
  final bool plugged;
  final int minutesToFull;
  final int minutesToEmpty;

  const BatteryInfo({
    this.available = false,
    this.percent = 0,
    this.charging = false,
    this.plugged = false,
    this.minutesToFull = -1,
    this.minutesToEmpty = -1,
  });

  factory BatteryInfo.fromMap(Map m) => BatteryInfo(
        available: m['available'] == true,
        percent: (m['percent'] ?? 0) as int,
        charging: m['charging'] == true,
        plugged: m['plugged'] == true,
        minutesToFull: (m['minutesToFull'] ?? -1) as int,
        minutesToEmpty: (m['minutesToEmpty'] ?? -1) as int,
      );
}

class MediaInfo {
  final String state; // playing | paused | none
  final String title;
  final String artist;
  final String artwork;
  final double position;
  final double duration;
  final String source;
  final DateTime receivedAt;

  MediaInfo({
    this.state = 'none',
    this.title = '',
    this.artist = '',
    this.artwork = '',
    this.position = 0,
    this.duration = 0,
    this.source = '',
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  bool get isPlaying => state == 'playing';
  bool get hasTrack => state == 'playing' || state == 'paused';

  /// Hozirgi pozitsiya (oxirgi xabardan beri o'tgan vaqt hisobga olinadi).
  double get livePosition {
    if (!isPlaying) return position;
    final p = position + DateTime.now().difference(receivedAt).inMilliseconds / 1000;
    return duration > 0 ? p.clamp(0, duration) : p;
  }

  factory MediaInfo.fromMap(Map m) => MediaInfo(
        state: (m['state'] ?? 'none') as String,
        title: (m['title'] ?? '') as String,
        artist: (m['artist'] ?? '') as String,
        artwork: (m['artwork'] ?? '') as String,
        position: ((m['position'] ?? 0) as num).toDouble(),
        duration: ((m['duration'] ?? 0) as num).toDouble(),
        source: (m['source'] ?? '') as String,
      );
}

class ClipEvent {
  final String text;
  final String app;
  const ClipEvent(this.text, this.app);
}

class CalendarEvent {
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String location;
  final int color;
  const CalendarEvent(this.title, this.start, this.end, this.allDay, this.location, this.color);

  factory CalendarEvent.fromMap(Map m) => CalendarEvent(
        (m['title'] ?? '') as String,
        DateTime.fromMillisecondsSinceEpoch(((m['start'] ?? 0) as num).toInt()),
        DateTime.fromMillisecondsSinceEpoch(((m['end'] ?? 0) as num).toInt()),
        m['allDay'] == true,
        (m['location'] ?? '') as String,
        0xFF000000 | int.parse((m['color'] ?? '0A84FF') as String, radix: 16),
      );
}

class NotchInfo {
  final double width;
  final double height;
  final bool hasNotch;
  const NotchInfo({this.width = 190, this.height = 32, this.hasNotch = false});
  factory NotchInfo.fromMap(Map m) => NotchInfo(
        width: ((m['width'] ?? 190) as num).toDouble(),
        height: ((m['height'] ?? 32) as num).toDouble(),
        hasNotch: m['hasNotch'] == true,
      );
}

/// Swift bilan aloqa.
class Native {
  Native._();
  static final instance = Native._();

  static const _ch = MethodChannel('orol/native');

  final hover = ValueNotifier<bool>(false);
  final battery = ValueNotifier<BatteryInfo>(const BatteryInfo());
  final media = ValueNotifier<MediaInfo>(MediaInfo());
  final notch = ValueNotifier<NotchInfo>(const NotchInfo());
  final mic = ValueNotifier<bool>(false);
  final camera = ValueNotifier<bool>(false);
  final calendarChanged = ValueNotifier<int>(0);
  final _clip = StreamController<ClipEvent>.broadcast();
  Stream<ClipEvent> get clipboard => _clip.stream;

  Future<void> init() async {
    _ch.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'hover':
          hover.value = call.arguments == true;
        case 'battery':
          battery.value = BatteryInfo.fromMap(call.arguments as Map);
        case 'media':
          media.value = MediaInfo.fromMap(call.arguments as Map);
        case 'clipboard':
          final m = call.arguments as Map;
          _clip.add(ClipEvent(m['text'] as String, (m['app'] ?? '') as String));
        case 'privacy':
          final m = call.arguments as Map;
          mic.value = m['mic'] == true;
          camera.value = m['camera'] == true;
        case 'calendarChanged':
          calendarChanged.value++;
        case 'screen':
          notch.value = NotchInfo.fromMap(call.arguments as Map);
      }
      return null;
    });
    try {
      notch.value = NotchInfo.fromMap(await _ch.invokeMethod('getScreen') as Map);
      battery.value = BatteryInfo.fromMap(await _ch.invokeMethod('getBattery') as Map);
    } catch (_) {}
  }

  Future<void> setIslandSize(Size s) =>
      _ch.invokeMethod('setIslandSize', {'width': s.width, 'height': s.height});
  Future<void> media_(String command) => _ch.invokeMethod('media', {'command': command});
  Future<void> openFile(String path) => _ch.invokeMethod('openFile', {'path': path});
  Future<void> revealFile(String path) => _ch.invokeMethod('revealFile', {'path': path});
  Future<bool> fileExists(String path) async =>
      (await _ch.invokeMethod('fileExists', {'path': path})) == true;
  Future<void> playSound(String name) => _ch.invokeMethod('playSound', {'name': name});
  Future<bool> getLaunchAtLogin() async =>
      (await _ch.invokeMethod('getLaunchAtLogin')) == true;
  Future<bool> setLaunchAtLogin(bool v) async =>
      (await _ch.invokeMethod('setLaunchAtLogin', {'enabled': v})) == true;
  Future<void> copyText(String text) => _ch.invokeMethod('copyText', {'text': text});
  Future<void> focusKeyboard() => _ch.invokeMethod('focusKeyboard');
  Future<void> releaseKeyboard() => _ch.invokeMethod('releaseKeyboard');
  Future<void> action(String name) => _ch.invokeMethod('action', {'name': name});
  Future<String> calendarStatus() async => (await _ch.invokeMethod('calendarStatus')) as String;
  Future<bool> requestCalendar() async => (await _ch.invokeMethod('requestCalendar')) == true;
  Future<void> openCalendar() => _ch.invokeMethod('openCalendar');
  Future<List<CalendarEvent>> getEvents() async {
    final list = (await _ch.invokeMethod('getEvents')) as List? ?? [];
    return list.map((e) => CalendarEvent.fromMap(e as Map)).toList();
  }

  Future<void> quit() => _ch.invokeMethod('quit');
}
