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
