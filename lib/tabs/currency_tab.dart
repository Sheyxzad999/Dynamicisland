import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../native.dart';
import '../services/currency.dart';
import '../ui.dart';

class CurrencyTab extends StatefulWidget {
  const CurrencyTab({super.key});
  @override
  State<CurrencyTab> createState() => _CurrencyTabState();
}

class _CurrencyTabState extends State<CurrencyTab> {
  final svc = CurrencyService.instance;
  final ctrl = TextEditingController(text: '100');
  final focus = FocusNode();
  String code = 'USD';
  bool toSom = true; // true: valyuta -> so'm

  @override
  void initState() {
    super.initState();
    svc.refresh();
    SharedPreferences.getInstance().then((p) {
      if (mounted) setState(() => code = p.getString('currencyCode') ?? 'USD');
    });
    focus.addListener(() {
      if (focus.hasFocus) Native.instance.focusKeyboard();
    });
  }

  @override
  void dispose() {
    ctrl.dispose();
    focus.dispose();
    super.dispose();
  }

  double get amount => double.tryParse(ctrl.text.replaceAll(' ', '').replaceAll(',', '.')) ?? 0;

  void _pick(String c) {
    setState(() => code = c);
    SharedPreferences.getInstance().then((p) => p.setString('currencyCode', c));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Rate>>(
      valueListenable: svc.rates,
      builder: (_, rates, _) {
        if (rates.isEmpty) {
          return const Center(
            child: Text('Kurslar yuklanmoqda...\nInternet aloqasini tekshiring',
                textAlign: TextAlign.center, style: TextStyle(color: kDim, fontSize: 12)),
          );
        }
        final rate = svc.byCode(code) ?? rates.first;
        final result = toSom ? amount * rate.rate : (rate.rate > 0 ? amount / rate.rate : 0.0);
        final resultText = toSom
            ? '${formatMoney(result, decimals: 0)} so‘m'
            : '${formatMoney(result)} ${rate.code}';
        return Row(children: [
          // Kalkulyator
          Expanded(
            flex: 5,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: glassTile(radius: 12),
                    child: Row(children: [
                      Expanded(
                        child: TextField(
                          controller: ctrl,
                          focusNode: focus,
                          onTap: () => Native.instance.focusKeyboard(),
                          onChanged: (_) => setState(() {}),
                          inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9 .,]'))],
                          style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
                          cursorColor: kGreen,
                          decoration: const InputDecoration(border: InputBorder.none, isCollapsed: true),
                        ),
                      ),
                      Text(toSom ? rate.code : 'so‘m', style: const TextStyle(color: kDim, fontSize: 13)),
                    ]),
                  ),
                ),
                const SizedBox(width: 8),
                Tap(
                  tooltip: 'Yo‘nalishni almashtirish',
                  onTap: () => setState(() => toSom = !toSom),
                  child: Container(
                    width: 40, height: 40,
                    decoration: glassTile(radius: 12, tint: kGreen, active: true),
                    child: const Icon(Icons.swap_horiz_rounded, color: kGreen, size: 20),
                  ),
                ),
              ]),
              const SizedBox(height: 10),
              Tap(
                tooltip: 'Nusxalash',
                onTap: () => Native.instance.copyText(resultText.replaceAll(' so‘m', '').replaceAll(' ${rate.code}', '')),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text('= $resultText',
                      style: const TextStyle(color: kGreen, fontSize: 24, fontWeight: FontWeight.w700)),
                ),
              ),
              Text('1 ${rate.code} = ${formatMoney(rate.rate)} so‘m  ·  Markaziy bank, ${svc.date.value}',
                  style: const TextStyle(color: kDim, fontSize: 11)),
              const Spacer(),
              Wrap(spacing: 5, runSpacing: 5, children: [
                for (final r in rates.take(8))
                  Tap(
                    onTap: () => _pick(r.code),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: glassTile(radius: 10, tint: r.code == rate.code ? kGreen : null, active: r.code == rate.code),
                      child: Text('${currencyFlags[r.code]} ${r.code}',
                          style: TextStyle(color: r.code == rate.code ? kGreen : Colors.white, fontSize: 11)),
                    ),
                  ),
              ]),
            ]),
          ),
          Container(width: 1, margin: const EdgeInsets.symmetric(horizontal: 14), color: Colors.white10),
          // Kurslar ro'yxati
          SizedBox(
            width: 210,
            child: ListView(children: [
              for (final r in rates)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(children: [
                    Text('${currencyFlags[r.code]} ', style: const TextStyle(fontSize: 13)),
                    SizedBox(width: 36, child: Text(r.code, style: const TextStyle(color: Colors.white, fontSize: 12))),
                    Expanded(
                      child: Text(formatMoney(r.rate),
                          textAlign: TextAlign.right,
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                    SizedBox(
                      width: 62,
                      child: Text(
                        '${r.diff >= 0 ? '▲' : '▼'} ${formatMoney(r.diff.abs())}',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: r.diff >= 0 ? kGreen : kRed, fontSize: 10),
                      ),
                    ),
                  ]),
                ),
            ]),
          ),
        ]);
      },
    );
  }
}
