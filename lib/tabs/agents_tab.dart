import 'dart:async';

import 'package:flutter/material.dart';

import '../i18n.dart';
import '../native.dart';
import '../services/agents.dart';
import '../ui.dart';

const kAgent = Color(0xFFD97757); // Claude rangi

/// AI agentlar: Claude Code sessiyalari, holati va bugungi statistika.
class AgentsTab extends StatefulWidget {
  const AgentsTab({super.key});
  @override
  State<AgentsTab> createState() => _AgentsTabState();
}

class _AgentsTabState extends State<AgentsTab> {
  final svc = AgentService.instance;
  Timer? _tick;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    svc.sessions.addListener(_r);
    svc.connected.addListener(_r);
    svc.refreshConnected();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _r());
  }

  void _r() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _tick?.cancel();
    svc.sessions.removeListener(_r);
    svc.connected.removeListener(_r);
    super.dispose();
  }

  Future<void> _toggle(bool on) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final err = await svc.setConnected(on);
    setState(() {
      _busy = false;
      _error = err;
    });
  }

  @override
  Widget build(BuildContext context) {
    final list = svc.sessions.value;
    if (!svc.connected.value && list.isEmpty) return _setup();
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(
        child: list.isEmpty
            ? Center(
                child: Text(tr('Claude Code sessiyalari shu yerda koʻrinadi.\nTerminalda `claude` ni ishga tushiring.',
                    'Claude Code sessions appear here.\nRun `claude` in a terminal.'),
                    textAlign: TextAlign.center, style: const TextStyle(color: kDim, fontSize: 12, height: 1.4)))
            : ListView.separated(
                padding: EdgeInsets.zero,
                itemCount: list.length,
                separatorBuilder: (_, _) => const SizedBox(height: 6),
                itemBuilder: (_, i) => _session(list[i]),
              ),
      ),
      const SizedBox(width: 12),
      SizedBox(width: 170, child: _stats()),
    ]);
  }

  Widget _setup() {
    return Row(children: [
      Container(
        width: 64, height: 64,
        decoration: glassTile(radius: 18, tint: kAgent, active: true),
        child: const Icon(Icons.auto_awesome_rounded, color: kAgent, size: 30),
      ),
      const SizedBox(width: 16),
      Expanded(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(tr('Claude Code — notch’da', 'Claude Code — in your notch'),
              style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(
              tr('Agent ishlayotganda, ruxsat soʻraganda va vazifani tugatganda orol xabar beradi. '
                  'Ulash ~/.claude/settings.json ga kichik hook qoʻshadi (zaxira nusxa olinadi).',
                  'The island shows when an agent is working, needs permission or has finished. '
                  'Connecting adds a small hook to ~/.claude/settings.json (a backup is made).'),
              style: const TextStyle(color: kDim, fontSize: 11.5, height: 1.4)),
          const SizedBox(height: 10),
          Row(children: [
            Tap(
              onTap: _busy ? null : () => _toggle(true),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: glassTile(radius: 12, tint: kAgent, active: true),
                child: Text(_busy ? '…' : tr('Claude Code’ga ulash', 'Connect Claude Code'),
                    style: const TextStyle(color: kAgent, fontSize: 12.5, fontWeight: FontWeight.w700)),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(width: 10),
              Expanded(child: Text(_error!, maxLines: 2, style: const TextStyle(color: kRed, fontSize: 10.5))),
            ],
          ]),
        ]),
      ),
    ]);
  }

  Widget _session(AgentSession s) {
    final (color, label, icon) = switch (s.state) {
      AgentState.working => (kAgent, tr('Ishlayapti', 'Working'), Icons.auto_awesome_rounded),
      AgentState.waiting => (kOrange, tr('Ruxsat kerak', 'Needs you'), Icons.front_hand_rounded),
      AgentState.done => (kGreen, tr('Tayyor', 'Done'), Icons.check_circle_rounded),
      AgentState.idle => (kDim, tr('Kutmoqda', 'Idle'), Icons.pause_circle_outline_rounded),
    };
    final elapsed = s.turnStart == null ? '' : fmtClock(DateTime.now().difference(s.turnStart!));
    return Tap(
      onTap: () => Native.instance.activateTerminal(s.term),
      tooltip: tr('Terminalga oʻtish', 'Go to terminal'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: glassTile(radius: 12, tint: s.state == AgentState.waiting ? kOrange : null, active: s.state == AgentState.waiting),
        child: Row(children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(
                  child: Text(s.project, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 6),
                Text(label, style: TextStyle(color: color, fontSize: 10.5, fontWeight: FontWeight.w700)),
                if (elapsed.isNotEmpty) Text('  ·  $elapsed', style: const TextStyle(color: kDim, fontSize: 10.5)),
              ]),
              const SizedBox(height: 2),
              Text(s.detail, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: kDim, fontSize: 11)),
            ]),
          ),
          const Icon(Icons.open_in_new_rounded, size: 14, color: kDim),
        ]),
      ),
    );
  }

  Widget _stats() {
    final st = svc.stats;
    final h = st.work.inHours, m = st.work.inMinutes % 60;
    Widget row(String k, String v) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            Expanded(child: Text(k, style: const TextStyle(color: kDim, fontSize: 11))),
            Text(v, style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: glassTile(radius: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text(tr('BUGUN', 'TODAY'), style: const TextStyle(color: kDim, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1)),
        const SizedBox(height: 8),
        row(tr('Soʻrovlar', 'Prompts'), '${st.prompts}'),
        row(tr('Asboblar', 'Tool calls'), '${st.tools}'),
        row(tr('Bajarildi', 'Finished'), '${st.done}'),
        row(tr('Ish vaqti', 'Work time'), h > 0 ? '$h:${two(m)}' : '$m ${tr('daq', 'min')}'),
        const SizedBox(height: 2),
        Tap(
          onTap: _busy ? null : () => _toggle(!svc.connected.value),
          child: Text(
            svc.connected.value ? tr('Ulangan ✓ · uzish', 'Connected ✓ · disconnect') : tr('Ulash', 'Connect'),
            style: TextStyle(color: svc.connected.value ? kGreen : kAgent, fontSize: 10.5, fontWeight: FontWeight.w600),
          ),
        ),
      ]),
    );
  }
}
