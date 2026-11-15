import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class City {
  final String name;
  final double lat;
  final double lng;
  const City(this.name, this.lat, this.lng);
}

const cities = <City>[
  City('Toshkent', 41.2995, 69.2401),
  City('Samarqand', 39.6542, 66.9597),
  City('Buxoro', 39.7747, 64.4286),
  City('Andijon', 40.7821, 72.3442),
  City("Farg'ona", 40.3864, 71.7864),
  City("Qo'qon", 40.5286, 70.9425),
  City('Namangan', 40.9983, 71.6726),
  City('Qarshi', 38.8606, 65.7891),
  City('Navoiy', 40.0844, 65.3792),
  City('Jizzax', 40.1158, 67.8422),
  City('Guliston', 40.4897, 68.7842),
  City('Termiz', 37.2242, 67.2783),
  City('Urganch', 41.5500, 60.6333),
  City('Nukus', 42.4531, 59.6103),
];

class Prayer {
  final String name;
  final DateTime time;
  const Prayer(this.name, this.time);
}

const _names = {
  'Fajr': 'Bomdod',
  'Sunrise': 'Quyosh',
  'Dhuhr': 'Peshin',
  'Asr': 'Asr',
  'Maghrib': 'Shom',
  'Isha': 'Xufton',
};

/// Namoz vaqtlari (AlAdhan, Hanafiy mazhabi bo'yicha asr).
class PrayerService {
  PrayerService._();
  static final instance = PrayerService._();

  final today = ValueNotifier<List<Prayer>>([]);
  final cityName = ValueNotifier<String>('Toshkent');
  String _loadedKey = '';

  City get city => cities.firstWhere((c) => c.name == cityName.value, orElse: () => cities.first);

  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    cityName.value = p.getString('city') ?? 'Toshkent';
    await refresh();
  }

  Future<void> setCity(String name) async {
    cityName.value = name;
    final p = await SharedPreferences.getInstance();
    await p.setString('city', name);
    _loadedKey = '';
    await refresh();
  }

  String _key(DateTime d) => '${city.name}-${d.year}-${d.month}-${d.day}';

  /// Kerak bo'lsa (yangi kun yoki shahar) vaqtlarni qayta yuklaydi.
  Future<void> refresh() async {
    final now = DateTime.now();
    final key = _key(now);
    if (key == _loadedKey && today.value.isNotEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    Map<String, dynamic>? timings;
    final cached = prefs.getString('prayer:$key');
    if (cached != null) {
      timings = jsonDecode(cached) as Map<String, dynamic>;
    } else {
      try {
        final date = '${now.day.toString().padLeft(2, '0')}-'
            '${now.month.toString().padLeft(2, '0')}-${now.year}';
        final uri = Uri.parse('https://api.aladhan.com/v1/timings/$date'
            '?latitude=${city.lat}&longitude=${city.lng}&method=3&school=1');
        final r = await http.get(uri).timeout(const Duration(seconds: 15));
        if (r.statusCode == 200) {
          timings = (jsonDecode(r.body)['data']['timings'] as Map).cast<String, dynamic>();
          await prefs.setString('prayer:$key', jsonEncode(timings));
        }
      } catch (_) {}
    }
    if (timings == null) return;
    final list = <Prayer>[];
    _names.forEach((k, uz) {
      final raw = (timings![k] as String?)?.split(' ').first;
      if (raw == null) return;
      final hm = raw.split(':');
      list.add(Prayer(uz, DateTime(now.year, now.month, now.day, int.parse(hm[0]), int.parse(hm[1]))));
    });
    _loadedKey = key;
    today.value = list;
  }

  /// Keyingi namoz (Quyosh ham kiritiladi, chunki bomdod vaqti tugashini bildiradi).
  Prayer? next([DateTime? at]) {
    final now = at ?? DateTime.now();
    for (final p in today.value) {
      if (p.time.isAfter(now)) return p;
    }
    if (today.value.isNotEmpty) {
      final f = today.value.first;
      return Prayer(f.name, f.time.add(const Duration(days: 1)));
    }
    return null;
  }
}
