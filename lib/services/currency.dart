import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class Rate {
  final String code;
  final String name;
  final double rate; // 1 birlik uchun so'm
  final double diff;
  const Rate(this.code, this.name, this.rate, this.diff);
}

const currencyFlags = {
  'USD': '🇺🇸', 'EUR': '🇪🇺', 'RUB': '🇷🇺', 'KZT': '🇰🇿', 'GBP': '🇬🇧',
  'CNY': '🇨🇳', 'TRY': '🇹🇷', 'KRW': '🇰🇷', 'AED': '🇦🇪', 'JPY': '🇯🇵', 'KGS': '🇰🇬', 'TJS': '🇹🇯',
};

/// O'zbekiston Markaziy banki rasmiy kurslari.
class CurrencyService {
  CurrencyService._();
  static final instance = CurrencyService._();

  final rates = ValueNotifier<List<Rate>>([]);
  final date = ValueNotifier<String>('');
  DateTime? _loadedAt;

  Rate? byCode(String c) {
    for (final r in rates.value) {
      if (r.code == c) return r;
    }
    return null;
  }

  Future<void> refresh({bool force = false}) async {
    if (!force && _loadedAt != null && DateTime.now().difference(_loadedAt!).inMinutes < 60) return;
    final prefs = await SharedPreferences.getInstance();
    String? body;
    try {
      final r = await http
          .get(Uri.parse('https://cbu.uz/uz/arkhiv-kursov-valyut/json/'))
          .timeout(const Duration(seconds: 15));
      if (r.statusCode == 200) {
        body = utf8.decode(r.bodyBytes);
        await prefs.setString('currency', body);
        _loadedAt = DateTime.now();
      }
    } catch (_) {}
    body ??= prefs.getString('currency');
    if (body == null) return;
    final list = <Rate>[];
    for (final e in jsonDecode(body) as List) {
      final code = e['Ccy'] as String;
      if (!currencyFlags.containsKey(code)) continue;
      final nominal = double.tryParse('${e['Nominal']}') ?? 1;
      list.add(Rate(
        code,
        e['CcyNm_UZ'] as String,
        (double.tryParse('${e['Rate']}') ?? 0) / nominal,
        (double.tryParse('${e['Diff']}') ?? 0) / nominal,
      ));
      date.value = e['Date'] as String;
    }
    final order = currencyFlags.keys.toList();
    list.sort((a, b) => order.indexOf(a.code).compareTo(order.indexOf(b.code)));
    rates.value = list;
  }
}

/// 12014.37 -> "12 014,37"
String formatMoney(double v, {int decimals = 2}) {
  final neg = v < 0;
  final fixed = v.abs().toStringAsFixed(decimals);
  final parts = fixed.split('.');
  final intPart = parts[0];
  final b = StringBuffer();
  for (var i = 0; i < intPart.length; i++) {
    if (i > 0 && (intPart.length - i) % 3 == 0) b.write(' ');
    b.write(intPart[i]);
  }
  var frac = parts.length > 1 ? parts[1] : '';
  frac = frac.replaceAll(RegExp(r'0+$'), '');
  return '${neg ? '-' : ''}$b${frac.isEmpty ? '' : ',$frac'}';
}
