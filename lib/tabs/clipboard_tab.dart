import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../native.dart';
import '../services/clipboard.dart';
import '../translit.dart';
import '../ui.dart';

class ClipboardTab extends StatefulWidget {
  const ClipboardTab({super.key});
  @override
  State<ClipboardTab> createState() => _ClipboardTabState();
}

class _ClipboardTabState extends State<ClipboardTab> {
  final store = ClipboardStore.instance;
  String? flash; // oxirgi nusxalangan element matni
  Timer? _t;

  void _copy(String text, {String? key}) {
    Native.instance.copyText(text);
    store.add(text, 'Dinamik Orol');
    setState(() => flash = key ?? text);
    _t?.cancel();
    _t = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => flash = null);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<ClipItem>>(
      valueListenable: store.items,
      builder: (_, items, _) {
        if (items.isEmpty) {
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.content_paste_rounded, color: kDim, size: 32),
              const SizedBox(height: 6),
              Text(tr('Hali hech narsa nusxalanmagan', 'Nothing copied yet'), style: const TextStyle(color: kDim, fontSize: 13)),
              Text(tr('Cmd+C bilan nusxalagan matnlaringiz shu yerda saqlanadi', 'Text you copy with Cmd+C is kept here'),
                  style: const TextStyle(color: Colors.white24, fontSize: 11)),
            ]),
          );
        }
        return Column(children: [
          Row(children: [
            Text(tr('${items.length} ta yozuv', '${items.length} items'), style: const TextStyle(color: kDim, fontSize: 12)),
            const Spacer(),
            Text(tr('Bosing: nusxalash  ·  Aа: lotin↔kirill  ', 'Click: copy  ·  Aа: Latin↔Cyrillic  '), style: const TextStyle(color: Colors.white24, fontSize: 10)),
            Tap(
              onTap: store.clearUnpinned,
              child: Text(tr('Tozalash', 'Clear'), style: const TextStyle(color: kRed, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 6),
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemExtent: 34,
              itemBuilder: (_, i) => _row(items[i]),
            ),
          ),
        ]);
      },
    );
  }

  Widget _row(ClipItem it) {
    final copied = flash == it.text;
    final translitKey = 'tr:${it.text}';
    final oneLine = it.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: glassTile(radius: 10, tint: copied ? kGreen : null, active: copied),
      child: Row(children: [
        if (it.pinned) const Padding(padding: EdgeInsets.only(right: 6), child: Icon(Icons.push_pin, size: 12, color: kOrange)),
        Expanded(
          child: Tap(
            onTap: () => _copy(it.text),
            child: Row(children: [
              Expanded(
                child: Text(copied ? tr('Nusxalandi ✓', 'Copied ✓') : oneLine,
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: copied ? kGreen : Colors.white, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              Text(
                flash == translitKey ? tr('Oʻgirildi ✓', 'Converted ✓') : timeAgo(it.time),
                style: TextStyle(color: flash == translitKey ? kTeal : Colors.white30, fontSize: 10),
              ),
            ]),
          ),
        ),
        const SizedBox(width: 8),
        Tap(
          tooltip: isCyrillic(it.text) ? tr('Lotinga oʻgirib nusxalash', 'Copy as Latin') : tr('Kirillga oʻgirib nusxalash', 'Copy as Cyrillic'),
          onTap: () => _copy(autoTranslit(it.text), key: translitKey),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(color: kTeal.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6)),
            child: const Text('Aа', style: TextStyle(color: kTeal, fontSize: 11, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(width: 6),
        Tap(
          tooltip: it.pinned ? tr('Qadashni olib tashlash', 'Unpin') : tr('Qadab qoʻyish', 'Pin'),
          onTap: () => store.togglePin(it),
          child: Icon(it.pinned ? Icons.push_pin : Icons.push_pin_outlined, size: 14, color: it.pinned ? kOrange : kDim),
        ),
        const SizedBox(width: 6),
        Tap(onTap: () => store.remove(it), child: const Icon(Icons.close_rounded, size: 14, color: kDim)),
      ]),
    );
  }
}
