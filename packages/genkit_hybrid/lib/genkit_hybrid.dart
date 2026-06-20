/// Provider-agnostic hybrid routing for Genkit.
///
/// Combine existing Genkit models behind one routing policy and use the
/// result as an ordinary `Model` via `ai.generate`.
library;

export 'src/routing_context.dart';
export 'src/routing_strategy.dart';
export 'src/hybrid_model.dart'
    show hybridModel, hybridModelOnDeviceCloud, kOnDevice, kCloud;
export 'src/strategies/pre_routing.dart';
export 'src/strategies/fallback.dart';
export 'src/strategies/connectivity.dart';
export 'src/strategies/input_size.dart';
export 'src/strategies/first_match.dart';
export 'src/strategies/with_fallback.dart';
