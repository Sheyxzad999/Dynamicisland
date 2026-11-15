import 'package:dinamik_orol/services/currency.dart';
import 'package:dinamik_orol/translit.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Lotin → Kirill', () {
    final cases = {
      'Salom': 'Салом',
      'O‘zbekiston': 'Ўзбекистон',
      "g'alaba": 'ғалаба',
      'Shahar': 'Шаҳар',
      'choy': 'чой',
      'yangi': 'янги',
      'yo‘l': 'йўл',
      'Ertaga': 'Эртага',
      'mehr': 'меҳр',
      'qoida': 'қоида',
      "ma'no": 'маъно',
      'TOSHKENT': 'ТОШКЕНТ',
    };
    cases.forEach((lat, cyr) => test(lat, () => expect(toCyrillic(lat), cyr)));
  });

  group('Kirill → Lotin', () {
    final cases = {
      'Салом': 'Salom',
      'Ўзбекистон': 'O‘zbekiston',
      'Шаҳар': 'Shahar',
      'Ер': 'Yer',
      'келди': 'keldi',
      'маъно': 'ma’no',
      'Ғалаба': 'G‘alaba',
      'ЧОЙ': 'CHOY',
    };
    cases.forEach((cyr, lat) => test(cyr, () => expect(toLatin(cyr), lat)));
  });

  test('Avtomatik yo‘nalish', () {
    expect(autoTranslit('Салом дунё'), 'Salom dunyo');
    expect(autoTranslit('Salom dunyo'), 'Салом дунё');
  });

  test('Pul formati', () {
    expect(formatMoney(12014.37), '12 014,37');
    expect(formatMoney(1201437, decimals: 0), '1 201 437');
    expect(formatMoney(146.10), '146,1');
  });
}
