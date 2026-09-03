import 'package:genkit/genkit.dart';

import '../routing_context.dart';
import '../routing_strategy.dart';

/// A capability a model branch may support.
enum ModelCapability { vision, audio, tools, json }

/// Routes to branches that support what the request requires (media, tools,
/// JSON output), preferring [order]. Returns capable branches only, or `[]`
/// ("no decision") when none qualifies — compose with `WithFallback`
/// for a best-effort attempt on a non-capable branch.
///
/// Capabilities are declared explicitly in [supports], NOT read from a
/// branch's Genkit `metadata['model']['supports']`: that map is untyped, often
/// absent, and its `media` flag does not split vision from audio. The default
/// [order] is `supports.keys` in insertion order. `ModelCapability` is safe to
/// grow (callers build sets, never `switch`).
///
/// v1 blind spots: `video/*` media, PDFs, `request.docs`, and a hosted media
/// URL with neither a `contentType` nor a recognized file extension all map to
/// no required capability.
class CapabilityStrategy implements RoutingStrategy {
  CapabilityStrategy({
    required Map<String, Set<ModelCapability>> supports,
    List<String>? order,
  }) : _supports = {
         for (final e in supports.entries) e.key: Set.unmodifiable(e.value),
       },
       _order = List.unmodifiable(order ?? supports.keys) {
    if (order != null) {
      for (final k in order) {
        if (!supports.containsKey(k)) {
          throw ArgumentError.value(
            order,
            'order',
            'key "$k" is not in supports (${supports.keys.join(', ')})',
          );
        }
      }
    }
  }

  final Map<String, Set<ModelCapability>> _supports;
  final List<String> _order;

  @override
  List<String> route(RoutingContext context) {
    final required = _required(context.request);
    return _order
        .where((k) => (_supports[k] ?? const {}).containsAll(required))
        .toList();
  }

  Set<ModelCapability> _required(ModelRequest? request) {
    if (request == null) return const {};
    final caps = <ModelCapability>{};
    for (final message in request.messages) {
      for (final part in message.content) {
        if (!part.isMedia) continue;
        final media = part.media;
        if (media == null) continue;
        if (_is(media, 'image')) caps.add(ModelCapability.vision);
        if (_is(media, 'audio')) caps.add(ModelCapability.audio);
      }
    }
    if (request.tools?.isNotEmpty ?? false) caps.add(ModelCapability.tools);
    final o = request.output;
    if (o != null &&
        (o.format == 'json' ||
            o.schema != null ||
            o.contentType == 'application/json')) {
      caps.add(ModelCapability.json);
    }
    return caps;
  }

  static final _imageExt = RegExp(
    r'\.(jpe?g|png|gif|webp|bmp|heic|heif|avif)$',
    caseSensitive: false,
  );
  static final _audioExt = RegExp(
    r'\.(wav|mp3|m4a|aac|ogg|opus|flac|weba)$',
    caseSensitive: false,
  );

  // contentType is nullable; the Flutter image-picker path carries the type in
  // a `data:<kind>/...` url, so check contentType, the data: url, and now the
  // URL extension (case-insensitively) — a hosted URL with neither a
  // contentType nor a recognized media extension is still undetected (v1).
  bool _is(Media media, String kind) {
    final ct = media.contentType?.toLowerCase();
    final url = media.url.toLowerCase();
    if (ct != null && ct.startsWith('$kind/')) return true;
    if (url.startsWith('data:$kind/')) return true;
    // Match the extension against the URL PATH only — strip any query/fragment
    // so a `?x=photo.png` query value is not mistaken for a media extension.
    final path = url.split('?').first.split('#').first;
    return kind == 'image'
        ? _imageExt.hasMatch(path)
        : _audioExt.hasMatch(path);
  }
}
