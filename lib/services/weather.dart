import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../i18n.dart';
import '../prayer.dart';

class DayForecast {
  final DateTime date;
  final int code;
  final double max;
  final double min;
  const DayForecast(this.date, this.code, this.max, this.min);
}

class Weather {
  final double temp;
  final double feels;
  final int code;
  final bool isDay;
  final double wind;
  final int humidity;
  final List<DayForecast> days;
  final String city;
  const Weather(this.temp, this.feels, this.code, this.isDay, this.wind, this.humidity, this.days, this.city);
}

/// WMO ob-havo kodi -> o'zbekcha tavsif.
String weatherText(int c) {
  if (c == 0) return tr('Ochiq osmon', 'Clear sky');
  if (c <= 2) return tr('Qisman bulutli', 'Partly cloudy');
  if (c == 3) return tr('Bulutli', 'Cloudy');
  if (c <= 48) return tr('Tuman', 'Fog');
  if (c <= 57) return tr('Shivalama yomgʻir', 'Drizzle');
  if (c <= 67) return tr('Yomgʻir', 'Rain');
  if (c <= 77) return tr('Qor', 'Snow');
  if (c <= 82) return tr('Jala', 'Showers');
  if (c <= 86) return tr('Qor yogʻishi', 'Snow showers');
  return tr('Momaqaldiroq', 'Thunderstorm');
}

IconData weatherIcon(int c, {bool day = true}) {
  if (c == 0) return day ? Icons.wb_sunny_rounded : Icons.nightlight_round;
  if (c <= 2) return day ? Icons.wb_cloudy_rounded : Icons.nights_stay_rounded;
  if (c == 3) return Icons.cloud_rounded;
  if (c <= 48) return Icons.foggy;
  if (c <= 67 || (c >= 80 && c <= 82)) return Icons.water_drop_rounded;
  if (c <= 77 || c <= 86) return Icons.ac_unit_rounded;
  return Icons.thunderstorm_rounded;
}

Color weatherColor(int c, {bool day = true}) {
  if (c == 0) return day ? const Color(0xFFFFD60A) : const Color(0xFFBF9BFF);
  if (c <= 3) return const Color(0xFFD1D1D6);
  if (c <= 67 || (c >= 80 && c <= 82)) return const Color(0xFF64D2FF);
  if (c <= 86) return Colors.white;
  return const Color(0xFFFF9F0A);
}

/// Open-Meteo xizmatidan ob-havo (kalit talab qilinmaydi).
class WeatherService {
  WeatherService._();
  static final instance = WeatherService._();

  final current = ValueNotifier<Weather?>(null);
  DateTime? _loadedAt;
  String _city = '';

  Future<void> refresh({bool force = false}) async {
    final city = PrayerService.instance.city;
    if (!force &&
        city.name == _city &&
        _loadedAt != null &&
        DateTime.now().difference(_loadedAt!).inMinutes < 20) {
      return;
    }
    try {
      final uri = Uri.parse('https://api.open-meteo.com/v1/forecast'
          '?latitude=${city.lat}&longitude=${city.lng}'
          '&current=temperature_2m,weather_code,is_day,wind_speed_10m,relative_humidity_2m,apparent_temperature'
          '&daily=weather_code,temperature_2m_max,temperature_2m_min&timezone=auto&forecast_days=5');
      final r = await http.get(uri).timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) return;
      final d = jsonDecode(r.body);
      final c = d['current'];
      final daily = d['daily'];
      final days = <DayForecast>[];
      for (var i = 0; i < (daily['time'] as List).length; i++) {
        days.add(DayForecast(
          DateTime.parse(daily['time'][i] as String),
          (daily['weather_code'][i] as num).toInt(),
          (daily['temperature_2m_max'][i] as num).toDouble(),
          (daily['temperature_2m_min'][i] as num).toDouble(),
        ));
      }
      current.value = Weather(
        (c['temperature_2m'] as num).toDouble(),
        (c['apparent_temperature'] as num).toDouble(),
        (c['weather_code'] as num).toInt(),
        c['is_day'] == 1,
        (c['wind_speed_10m'] as num).toDouble(),
        (c['relative_humidity_2m'] as num).toInt(),
        days,
        city.name,
      );
      _city = city.name;
      _loadedAt = DateTime.now();
    } catch (_) {}
  }
}
