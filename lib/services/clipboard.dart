import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../native.dart';

class ClipItem {
  final String text;
  final String app;
  final DateTime time;
  final bool pinned;
  const ClipItem(this.text, this.app, this.time, {this.pinned = false});

  ClipItem copyWith({bool? pinned}) => ClipItem(text, app, time, pinned: pinned ?? this.pinned);

  Map<String, dynamic> toJson() =>
      {'t': text, 'a': app, 'd': time.millisecondsSinceEpoch, 'p': pinned};
  factory ClipItem.fromJson(Map m) => ClipItem(
        m['t'] as String,
        (m['a'] ?? '') as String,
        DateTime.fromMillisecondsSinceEpoch(m['d'] as int),
        pinned: m['p'] == true,
      );
}

/// Nusxalangan matnlar tarixi (oxirgi 50 ta + qadalganlar).
class ClipboardStore {
  ClipboardStore._();
  static final instance = ClipboardStore._();
  static const limit = 50;

  final items = ValueNotifier<List<ClipItem>>([]);
  StreamSubscription<ClipEvent>? _sub;

  Future<void> init() async {
    if (kDemo.isNotEmpty) {
      // Demo rejim: haqiqiy tarix o'qilmaydi va saqlanmaydi
      final now = DateTime.now();
      items.value = [
        ClipItem('https://github.com/Sheyxzad999/Dynamicisland', 'Safari', now.subtract(const Duration(minutes: 2))),
        ClipItem('Ertaga 10:00 — jamoa bilan uchrashuv', 'Notes', now.subtract(const Duration(minutes: 9)), pinned: true),
        ClipItem('#F0875A', 'Figma', now.subtract(const Duration(minutes: 24))),
        ClipItem('Ўзбекистон Республикаси', 'Telegram', now.subtract(const Duration(hours: 1))),
        ClipItem('flutter build macos --release', 'Terminal', now.subtract(const Duration(hours: 3))),
      ];
      return;
    }
    final p = await SharedPreferences.getInstance();
    final raw = p.getString('clipboard');
    if (raw != null) {
      try {
        items.value = (jsonDecode(raw) as List).map((e) => ClipItem.fromJson(e as Map)).toList();
      } catch (_) {}
    }
    _sub ??= Native.instance.clipboard.listen((e) => add(e.text, e.app));
  }

  void add(String text, String app) {
    final list = [...items.value];
    final old = list.indexWhere((x) => x.text == text);
    var pinned = false;
    if (old >= 0) pinned = list.removeAt(old).pinned;
    list.insert(0, ClipItem(text, app, DateTime.now(), pinned: pinned));
    var unpinned = 0;
    list.removeWhere((x) => !x.pinned && ++unpinned > limit);
    items.value = list;
    _save();
  }

  void togglePin(ClipItem item) {
    items.value = [for (final x in items.value) x.text == item.text ? x.copyWith(pinned: !x.pinned) : x];
    _save();
  }

  void remove(ClipItem item) {
    items.value = items.value.where((x) => x.text != item.text).toList();
    _save();
  }

  void clearUnpinned() {
    items.value = items.value.where((x) => x.pinned).toList();
    _save();
  }

  Future<void> _save() async {
    if (kDemo.isNotEmpty) return;
    final p = await SharedPreferences.getInstance();
    await p.setString('clipboard', jsonEncode(items.value.map((e) => e.toJson()).toList()));
  }
}
