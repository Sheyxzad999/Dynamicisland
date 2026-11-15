import 'package:flutter/material.dart';

import '../native.dart';
import '../services/calendar.dart';
import '../ui.dart';

class CalendarTab extends StatelessWidget {
  const CalendarTab({super.key});

  @override
  Widget build(BuildContext context) {
    final svc = CalendarService.instance;
    return ValueListenableBuilder<String>(
      valueListenable: svc.status,
      builder: (_, status, _) {
        if (status != 'granted') {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.event_rounded, color: kPurple, size: 32),
              const SizedBox(height: 6),
              Text(
                status == 'denied'
                    ? 'Kalendarga ruxsat berilmagan.\nTizim sozlamalari → Maxfiylik → Kalendarlar bo‘limidan yoqing'
                    : 'Uchrashuvlaringizni ko‘rish uchun kalendarga ruxsat bering',
                textAlign: TextAlign.center,
                style: const TextStyle(color: kDim, fontSize: 12),
              ),
              const SizedBox(height: 10),
              if (status != 'denied') Pill('Ruxsat berish', kPurple, svc.requestAccess, icon: Icons.lock_open_rounded),
            ]),
          );
        }
        return ValueListenableBuilder<List<CalendarEvent>>(
          valueListenable: svc.events,
          builder: (_, events, _) {
            final now = DateTime.now();
            final upcoming = events.where((e) => e.end.isAfter(now)).toList();
            if (upcoming.isEmpty) {
              return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.event_available_rounded, color: kGreen, size: 32),
                  const SizedBox(height: 6),
                  const Text('Yaqin 3 kunda uchrashuvlar yo‘q', style: TextStyle(color: kDim, fontSize: 13)),
                  const SizedBox(height: 10),
                  Pill('Kalendarni ochish', kPurple, Native.instance.openCalendar),
                ]),
              );
            }
            final rows = <Widget>[];
            String? lastDay;
            for (final e in upcoming) {
              final day = dayLabel(e.start.isBefore(now) ? now : e.start);
              if (day != lastDay) {
                lastDay = day;
                rows.add(Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 4),
                  child: Text(day, style: const TextStyle(color: kDim, fontSize: 11, fontWeight: FontWeight.w600)),
                ));
              }
              rows.add(_event(e, now));
            }
            return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: ListView(children: rows)),
              const SizedBox(width: 10),
              Tap(
                tooltip: 'Kalendarni ochish',
                onTap: Native.instance.openCalendar,
                child: const Icon(Icons.open_in_new_rounded, size: 16, color: kDim),
              ),
            ]);
          },
        );
      },
    );
  }

  Widget _event(CalendarEvent e, DateTime now) {
    final live = e.start.isBefore(now) && e.end.isAfter(now);
    final color = Color(e.color);
    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: live ? color.withValues(alpha: 0.18) : kCard,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        Container(width: 3, height: 26, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(e.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            Text(
              [
                e.allDay ? 'Kun bo‘yi' : '${fmtTime(e.start)} – ${fmtTime(e.end)}',
                if (e.location.isNotEmpty) e.location,
              ].join('  ·  '),
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: kDim, fontSize: 10.5),
            ),
          ]),
        ),
        if (!e.allDay)
          Text(
            live ? 'Hozir' : (e.start.difference(now).inHours < 24 ? '${fmtLeft(e.start.difference(now))}dan keyin' : ''),
            style: TextStyle(color: live ? color : kDim, fontSize: 10.5),
          ),
      ]),
    );
  }
}
