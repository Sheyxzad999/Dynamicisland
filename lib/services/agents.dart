import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../i18n.dart';
import '../native.dart';

enum AgentState { idle, working, waiting, done }

class AgentSession {
  final String id;
  final String source; // claude
  String cwd;
  String term;
  AgentState state = AgentState.idle;
  String detail = '';
  DateTime updated = DateTime.now();
  DateTime? turnStart;
  int tools = 0;
  AgentSession(this.id, this.source, this.cwd, this.term);

  String get project {
    final parts = cwd.split('/').where((p) => p.isNotEmpty).toList();
    return parts.isEmpty ? 'Claude' : parts.last;
  }
}

/// Bugungi statistika — faqat hook xabarlaridan hisoblanadi (transkript oʻqilmaydi).
class AgentStats {
  int prompts = 0, tools = 0, done = 0;
  Duration work = Duration.zero;
  DateTime day = DateTime.now();
}

/// Agent hodisasi orol uchun (banner koʻrsatish).
class AgentAlert {
  final AgentSession session;
  final bool needsPermission;
  final String text;
  const AgentAlert(this.session, this.needsPermission, this.text);
}

/// Claude Code hook'laridan kelgan hodisalarni sessiyalarga aylantiradi.
class AgentService {
  AgentService._();
  static final instance = AgentService._();

  /// Hook buyrug'i — mahalliy serverga JSON yuboradi, xato bo'lsa jim qoladi.
  static const hookCommand =
      'curl -s -m 1 -X POST -H "X-Term: \$TERM_PROGRAM" --data-binary @- '
      '"http://127.0.0.1:47811/event?source=claude" >/dev/null 2>&1 || true';
  static const hookEvents = [
    'SessionStart', 'UserPromptSubmit', 'PreToolUse', 'PermissionRequest',
    'Notification', 'Stop', 'SessionEnd',
  ];

  final sessions = ValueNotifier<List<AgentSession>>([]);
  final stats = AgentStats();
  final alerts = StreamController<AgentAlert>.broadcast(sync: true);
  final connected = ValueNotifier<bool>(false);
  final _map = <String, AgentSession>{};
  Timer? _gc;

  void init() {
    Native.instance.agentEvents.listen(_onRaw);
    _gc = Timer.periodic(const Duration(minutes: 1), (_) => _cleanup());
    refreshConnected();
  }

  void dispose() => _gc?.cancel();

  List<AgentSession> get waiting => sessions.value.where((s) => s.state == AgentState.waiting).toList();
  List<AgentSession> get working => sessions.value.where((s) => s.state == AgentState.working).toList();

  void _onRaw(String raw) {
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      handle((m['payload'] as Map).cast<String, dynamic>(), source: m['source'] as String? ?? 'claude', term: m['term'] as String? ?? '');
    } catch (_) {}
  }

  /// Bitta hook hodisasini qayta ishlaydi (testlar uchun ham ochiq).
  void handle(Map<String, dynamic> e, {String source = 'claude', String term = '', DateTime? now}) {
    final t = now ?? DateTime.now();
    _rollDay(t);
    final id = (e['session_id'] ?? '').toString();
    if (id.isEmpty) return;
    final event = (e['hook_event_name'] ?? '').toString();
    final cwd = (e['cwd'] ?? '').toString();

    if (event == 'SessionEnd') {
      _map.remove(id);
      _publish();
      return;
    }
    final s = _map.putIfAbsent(id, () => AgentSession(id, source, cwd, term));
    if (cwd.isNotEmpty) s.cwd = cwd;
    if (term.isNotEmpty) s.term = term;
    s.updated = t;

    switch (event) {
      case 'SessionStart':
        s.state = AgentState.idle;
        s.detail = tr('Tayyor', 'Ready');
      case 'UserPromptSubmit':
        s.state = AgentState.working;
        s.detail = tr('Oʻylayapti…', 'Thinking…');
        s.turnStart = t;
        stats.prompts++;
      case 'PreToolUse':
        s.state = AgentState.working;
        s.detail = toolLabel(e['tool_name']?.toString() ?? '', e['tool_input']);
        s.turnStart ??= t;
        s.tools++;
        stats.tools++;
      case 'PermissionRequest':
        _waiting(s, tr('Ruxsat soʻrayapti: ', 'Needs permission: ') + toolLabel(e['tool_name']?.toString() ?? '', e['tool_input']));
      case 'Notification':
        final type = (e['notification_type'] ?? '').toString();
        if (type == 'permission_prompt') {
          _waiting(s, (e['message'] ?? tr('Ruxsat soʻrayapti', 'Needs permission')).toString());
        } else if (type == 'idle_prompt' && s.state != AgentState.done) {
          s.state = AgentState.idle;
          s.detail = tr('Javobingizni kutyapti', 'Waiting for your input');
        }
      case 'Stop':
        s.state = AgentState.done;
        final msg = (e['last_assistant_message'] ?? '').toString().trim().split('\n').first;
        s.detail = msg.isEmpty ? tr('Vazifa bajarildi', 'Task finished') : _short(msg, 90);
        if (s.turnStart != null) stats.work += t.difference(s.turnStart!);
        s.turnStart = null;
        stats.done++;
        alerts.add(AgentAlert(s, false, s.detail));
    }
    _publish();
  }

  void _waiting(AgentSession s, String detail) {
    final was = s.state == AgentState.waiting;
    s.state = AgentState.waiting;
    s.detail = _short(detail, 90);
    if (!was) alerts.add(AgentAlert(s, true, s.detail));
  }

  static String _short(String s, int n) => s.length <= n ? s : '${s.substring(0, n - 1)}…';

  /// "Bash: npm test", "Edit: main.dart" kabi qisqa tavsif.
  static String toolLabel(String tool, dynamic input) {
    final i = input is Map ? input : const {};
    String? arg;
    if (i['command'] is String) arg = i['command'] as String;
    if (i['file_path'] is String) arg = (i['file_path'] as String).split('/').last;
    if (i['pattern'] is String) arg = i['pattern'] as String;
    if (i['url'] is String) arg = i['url'] as String;
    if (i['description'] is String && arg == null) arg = i['description'] as String;
    return arg == null || arg.isEmpty ? tool : _short('$tool: ${arg.split('\n').first}', 70);
  }

  void _rollDay(DateTime t) {
    if (t.year != stats.day.year || t.month != stats.day.month || t.day != stats.day.day) {
      stats
        ..prompts = 0
        ..tools = 0
        ..done = 0
        ..work = Duration.zero
        ..day = t;
    }
  }

  /// 30 daqiqa jim turgan sessiyalar roʻyxatdan olinadi.
  void _cleanup([DateTime? now]) {
    final t = now ?? DateTime.now();
    _map.removeWhere((_, s) => s.state != AgentState.working && t.difference(s.updated) > const Duration(minutes: 30));
    _publish();
  }

  void _publish() {
    final list = _map.values.toList()
      ..sort((a, b) => _rank(a.state).compareTo(_rank(b.state)) != 0
          ? _rank(a.state).compareTo(_rank(b.state))
          : b.updated.compareTo(a.updated));
    sessions.value = list;
  }

  static int _rank(AgentState s) => switch (s) {
        AgentState.waiting => 0,
        AgentState.working => 1,
        AgentState.done => 2,
        AgentState.idle => 3,
      };

  // ---------------------------------------------------------------------------
  // ~/.claude/settings.json ga ulash / uzish

  static File get _settingsFile {
    final dir = Platform.environment['CLAUDE_CONFIG_DIR'] ?? '${Platform.environment['HOME']}/.claude';
    return File('$dir/settings.json');
  }

  Future<void> refreshConnected() async {
    try {
      final f = _settingsFile;
      connected.value = await f.exists() && (await f.readAsString()).contains('127.0.0.1:47811');
    } catch (_) {
      connected.value = false;
    }
  }

  /// Hook'larni qoʻshadi yoki olib tashlaydi. Eski fayldan zaxira nusxa olinadi.
  /// Xato boʻlsa (masalan fayl JSON emas) — hech narsa oʻzgartirilmaydi.
  Future<String?> setConnected(bool on) async {
    try {
      final f = _settingsFile;
      Map<String, dynamic> json = {};
      if (await f.exists()) {
        final text = await f.readAsString();
        if (text.trim().isNotEmpty) json = (jsonDecode(text) as Map).cast<String, dynamic>();
        await File('${f.path}.dinamikorol-backup').writeAsString(text);
      } else {
        await f.parent.create(recursive: true);
      }
      final updated = on ? addHooks(json) : removeHooks(json);
      await f.writeAsString('${const JsonEncoder.withIndent('  ').convert(updated)}\n');
      await refreshConnected();
      return null;
    } catch (e) {
      return e.toString();
    }
  }

  static bool _isOurs(dynamic group) =>
      group is Map && group['hooks'] is List && (group['hooks'] as List).any((h) => h is Map && '${h['command']}'.contains('127.0.0.1:47811'));

  /// Sof funksiya: settings xaritasiga bizning hook'larni qoʻshadi (takrorlamasdan).
  static Map<String, dynamic> addHooks(Map<String, dynamic> settings) {
    final out = removeHooks(settings);
    final hooks = (out['hooks'] as Map?)?.cast<String, dynamic>() ?? <String, dynamic>{};
    for (final ev in hookEvents) {
      final list = List<dynamic>.from(hooks[ev] as List? ?? const []);
      list.add({
        'hooks': [
          {'type': 'command', 'command': hookCommand, 'async': true},
        ],
      });
      hooks[ev] = list;
    }
    out['hooks'] = hooks;
    return out;
  }

  /// Sof funksiya: faqat bizning hook'larni olib tashlaydi, boshqalariga tegmaydi.
  static Map<String, dynamic> removeHooks(Map<String, dynamic> settings) {
    final out = Map<String, dynamic>.from(settings);
    final hooks = (out['hooks'] as Map?)?.cast<String, dynamic>();
    if (hooks == null) return out;
    final cleaned = <String, dynamic>{};
    hooks.forEach((ev, groups) {
      final list = (groups as List).where((g) => !_isOurs(g)).toList();
      if (list.isNotEmpty) cleaned[ev] = list;
    });
    if (cleaned.isEmpty) {
      out.remove('hooks');
    } else {
      out['hooks'] = cleaned;
    }
    return out;
  }
}
