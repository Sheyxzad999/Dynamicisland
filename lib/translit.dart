/// O'zbek tili uchun lotin ↔ kirill o'girgich.
library;

const _vowelsLat = 'aeiouAEIOU';
const _vowelsCyr = 'аеёиоуўэюяАЕЁИОУЎЭЮЯ';
const _apostrophes = "'‘’`ʻʼ";

final _cyrRe = RegExp('[а-яА-ЯёЁўЎқҚғҒҳҲ]');

bool isCyrillic(String s) => _cyrRe.hasMatch(s);

/// Matn qaysi alifboda bo'lsa, boshqasiga o'giradi.
String autoTranslit(String s) => isCyrillic(s) ? toLatin(s) : toCyrillic(s);

bool _isUpper(String c) => c.toUpperCase() == c && c.toLowerCase() != c;
bool _isLetter(String c) => c.toUpperCase() != c.toLowerCase();

/// Harf katta bo'lsa, natijani ham katta qiladi (to'liq katta so'zlarda butunlay).
String _case(String out, String first, String? next) {
  if (!_isUpper(first)) return out;
  final wholeUpper = next != null && _isLetter(next) && _isUpper(next);
  if (out.length == 1 || wholeUpper) return out.toUpperCase();
  return out[0].toUpperCase() + out.substring(1);
}

const _latMap = {
  'a': 'а', 'b': 'б', 'd': 'д', 'f': 'ф', 'g': 'г', 'h': 'ҳ', 'i': 'и', 'j': 'ж',
  'k': 'к', 'l': 'л', 'm': 'м', 'n': 'н', 'o': 'о', 'p': 'п', 'q': 'қ', 'r': 'р',
  's': 'с', 't': 'т', 'u': 'у', 'v': 'в', 'x': 'х', 'y': 'й', 'z': 'з', 'c': 'с', 'w': 'в',
};

String toCyrillic(String s) {
  final b = StringBuffer();
  var i = 0;
  String at(int k) => k < s.length ? s[k] : '';
  while (i < s.length) {
    final c = s[i];
    final l = c.toLowerCase();
    final n = at(i + 1).toLowerCase();
    final prev = i > 0 ? s[i - 1] : '';

    // o‘, g‘
    if ((l == 'o' || l == 'g') && n.isNotEmpty && _apostrophes.contains(n)) {
      b.write(_case(l == 'o' ? 'ў' : 'ғ', c, at(i + 2)));
      i += 2;
      continue;
    }
    // sh, ch
    if ((l == 's' || l == 'c') && n == 'h') {
      b.write(_case(l == 's' ? 'ш' : 'ч', c, at(i + 1)));
      i += 2;
      continue;
    }
    // yo, yu, ya, ye
    if (l == 'y' && 'ouae'.contains(n) && n.isNotEmpty) {
      // yo‘ -> йў
      if (n == 'o' && _apostrophes.contains(at(i + 2)) && at(i + 2).isNotEmpty) {
        b.write(_case('й', c, at(i + 1)));
        i += 1;
        continue;
      }
      const m = {'o': 'ё', 'u': 'ю', 'a': 'я', 'e': 'е'};
      b.write(_case(m[n]!, c, at(i + 1)));
      i += 2;
      continue;
    }
    // e: so'z boshida va unlidan keyin э
    if (l == 'e') {
      final start = prev.isEmpty || !_isLetter(prev) || _vowelsLat.contains(prev);
      b.write(_case(start ? 'э' : 'е', c, n));
      i += 1;
      continue;
    }
    // tutuq belgisi
    if (_apostrophes.contains(c) && _isLetter(prev) && _isLetter(at(i + 1))) {
      b.write('ъ');
      i += 1;
      continue;
    }
    final r = _latMap[l];
    b.write(r == null ? c : _case(r, c, at(i + 1)));
    i += 1;
  }
  return b.toString();
}

const _cyrMap = {
  'а': 'a', 'б': 'b', 'в': 'v', 'г': 'g', 'ғ': 'g‘', 'д': 'd', 'ё': 'yo', 'ж': 'j',
  'з': 'z', 'и': 'i', 'й': 'y', 'к': 'k', 'қ': 'q', 'л': 'l', 'м': 'm', 'н': 'n',
  'о': 'o', 'п': 'p', 'р': 'r', 'с': 's', 'т': 't', 'у': 'u', 'ў': 'o‘', 'ф': 'f',
  'х': 'x', 'ҳ': 'h', 'ч': 'ch', 'ш': 'sh', 'щ': 'sh', 'ъ': '’', 'ь': '', 'ы': 'i',
  'э': 'e', 'ю': 'yu', 'я': 'ya',
};

String toLatin(String s) {
  final b = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    final c = s[i];
    final l = c.toLowerCase();
    final prev = i > 0 ? s[i - 1] : '';
    final next = i + 1 < s.length ? s[i + 1] : null;
    String? r;
    if (l == 'е') {
      final start = prev.isEmpty || !_isLetter(prev) || _vowelsCyr.contains(prev) || 'ъьЪЬ'.contains(prev);
      r = start ? 'ye' : 'e';
    } else if (l == 'ц') {
      r = prev.isNotEmpty && _vowelsCyr.contains(prev) ? 'ts' : 's';
    } else {
      r = _cyrMap[l];
    }
    b.write(r == null ? c : (r.isEmpty ? '' : _case(r, c, next)));
  }
  return b.toString();
}
