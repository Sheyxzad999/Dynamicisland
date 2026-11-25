import 'package:flutter/foundation.dart';

import '../native.dart';

/// Mac kalendaridagi tadbirlar (EventKit orqali).
class CalendarService {
  CalendarService._();
  static final instance = CalendarService._();

  final events = ValueNotifier<List<CalendarEvent>>([]);
  final status = ValueNotifier<String>('notDetermined');

  Future<void> init() async {
    Native.instance.calendarChanged.addListener(refresh);
    await refresh();
  }

  Future<void> refresh() async {
    if (kDemo.isNotEmpty) {
      // Demo rejim: haqiqiy kalendar o'qilmaydi
      final d = DateTime.now();
      final t = DateTime(d.year, d.month, d.day);
      status.value = 'granted';
      events.value = [
        CalendarEvent('Dizayn ko‘rib chiqish', t.add(const Duration(hours: 16)), t.add(const Duration(hours: 17)), false, 'Zoom', 0xFFBF5AF2),
        CalendarEvent('Mijoz bilan qo‘ng‘iroq', t.add(const Duration(hours: 18, minutes: 30)), t.add(const Duration(hours: 19)), false, '', 0xFF0A84FF),
        CalendarEvent('Sport zal', t.add(const Duration(days: 1, hours: 8)), t.add(const Duration(days: 1, hours: 9)), false, '', 0xFF34C759),
        CalendarEvent('Reliz: Dinamik Orol 1.3', t.add(const Duration(days: 2, hours: 11)), t.add(const Duration(days: 2, hours: 12)), false, '', 0xFFFF9F0A),
      ];
      return;
    }
    try {
      status.value = await Native.instance.calendarStatus();
      if (status.value == 'granted') events.value = await Native.instance.getEvents();
    } catch (_) {}
  }

  Future<void> requestAccess() async {
    try {
      await Native.instance.requestCalendar();
    } catch (_) {}
    await refresh();
  }

  /// Hozir davom etayotgan yoki keyingi (kun bo'yi davom etmaydigan) tadbir.
  CalendarEvent? next([DateTime? at]) {
    final now = at ?? DateTime.now();
    for (final e in events.value) {
      if (!e.allDay && e.end.isAfter(now)) return e;
    }
    return null;
  }
}
