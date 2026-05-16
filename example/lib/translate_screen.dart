import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_gemma/flutter_gemma.dart';

import 'models/translate_model.dart';
import 'translation/translate_runner.dart';

/// Translator UI: source/target language pickers, multiline input,
/// streaming output. Loads the active `InferenceModel` via
/// `FlutterGemma.getActiveModel()` and drives `TranslateRunner` for each
/// invocation.
class TranslateScreen extends StatefulWidget {
  const TranslateScreen({super.key, required this.model});

  final TranslateModel model;

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  final TextEditingController _input = TextEditingController();
  String _output = '';
  bool _loadingModel = true;
  bool _translating = false;
  String? _error;
  InferenceModel? _inference;
  TranslateRunner? _runner;

  late String _src = _initialLang('en');
  late String _dst = _initialLang('fr');

  String _initialLang(String fallback) {
    final supported = widget.model.promptStrategy.supportedLanguages;
    return supported.containsKey(fallback) ? fallback : supported.keys.first;
  }

  @override
  void initState() {
    super.initState();
    _loadModel();
  }

  Future<void> _loadModel() async {
    try {
      final model = await FlutterGemma.getActiveModel(
        maxTokens: widget.model.maxTokens,
        preferredBackend: widget.model.preferredBackend,
      );
      if (!mounted) return;
      setState(() {
        _inference = model;
        _runner = TranslateRunner(
          model: model,
          strategy: widget.model.promptStrategy,
        );
        _loadingModel = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to load model: $e';
        _loadingModel = false;
      });
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _inference?.close();
    super.dispose();
  }

  Future<void> _runTranslate() async {
    final runner = _runner;
    if (runner == null) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _translating = true;
      _output = '';
      _error = null;
    });
    try {
      await for (final chunk in runner.translateStream(
        text: text,
        src: _src,
        dst: _dst,
      )) {
        if (!mounted) return;
        setState(() => _output += chunk);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Translation failed: $e');
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  void _swap() {
    setState(() {
      final tmp = _src;
      _src = _dst;
      _dst = tmp;
    });
  }

  void _copyOutput() {
    Clipboard.setData(ClipboardData(text: _output));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Translation copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final supported = widget.model.promptStrategy.supportedLanguages;
    final entries = supported.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));

    return Scaffold(
      appBar: AppBar(title: Text(widget.model.displayName)),
      body: _loadingModel
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(child: _langPicker(entries, _src, (v) => setState(() => _src = v))),
                      IconButton(
                        icon: const Icon(Icons.swap_horiz),
                        tooltip: 'Swap languages',
                        onPressed: _translating ? null : _swap,
                      ),
                      Expanded(child: _langPicker(entries, _dst, (v) => setState(() => _dst = v))),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _input,
                    minLines: 3,
                    maxLines: 6,
                    enabled: !_translating,
                    decoration: const InputDecoration(
                      labelText: 'Text to translate',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: _translating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.translate),
                    label: Text(_translating ? 'Translating…' : 'Translate'),
                    onPressed: _translating ? null : _runTranslate,
                  ),
                  const SizedBox(height: 16),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade400),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: SingleChildScrollView(
                              child: SelectableText(
                                _output.isEmpty ? '—' : _output,
                                style: const TextStyle(fontSize: 16),
                              ),
                            ),
                          ),
                          if (_output.isNotEmpty)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                icon: const Icon(Icons.copy),
                                label: const Text('Copy'),
                                onPressed: _copyOutput,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _langPicker(
    List<MapEntry<String, String>> entries,
    String value,
    ValueChanged<String> onChange,
  ) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      decoration: const InputDecoration(border: OutlineInputBorder()),
      items: [
        for (final e in entries)
          DropdownMenuItem(value: e.key, child: Text('${e.value} (${e.key})')),
      ],
      onChanged: _translating ? null : (v) {
        if (v != null) onChange(v);
      },
    );
  }
}
