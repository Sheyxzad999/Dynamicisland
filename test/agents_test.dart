import 'package:dinamik_orol/services/agents.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('settings.json bilan ishlash', () {
    final userHook = {
      'matcher': 'Bash',
      'hooks': [
        {'type': 'command', 'command': 'echo mening-hookim'},
      ],
    };
    final settings = <String, dynamic>{
      'model': 'opus',
      'permissions': {'allow': ['Bash(ls:*)']},
      'hooks': {
        'PreToolUse': [userHook],
      },
    };

    test('qoʻshish boshqa sozlamalar va hook’larga tegmaydi', () {
      final out = AgentService.addHooks(settings);
      expect(out['model'], 'opus');
      expect(out['permissions'], settings['permissions']);
      final pre = (out['hooks'] as Map)['PreToolUse'] as List;
      expect(pre.first, userHook, reason: 'foydalanuvchi hook’i joyida');
      expect(pre.length, 2);
      for (final ev in AgentService.hookEvents) {
        expect((out['hooks'] as Map).containsKey(ev), isTrue, reason: ev);
      }
      final ours = (pre.last as Map)['hooks'][0] as Map;
      expect(ours['async'], isTrue, reason: 'Claude Code’ni sekinlashtirmaydi');
    });

    test('ikki marta qoʻshilsa takrorlanmaydi', () {
      final twice = AgentService.addHooks(AgentService.addHooks(settings));
      final pre = (twice['hooks'] as Map)['PreToolUse'] as List;
      expect(pre.length, 2);
      expect(((twice['hooks'] as Map)['Stop'] as List).length, 1);
    });

    test('uzish faqat bizning hook’larni olib tashlaydi', () {
      final back = AgentService.removeHooks(AgentService.addHooks(settings));
      expect(back, settings);
    });

    test('hook’lari yoʻq faylda uzish "hooks" kalitini qoldirmaydi', () {
      final clean = <String, dynamic>{'model': 'opus'};
      expect(AgentService.removeHooks(AgentService.addHooks(clean)), clean);
    });
  });

  group('hodisalar', () {
    test('ish → ruxsat → tugadi', () {
      final svc = AgentService.instance;
      final alerts = <AgentAlert>[];
      final sub = svc.alerts.stream.listen(alerts.add);
      final t0 = DateTime(2026, 11, 25, 10);
      svc.handle({'hook_event_name': 'SessionStart', 'session_id': 's1', 'cwd': '/Users/a/tezkor'}, term: 'Apple_Terminal', now: t0);
      svc.handle({'hook_event_name': 'UserPromptSubmit', 'session_id': 's1'}, now: t0);
      svc.handle({
        'hook_event_name': 'PreToolUse', 'session_id': 's1', 'tool_name': 'Bash',
        'tool_input': {'command': 'npm test\necho 2'},
      }, now: t0.add(const Duration(seconds: 5)));
      var s = svc.sessions.value.single;
      expect(s.project, 'tezkor');
      expect(s.term, 'Apple_Terminal');
      expect(s.state, AgentState.working);
      expect(s.detail, 'Bash: npm test');

      svc.handle({'hook_event_name': 'Notification', 'session_id': 's1', 'notification_type': 'permission_prompt', 'message': 'Claude needs your permission to use Bash'}, now: t0.add(const Duration(seconds: 6)));
      expect(svc.sessions.value.single.state, AgentState.waiting);

      svc.handle({'hook_event_name': 'Stop', 'session_id': 's1', 'last_assistant_message': 'Barcha testlar oʻtdi.\nBatafsil…'}, now: t0.add(const Duration(minutes: 2)));
      s = svc.sessions.value.single;
      expect(s.state, AgentState.done);
      expect(s.detail, 'Barcha testlar oʻtdi.');
      expect(svc.stats.prompts, 1);
      expect(svc.stats.tools, 1);
      expect(svc.stats.done, 1);
      expect(svc.stats.work, const Duration(minutes: 2));

      svc.handle({'hook_event_name': 'SessionEnd', 'session_id': 's1'}, now: t0.add(const Duration(minutes: 3)));
      expect(svc.sessions.value, isEmpty);
      return Future<void>.delayed(Duration.zero, () {
        expect(alerts.map((a) => a.needsPermission), [true, false]);
        sub.cancel();
      });
    });

    test('toolLabel', () {
      expect(AgentService.toolLabel('Edit', {'file_path': '/a/b/main.dart'}), 'Edit: main.dart');
      expect(AgentService.toolLabel('Read', null), 'Read');
    });
  });
}
