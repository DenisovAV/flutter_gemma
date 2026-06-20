# Changelog

## 0.1.0

Initial release.

- `hybridModel(branches, strategy)` — combine N named Genkit `Model` actions behind one routing policy; returns an ordinary `Model`.
- `hybridModelOnDeviceCloud(onDevice, cloud, strategy)` — binary façade with `kOnDevice` / `kCloud` keys.
- `RoutingStrategy` interface returning an ordered list of branch keys (single = pre-routing, multi = fallback, empty = no decision).
- Built-in strategies: `PreRoutingStrategy`, `FallbackStrategy`, `ConnectivityStrategy`, `InputSizeStrategy`, and combinators `FirstMatch`, `WithFallback`.
- Streaming fallback only before the first emitted token.
- Transient-vs-permanent error policy: fallback on availability errors, immediate propagation of permanent ones.
