import '../../pigeon.g.dart';

List<PreferredBackend> ffiBackendFallbackOrder(
  PreferredBackend? preferredBackend,
) =>
    switch (preferredBackend) {
      PreferredBackend.npu => const [
          PreferredBackend.npu,
          PreferredBackend.gpu,
          PreferredBackend.cpu,
        ],
      PreferredBackend.gpu || null => const [
          PreferredBackend.gpu,
          PreferredBackend.cpu,
        ],
      PreferredBackend.cpu => const [PreferredBackend.cpu],
    };

String ffiBackendWireName(PreferredBackend backend) => switch (backend) {
      PreferredBackend.npu => 'npu',
      PreferredBackend.gpu => 'gpu',
      PreferredBackend.cpu => 'cpu',
    };
