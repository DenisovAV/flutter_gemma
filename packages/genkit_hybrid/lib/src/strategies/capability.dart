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
/// v1 blind spots: `video/*` media, PDFs, and `request.docs` map to no required
/// capability.
class CapabilityStrategy implements RoutingStrategy {
  CapabilityStrategy({
    required Map<String, Set<ModelCapability>> supports,
    List<String>? order,
  }) : _supports = supports,
       _order = order ?? supports.keys.toList();

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

  // contentType is nullable; the Flutter image-picker path carries the type in
  // a `data:<kind>/...` url, so check both.
  bool _is(Media media, String kind) =>
      (media.contentType?.startsWith('$kind/') ?? false) ||
      media.url.startsWith('data:$kind/');
}
