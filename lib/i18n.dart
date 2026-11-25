import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Interfeys tili: 'uz' (oʻzbekcha, lotin) yoki 'en' (inglizcha).
final appLang = ValueNotifier<String>('uz');

bool get isEn => appLang.value == 'en';

/// Ikki tilli matn: `tr('Salom', 'Hello')`.
String tr(String uz, String en) => isEn ? en : uz;

Future<void> loadLang() async {
  final p = await SharedPreferences.getInstance();
  appLang.value = p.getString('lang') ?? 'uz';
}

Future<void> setLang(String lang) async {
  appLang.value = lang;
  final p = await SharedPreferences.getInstance();
  await p.setString('lang', lang);
}

const _prayerEn = {
  'Bomdod': 'Fajr', 'Quyosh': 'Sunrise', 'Peshin': 'Dhuhr',
  'Asr': 'Asr', 'Shom': 'Maghrib', 'Xufton': 'Isha',
};

/// Namoz nomi joriy tilda (ichki kalit — oʻzbekcha nom).
String prayerName(String uz) => isEn ? (_prayerEn[uz] ?? uz) : uz;
