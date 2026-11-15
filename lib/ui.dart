import 'package:flutter/material.dart';

// Umumiy ranglar
const kGreen = Color(0xFF34C759);
const kOrange = Color(0xFFFF9F0A);
const kTeal = Color(0xFF64D2FF);
const kPurple = Color(0xFFBF5AF2);
const kRed = Color(0xFFFF453A);
const kYellow = Color(0xFFFFD60A);
const kDim = Color(0xFF8E8E93);
const kCard = Color(0xFF1C1C1E);

String two(int n) => n.toString().padLeft(2, '0');

String fmtClock(Duration d) {
  final s = d.inSeconds.clamp(0, 1 << 30);
  final h = s ~/ 3600, m = (s % 3600) ~/ 60, sec = s % 60;
  return h > 0 ? '$h:${two(m)}:${two(sec)}' : '${two(m)}:${two(sec)}';
}

String fmtLeft(Duration d) {
  final m = (d.inSeconds / 60).ceil();
  if (m < 60) return '$m daq';
  if (m < 60 * 24) return '${m ~/ 60} soat ${m % 60} daq';
  return '${m ~/ (60 * 24)} kun';
}

String fmtTime(DateTime t) => '${two(t.hour)}:${two(t.minute)}';

String timeAgo(DateTime t) {
  final d = DateTime.now().difference(t);
  if (d.inSeconds < 60) return 'hozirgina';
  if (d.inMinutes < 60) return '${d.inMinutes} daq oldin';
  if (d.inHours < 24) return '${d.inHours} soat oldin';
  return '${d.inDays} kun oldin';
}

const uzMonths = [
  'yanvar', 'fevral', 'mart', 'aprel', 'may', 'iyun',
  'iyul', 'avgust', 'sentabr', 'oktabr', 'noyabr', 'dekabr'
];
const uzWeekdays = ['dushanba', 'seshanba', 'chorshanba', 'payshanba', 'juma', 'shanba', 'yakshanba'];
const uzWeekdaysShort = ['Du', 'Se', 'Ch', 'Pa', 'Ju', 'Sh', 'Ya'];

String dayLabel(DateTime d) {
  final now = DateTime.now();
  final a = DateTime(now.year, now.month, now.day);
  final b = DateTime(d.year, d.month, d.day);
  final diff = b.difference(a).inDays;
  if (diff == 0) return 'Bugun';
  if (diff == 1) return 'Ertaga';
  if (diff == -1) return 'Kecha';
  return '${d.day}-${uzMonths[d.month - 1]}, ${uzWeekdays[d.weekday - 1]}';
}

class Pill extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;
  final IconData? icon;
  const Pill(this.label, this.color, this.onTap, {super.key, this.icon});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.16), borderRadius: BorderRadius.circular(14)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 5)],
            Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}

/// Bosilganda ozgina xiralashadigan tugma.
class Tap extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onSecondaryTap;
  final String? tooltip;
  const Tap({super.key, required this.child, this.onTap, this.onSecondaryTap, this.tooltip});
  @override
  State<Tap> createState() => _TapState();
}

class _TapState extends State<Tap> {
  bool down = false;
  @override
  Widget build(BuildContext context) {
    Widget w = GestureDetector(
      onTapDown: (_) => setState(() => down = true),
      onTapUp: (_) => setState(() => down = false),
      onTapCancel: () => setState(() => down = false),
      onTap: widget.onTap,
      onSecondaryTap: widget.onSecondaryTap,
      child: AnimatedOpacity(duration: const Duration(milliseconds: 90), opacity: down ? 0.5 : 1, child: widget.child),
    );
    if (widget.tooltip != null) {
      w = Tooltip(message: widget.tooltip!, waitDuration: const Duration(milliseconds: 500), child: w);
    }
    return w;
  }
}
