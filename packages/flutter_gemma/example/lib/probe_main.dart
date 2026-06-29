// Standalone probe APP that exercises the REAL JsSkillExecutor on the bundled
// calculate-hash skill via flutter_inappwebview, and shows the result ON SCREEN.
// Run as an app (NOT integration_test) to isolate whether the Windows
// headless-WebView2 crash is in our code or only in the flutter-test harness:
//   flutter run -t lib/probe_main.dart -d windows
// GREEN = the skill returned the correct SHA-1 (loopback secure-context path
// works on this engine); RED = error / crash text.
import 'package:flutter/material.dart';
import 'package:flutter_gemma_agent/flutter_gemma_agent.dart';

const _expectedSha1 = 'aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d';

void main() => runApp(const _ProbeApp());

class _ProbeApp extends StatefulWidget {
  const _ProbeApp();
  @override
  State<_ProbeApp> createState() => _ProbeAppState();
}

class _ProbeAppState extends State<_ProbeApp> {
  String _status = 'Running calculate-hash skill…';
  bool? _ok;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    try {
      final source = AssetSkillSource();
      final skills = await source.load();
      final skill = skills.firstWhere((s) => s.name == 'calculate-hash');
      final exec = JsSkillExecutor(sourceFor: source.jsSkillSourceFor);
      final result = await exec.execute(skill, '{"text":"hello"}');
      final text = result is TextResult ? result.text : '$result';
      setState(() {
        _status = '$result';
        _ok = text.contains(_expectedSha1);
      });
      debugPrint('PROBE_RESULT: ok=$_ok $result');
    } catch (e) {
      setState(() {
        _status = 'ERROR: $e';
        _ok = false;
      });
      debugPrint('PROBE_RESULT: ERROR $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _ok == null
        ? Colors.grey
        : (_ok! ? Colors.green : Colors.red);
    return MaterialApp(
      home: Scaffold(
        backgroundColor: color.shade900,
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _ok == null
                      ? '⏳'
                      : (_ok! ? '✅ skill OK (SHA-1 matched)' : '❌ failed'),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                SelectableText(
                  _status,
                  style: const TextStyle(fontSize: 16, color: Colors.white),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
