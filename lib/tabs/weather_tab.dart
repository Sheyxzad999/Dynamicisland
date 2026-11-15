import 'package:flutter/material.dart';

import '../services/weather.dart';
import '../ui.dart';

class WeatherTab extends StatelessWidget {
  const WeatherTab({super.key});

  @override
  Widget build(BuildContext context) {
    WeatherService.instance.refresh();
    return ValueListenableBuilder<Weather?>(
      valueListenable: WeatherService.instance.current,
      builder: (_, w, _) {
        if (w == null) {
          return const Center(
            child: Text('Ob-havo yuklanmoqda...\nInternet aloqasini tekshiring',
                textAlign: TextAlign.center, style: TextStyle(color: kDim, fontSize: 12)),
          );
        }
        return Row(children: [
          Icon(weatherIcon(w.code, day: w.isDay), size: 64, color: weatherColor(w.code, day: w.isDay)),
          const SizedBox(width: 14),
          SizedBox(
            width: 170,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(w.city, style: const TextStyle(color: kDim, fontSize: 12)),
              Text('${w.temp.round()}°',
                  style: const TextStyle(color: Colors.white, fontSize: 44, fontWeight: FontWeight.w300, height: 1.1)),
              Text(weatherText(w.code), style: const TextStyle(color: Colors.white, fontSize: 13)),
              const SizedBox(height: 4),
              Text('His qilinadi ${w.feels.round()}°  ·  💧 ${w.humidity}%  ·  💨 ${w.wind.round()} km/s',
                  style: const TextStyle(color: kDim, fontSize: 10.5)),
            ]),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Row(children: [
              for (final d in w.days.take(5))
                Expanded(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14)),
                    child: Column(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(_dayName(d.date), style: const TextStyle(color: kDim, fontSize: 11)),
                      Icon(weatherIcon(d.code), color: weatherColor(d.code), size: 24),
                      Text('${d.max.round()}°', style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
                      Text('${d.min.round()}°', style: const TextStyle(color: kDim, fontSize: 12)),
                    ]),
                  ),
                ),
            ]),
          ),
        ]);
      },
    );
  }

  String _dayName(DateTime d) {
    final now = DateTime.now();
    if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Bugun';
    return uzWeekdaysShort[d.weekday - 1];
  }
}
