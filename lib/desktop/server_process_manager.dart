import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

/// Manages the LiteRT-LM gRPC server process lifecycle
class ServerProcessManager {
  static ServerProcessManager? _instance;
  static ServerProcessManager get instance => _instance ??= ServerProcessManager._();

  ServerProcessManager._() {
    // Register cleanup on app exit to prevent zombie processes
    _registerCleanupHandlers();
  }

  Process? _serverProcess;
  int _currentPort = 0;
  bool _isStarting = false;
  Completer<void>? _startCompleter;
  bool _cleanupRegistered = false;

  /// Register signal handlers for graceful shutdown
  void _registerCleanupHandlers() {
    if (_cleanupRegistered) return;
    _cleanupRegistered = true;

    // Handle SIGINT (Ctrl+C) and SIGTERM
    try {
      ProcessSignal.sigint.watch().listen((_) {
        debugPrint('[ServerProcessManager] Received SIGINT, cleaning up...');
        stop();
      });
      ProcessSignal.sigterm.watch().listen((_) {
        debugPrint('[ServerProcessManager] Received SIGTERM, cleaning up...');
        stop();
      });
    } catch (e) {
      // Signal watching not supported on all platforms (e.g., Windows)
      debugPrint('[ServerProcessManager] Signal handlers not available: $e');
    }
  }

  /// Current gRPC server port
  int get port => _currentPort;

  /// Whether server is running
  bool get isRunning => _serverProcess != null;

  /// Find a free port for the gRPC server
  ///
  /// Binds to port 0 which lets the OS allocate an available port,
  /// then returns that port number. This ensures multiple apps can
  /// run simultaneously without port conflicts.
  Future<int> _findFreePort() async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final port = server.port;
    await server.close();
    debugPrint('[ServerProcessManager] Found free port: $port');
    return port;
  }

  /// Start the gRPC server
  ///
  /// Returns when server is ready to accept connections.
  /// If already running, returns immediately.
  ///
  /// [port] - gRPC server port (default: auto-detect free port)
  /// [maxHeapMb] - Maximum JVM heap size in MB (default: auto-detect, max 4096)
  Future<void> start({int? port, int? maxHeapMb}) async {
    if (_serverProcess != null) {
      debugPrint('[ServerProcessManager] Server already running on port $_currentPort');
      return;
    }

    if (_isStarting) {
      debugPrint('[ServerProcessManager] Server is starting, waiting...');
      return _startCompleter?.future;
    }

    _isStarting = true;
    _startCompleter = Completer<void>();
    _currentPort = port ?? await _findFreePort();

    try {
      final javaPath = await _findJava();
      final jarPath = await _getJarPath();
      final nativesPath = await _getNativesPath();

      debugPrint('[ServerProcessManager] Starting server...');
      debugPrint('[ServerProcessManager] Java: $javaPath');
      debugPrint('[ServerProcessManager] JAR: $jarPath');
      debugPrint('[ServerProcessManager] Natives: $nativesPath');

      // Verify JAR exists
      if (!await File(jarPath).exists()) {
        throw Exception('Server JAR not found at: $jarPath');
      }

      // Calculate heap size - use provided value or auto-detect
      final heapMb = maxHeapMb ?? _getRecommendedHeapSizeMb();
      debugPrint('[ServerProcessManager] Using heap size: ${heapMb}MB');

      _serverProcess = await Process.start(
        javaPath,
        [
          '-Djava.library.path=$nativesPath',
          '-Xmx${heapMb}m',
          '-jar',
          jarPath,
          _currentPort.toString(),
        ],
        environment: {
          if (Platform.isLinux) 'LD_LIBRARY_PATH': nativesPath,
          if (Platform.isMacOS) 'DYLD_LIBRARY_PATH': nativesPath,
        },
      );

      // Monitor stdout for startup message
      final startupCompleter = Completer<void>();
      Timer? timeoutTimer;

      _serverProcess!.stdout.transform(utf8.decoder).listen((line) {
        debugPrint('[LiteRT-LM Server] $line');
        if (line.contains('started on port') && !startupCompleter.isCompleted) {
          startupCompleter.complete();
        }
      });

      _serverProcess!.stderr.transform(utf8.decoder).listen((line) {
        debugPrint('[LiteRT-LM Server ERROR] $line');
        if (line.contains('Exception') && !startupCompleter.isCompleted) {
          startupCompleter.completeError(Exception('Server failed to start: $line'));
        }
      });

      // Handle process exit
      _serverProcess!.exitCode.then((code) {
        debugPrint('[ServerProcessManager] Server process exited with code $code');
        _serverProcess = null;
        if (!startupCompleter.isCompleted) {
          startupCompleter.completeError(Exception('Server process exited unexpectedly'));
        }
      });

      // Timeout for startup
      timeoutTimer = Timer(const Duration(seconds: 30), () {
        if (!startupCompleter.isCompleted) {
          startupCompleter.completeError(
            TimeoutException('Server startup timed out after 30 seconds'),
          );
        }
      });

      // Wait for startup
      await startupCompleter.future;
      timeoutTimer.cancel();

      debugPrint('[ServerProcessManager] Server started successfully on port $_currentPort');
      _startCompleter?.complete();
    } catch (e) {
      debugPrint('[ServerProcessManager] Failed to start server: $e');
      _serverProcess?.kill();
      _serverProcess = null;
      _startCompleter?.completeError(e);
      rethrow;
    } finally {
      _isStarting = false;
    }
  }

  /// Stop the gRPC server
  Future<void> stop() async {
    if (_serverProcess == null) {
      debugPrint('[ServerProcessManager] Server not running');
      return;
    }

    debugPrint('[ServerProcessManager] Stopping server...');

    // Try graceful shutdown first
    _serverProcess!.kill(ProcessSignal.sigterm);

    // Wait for process to exit
    try {
      await _serverProcess!.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          debugPrint('[ServerProcessManager] Graceful shutdown timed out, force killing');
          _serverProcess!.kill(ProcessSignal.sigkill);
          return -1;
        },
      );
    } catch (e) {
      debugPrint('[ServerProcessManager] Error stopping server: $e');
    }

    _serverProcess = null;
    debugPrint('[ServerProcessManager] Server stopped');
  }

  /// Find Java executable
  Future<String> _findJava() async {
    // Try JAVA_HOME first
    final javaHome = Platform.environment['JAVA_HOME'];
    if (javaHome != null) {
      final javaPath = path.join(
        javaHome,
        'bin',
        Platform.isWindows ? 'java.exe' : 'java',
      );
      if (await File(javaPath).exists()) {
        return javaPath;
      }
    }

    // Try bundled JRE
    final bundledJre = await _getBundledJrePath();
    if (bundledJre != null && await File(bundledJre).exists()) {
      return bundledJre;
    }

    // Try system PATH
    final result = await Process.run(
      Platform.isWindows ? 'where' : 'which',
      ['java'],
    );
    if (result.exitCode == 0) {
      final javaPath = (result.stdout as String).trim().split('\n').first;
      // Verify it's a real Java, not macOS stub
      if (!javaPath.startsWith('/usr/bin')) {
        return javaPath;
      }
    }

    // Fallback: Try common installation paths (macOS sandbox can't see PATH)
    if (Platform.isMacOS) {
      final commonPaths = [
        '/opt/homebrew/opt/openjdk/bin/java', // Apple Silicon Homebrew
        '/opt/homebrew/opt/openjdk@21/bin/java',
        '/opt/homebrew/opt/openjdk@17/bin/java',
        '/usr/local/opt/openjdk/bin/java', // Intel Homebrew
        '/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home/bin/java',
        '/Library/Java/JavaVirtualMachines/temurin-17.jdk/Contents/Home/bin/java',
      ];
      for (final javaPath in commonPaths) {
        if (await File(javaPath).exists()) {
          return javaPath;
        }
      }
    }

    throw Exception(
      'Java not found. Please install Java 17+ or set JAVA_HOME.\n'
      'Download from: https://adoptium.net/',
    );
  }

  /// Get bundled JRE path
  Future<String?> _getBundledJrePath() async {
    final executableDir = path.dirname(Platform.resolvedExecutable);
    final javaExe = Platform.isWindows ? 'java.exe' : 'java';

    String jrePath;
    if (Platform.isMacOS) {
      // macOS: Inside app bundle Resources (not Frameworks to avoid code signing issues)
      jrePath = path.join(executableDir, '..', 'Resources', 'jre', 'bin', javaExe);
    } else if (Platform.isWindows) {
      // Windows: Next to executable
      jrePath = path.join(executableDir, 'jre', 'bin', javaExe);
    } else {
      // Linux: In lib directory
      jrePath = path.join(executableDir, 'lib', 'jre', 'bin', javaExe);
    }

    return jrePath;
  }

  /// Get server JAR path
  Future<String> _getJarPath() async {
    final executableDir = path.dirname(Platform.resolvedExecutable);

    String jarPath;
    if (Platform.isMacOS) {
      // macOS: Inside app bundle Resources
      jarPath = path.join(executableDir, '..', 'Resources', 'litertlm-server.jar');
    } else if (Platform.isWindows) {
      // Windows: In data directory
      jarPath = path.join(executableDir, 'data', 'litertlm-server.jar');
    } else {
      // Linux: In data directory
      jarPath = path.join(executableDir, 'data', 'litertlm-server.jar');
    }

    // Fallback: check current directory (for development)
    if (!await File(jarPath).exists()) {
      final devPath = path.join(
        Directory.current.path,
        'litertlm-server',
        'build',
        'libs',
        'litertlm-server-0.1.0-all.jar',
      );
      if (await File(devPath).exists()) {
        return devPath;
      }
    }

    return jarPath;
  }

  /// Get native libraries path
  Future<String> _getNativesPath() async {
    final executableDir = path.dirname(Platform.resolvedExecutable);

    String nativesPath;
    if (Platform.isMacOS) {
      // Native library is pre-extracted to Frameworks/litertlm by setup script
      nativesPath = path.join(executableDir, '..', 'Frameworks', 'litertlm');
    } else if (Platform.isWindows) {
      nativesPath = path.join(executableDir, 'litertlm');
    } else {
      nativesPath = path.join(executableDir, 'lib', 'litertlm');
    }

    // Fallback: check litertlm-server/natives (for development)
    if (!await Directory(nativesPath).exists()) {
      String platform;
      if (Platform.isMacOS) {
        platform = 'macos';
      } else if (Platform.isWindows) {
        platform = 'windows';
      } else {
        platform = 'linux';
      }
      final devPath = path.join(
        Directory.current.path,
        'litertlm-server',
        'natives',
        platform,
      );
      if (await Directory(devPath).exists()) {
        return devPath;
      }
    }

    return nativesPath;
  }

  /// Get recommended heap size based on available system memory
  ///
  /// Returns a conservative value to avoid OOM on low-memory systems
  int _getRecommendedHeapSizeMb() {
    // Default to 2GB which should work on most systems
    // This is a safe fallback - for large models, users can specify maxHeapMb
    const defaultHeapMb = 2048;
    const maxHeapMb = 4096;

    // Try to detect available memory (platform-specific)
    // For now, return default - can be enhanced with platform-specific detection
    // TODO: Add platform-specific memory detection
    return defaultHeapMb.clamp(512, maxHeapMb);
  }

  /// Reset singleton (for testing)
  @visibleForTesting
  static void reset() {
    _instance?.stop();
    _instance = null;
  }
}
