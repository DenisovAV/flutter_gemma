import 'dart:io' show File;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_gemma_example/models/embedding_model.dart' as model_config;
import 'package:flutter_gemma_example/services/embedding_download_service.dart';

/// Get database path - returns virtual path on web, real path on mobile
Future<String> _getDatabasePath(String filename) async {
  if (kIsWeb) {
    // Web uses OPFS - path is symbolic only
    return filename;
  } else {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$filename';
  }
}

class VectorStoreTestScreen extends StatefulWidget {
  const VectorStoreTestScreen({super.key});

  @override
  State<VectorStoreTestScreen> createState() => _VectorStoreTestScreenState();
}

class _VectorStoreTestScreenState extends State<VectorStoreTestScreen> {
  bool _isTesting = false;
  EmbeddingModel? _embeddingModel;
  int _modelDimension = 0; // Auto-detected dimension
  String _currentTest = '';

  @override
  void initState() {
    super.initState();
    _checkEmbeddingModel();
  }

  Future<void> _checkEmbeddingModel() async {
    try {
      _embeddingModel = await FlutterGemmaPlugin.instance.createEmbeddingModel();

      // Detect model dimension
      final testEmbedding = await _embeddingModel!.generateEmbedding('test');
      _modelDimension = testEmbedding.length;

      setState(() {}); // Update UI to show ready state
    } catch (e) {
      // Silent fail - tests will download models if needed
      _embeddingModel = null;
      _modelDimension = 0;
    }
  }

  void _log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    debugPrint('[$timestamp] $message');
  }

  /// Generates diverse test documents across different topics
  List<String> _generateTestDocuments(int count) {
    final topics = [
      // Technology (20 docs)
      'Flutter is a cross-platform UI framework for building mobile apps',
      'Machine learning models can process natural language text efficiently',
      'Neural networks use embeddings to represent semantic meaning',
      'Vector databases store high-dimensional embedding vectors',
      'GPU acceleration improves AI model inference performance',
      'Transformers revolutionized natural language processing tasks',
      'Deep learning requires large datasets for training models',
      'Cloud computing enables scalable AI infrastructure deployment',
      'Edge devices can run lightweight AI models locally',
      'Python is the most popular language for data science',
      'Docker containers simplify application deployment processes',
      'Kubernetes orchestrates containerized workloads at scale',
      'GraphQL provides flexible API querying capabilities',
      'WebAssembly enables high-performance web applications',
      'Rust programming language ensures memory safety',
      'TypeScript adds static typing to JavaScript code',
      'React framework builds interactive user interfaces',
      'Microservices architecture improves system modularity',
      'CI/CD pipelines automate software delivery workflows',
      'Blockchain technology enables decentralized applications',

      // Science (20 docs)
      'Quantum computers leverage superposition for parallel computation',
      'CRISPR gene editing technology modifies DNA sequences',
      'Climate change affects global temperature patterns',
      'Renewable energy sources reduce carbon emissions',
      'Photosynthesis converts sunlight into chemical energy',
      'The human brain contains billions of neurons',
      'DNA stores genetic information in base pairs',
      'Black holes have immense gravitational force',
      'Antibiotics treat bacterial infections effectively',
      'Vaccines train immune systems to fight diseases',
      'Evolution explains biodiversity through natural selection',
      'Atomic structure consists of protons neutrons electrons',
      'Chemical reactions involve breaking forming bonds',
      'Gravity attracts objects with mass together',
      'Light travels at constant speed in vacuum',
      'Magnetism results from electron movement alignment',
      'Electricity flows through conductive materials easily',
      'Thermodynamics governs energy transfer heat work',
      'Plate tectonics shapes Earth surface features',
      'Water cycle regulates planet climate systems',

      // Sports (20 docs)
      'Football requires teamwork strategy physical fitness',
      'Basketball players need height agility shooting skills',
      'Tennis matches test endurance mental toughness',
      'Swimming builds cardiovascular strength muscle tone',
      'Running marathons demands extensive training preparation',
      'Cycling tours cover hundreds of miles daily',
      'Gymnastics requires flexibility balance coordination',
      'Soccer tournaments attract millions of viewers',
      'Baseball games feature pitching batting fielding',
      'Golf courses challenge players with varied terrain',
      'Boxing matches test strength speed reflexes',
      'Skiing downhill requires courage precise control',
      'Surfing waves demands balance timing courage',
      'Rock climbing builds upper body strength',
      'Yoga improves flexibility reduces stress levels',
      'Martial arts teach discipline self defense',
      'Volleyball teams rotate positions during play',
      'Cricket matches can last multiple days',
      'Rugby players need strength tackling skills',
      'Ice hockey combines skating shooting teamwork',

      // Travel (20 docs)
      'Paris attractions include Eiffel Tower Louvre Museum',
      'Tokyo offers traditional temples modern technology',
      'New York City features diverse neighborhoods culture',
      'London landmarks include Big Ben Tower Bridge',
      'Rome showcases ancient architecture historical sites',
      'Barcelona architecture features Gaudi unique designs',
      'Dubai has tallest buildings luxury shopping malls',
      'Sydney harbor hosts Opera House iconic bridge',
      'Amsterdam canals create picturesque city views',
      'Thailand beaches attract tourists year round',
      'Iceland landscapes include geysers hot springs',
      'Switzerland mountains offer skiing hiking trails',
      'Greece islands feature white buildings blue domes',
      'Egypt pyramids represent ancient civilization wonders',
      'Peru Machu Picchu sits high Andes mountains',
      'Morocco markets sell spices textiles crafts',
      'Norway fjords create dramatic coastal scenery',
      'New Zealand offers diverse natural landscapes',
      'Vietnam cuisine combines fresh herbs spices',
      'Brazil carnival celebrates music dance culture',

      // Food (20 docs)
      'Italian pasta dishes use fresh tomatoes herbs',
      'Japanese sushi features raw fish seasoned rice',
      'Mexican tacos combine meat vegetables tortillas',
      'French cuisine emphasizes butter cream wine',
      'Indian curries blend aromatic spices heat',
      'Chinese stir fry cooks vegetables quickly',
      'Thai food balances sweet sour salty spicy',
      'Greek salads include olives feta cheese',
      'Spanish tapas offer small flavorful dishes',
      'Korean BBQ grills marinated meats tableside',
      'Vietnamese pho soup has rice noodles broth',
      'Turkish kebabs feature grilled seasoned meats',
      'Lebanese mezze includes hummus tabbouleh baba',
      'Brazilian churrasco serves grilled meat skewers',
      'American burgers stack beef cheese toppings',
      'British fish chips remain classic comfort food',
      'German sausages pair perfectly with sauerkraut',
      'Ethiopian injera bread accompanies spiced stews',
      'Moroccan tagine slow cooks meats vegetables',
      'Australian BBQ features fresh seafood steaks',
    ];

    return topics.take(count).toList();
  }

  Future<void> _runTest(String testName, Future<void> Function() test) async {
    setState(() => _currentTest = testName);
    _log('\n🧪 Running: $testName');
    try {
      await test();
      _log('✅ $testName passed');
    } catch (e, stackTrace) {
      _log('❌ $testName failed: $e');
      debugPrint('Stack trace: $stackTrace');
    }
  }

  Future<void> _runAllTests() async {
    setState(() {
      _isTesting = true;
      _currentTest = 'Starting tests...';
    });

    // Test 1 requires pre-installed model
    if (_embeddingModel != null) {
      await _runTest('Test 1: Basic Functionality', _testBasicVectorStore);
    } else {
      _log('⏭️ Skipping Test 1 (requires pre-installed embedding model)');
    }

    await _runTest(
        'Test 2: Performance Comparison (Gecko 64 vs EmbeddingGemma 256)', _testDynamicDimensions);
    await _runTest('Test 3: Dimension Validation', _testDimensionValidation);

    // Tests 4 and 5 require a model - using the one installed in Test 2
    await _runTest('Test 4: Storage Optimization', _testStorageOptimization);
    await _runTest('Test 5: Search Performance (Real Embeddings)', _testSearchPerformance);

    setState(() {
      _isTesting = false;
      _currentTest = 'All tests completed!';
    });
    _log('\n🎉 All tests completed!');
  }

  // ============================================================================
  // TEST 1: Basic Functionality
  // ============================================================================
  Future<void> _testBasicVectorStore() async {
    // 1. Initialization
    final dbPath = await _getDatabasePath('test_vector_store.db');

    await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);
    _log('✅ VectorStore initialized');

    // 2. Generate embeddings
    final texts = [
      'Flutter is a UI framework',
      'Dart is a programming language',
      'Machine learning on mobile devices',
    ];

    for (int i = 0; i < texts.length; i++) {
      final embedding = await _embeddingModel!.generateEmbedding(texts[i]);

      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc_$i',
        content: texts[i],
        embedding: embedding,
        metadata: '{"source": "test", "index": $i}',
      );
      _log('✅ Added document $i (${embedding.length}D embedding)');
    }

    // 3. Check statistics
    final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
    _log('📊 Stats: ${stats.documentCount} docs, ${stats.vectorDimension}D');

    if (stats.documentCount != 3) {
      throw Exception('Expected 3 documents, got ${stats.documentCount}');
    }

    // 4. Search similar documents
    final results = await FlutterGemmaPlugin.instance.searchSimilar(
      query: 'What is Flutter?',
      topK: 2,
      threshold: 0.0,
    );

    _log('🔍 Search results:');
    for (final result in results) {
      _log('  - ${result.content} (similarity: ${result.similarity.toStringAsFixed(4)})');
    }

    if (results.isEmpty) {
      throw Exception('Expected search results');
    }
    if (!results.first.content.contains('Flutter')) {
      throw Exception('Expected Flutter in top result');
    }

    // 5. Cleanup
    await FlutterGemmaPlugin.instance.clearVectorStore();
    final statsAfterClear = await FlutterGemmaPlugin.instance.getVectorStoreStats();
    if (statsAfterClear.documentCount != 0) {
      throw Exception('Expected 0 documents after clear');
    }

    _log('✅ All basic tests passed!');
  }

  // ============================================================================
  // TEST 2: Performance Comparison (Gecko 64 vs EmbeddingGemma 256)
  // ============================================================================
  Future<void> _testDynamicDimensions() async {
    // Compare lightweight and heavier models
    // Both generate 768D embeddings but with different parameters and performance
    final testModels = [
      model_config.EmbeddingModel.gecko64, // Gecko: 110M params, seq=64, 110MB (FASTEST)
      model_config.EmbeddingModel
          .embeddingGemma256, // EmbeddingGemma: 300M params, seq=256, 179MB (more accurate)
    ];

    for (final modelConfig in testModels) {
      final expectedDim = modelConfig.dimension;
      _log('\n📐 Testing ${modelConfig.displayName} (expects ${expectedDim}D)...');

      // downloadModel() checks if model is installed, skips download if yes,
      // and ALWAYS sets it as active (line 206-207 in embedding_installation_builder.dart)
      _log('🔧 Ensuring ${modelConfig.displayName} is active...');
      final downloadService = EmbeddingModelDownloadService(model: modelConfig);
      final token = await downloadService.loadToken() ?? '';

      bool downloadSucceeded = false;

      // Attempt 1: With token (if available)
      if (token.isNotEmpty) {
        _log('🔑 Trying with token: ${token.substring(0, 10)}...');
        try {
          await downloadService.downloadModel(token, (_, __) {});
          downloadSucceeded = true;
        } catch (e) {
          _log('⚠️  Download with token failed: $e');
        }
      } else {
        _log('⚠️  No HuggingFace token found');
      }

      // Attempt 2: Without token (if first attempt failed)
      if (!downloadSucceeded) {
        _log('🔄 Retrying without token...');
        try {
          await downloadService.downloadModel('', (_, __) {});
          downloadSucceeded = true;
          _log('✅ Downloaded without token');
        } catch (e) {
          _log('❌ Download failed even without token: $e');
          rethrow; // Fail only if both attempts didn't work
        }
      }

      // Close old model AFTER new one becomes active
      if (_embeddingModel != null) {
        await _embeddingModel!.close();
        _embeddingModel = null;
      }

      // Create new model with GPU acceleration
      _log('🔧 Initializing ${modelConfig.displayName} with GPU...');
      final initStopwatch = Stopwatch()..start();
      final embeddingModel = await FlutterGemmaPlugin.instance.createEmbeddingModel(
        preferredBackend: PreferredBackend.gpu, // ← GPU acceleration!
      );
      initStopwatch.stop();
      _log('   ⏱️  Initialization time: ${initStopwatch.elapsedMilliseconds}ms');

      // Generate real embedding and measure time
      _log('🧪 Generating test embedding...');
      final embedStopwatch = Stopwatch()..start();
      final testEmbedding = await embeddingModel.generateEmbedding('Test short query for search');
      embedStopwatch.stop();
      final actualDimension = testEmbedding.length;
      _log('   ⏱️  Embedding generation time: ${embedStopwatch.elapsedMilliseconds}ms');

      if (actualDimension != expectedDim) {
        _log(
            '⚠️  Warning: Config expects ${expectedDim}D, but model generates ${actualDimension}D');
        _log('    This may indicate incorrect model configuration.');
      }
      _log('✅ Generated ${actualDimension}D embedding (seq_len=${modelConfig.maxSeqLen})');

      // Initialize VectorStore with actual dimension
      final dbPath = await _getDatabasePath('test_${actualDimension}d.db');
      await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);

      // Add document
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc_${modelConfig.name}',
        content: 'Test document for ${modelConfig.displayName}',
        embedding: testEmbedding,
      );

      // Check statistics
      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();
      if (stats.vectorDimension != actualDimension) {
        throw Exception('Expected ${actualDimension}D in stats, got ${stats.vectorDimension}D');
      }

      _log('✅ ${modelConfig.displayName} test passed! (${actualDimension}D vectors)');

      // Keep last model for next tests
      if (modelConfig == testModels.last) {
        setState(() {
          _embeddingModel = embeddingModel;
          _modelDimension = actualDimension;
        });
        _log('💾 Keeping ${actualDimension}D model for next tests');
      } else {
        await embeddingModel.close();
      }
    }

    _log('\n✅ All dimension tests passed!');
  }

  // ============================================================================
  // TEST 3: Dimension Validation
  // ============================================================================
  Future<void> _testDimensionValidation() async {
    final dbPath = await _getDatabasePath('test_validation.db');

    await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);

    // Add first document with 768D
    final embedding768 = List.generate(768, (i) => i / 768.0);
    await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
      id: 'doc_768',
      content: 'First doc 768D',
      embedding: embedding768,
    );
    _log('✅ Added 768D document');

    // Try to add document with 256D (should throw error)
    try {
      final embedding256 = List.generate(256, (i) => i / 256.0);
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc_256',
        content: 'Second doc 256D',
        embedding: embedding256,
      );

      _log('❌ ERROR: Should have thrown dimension mismatch error!');
      throw Exception('Expected dimension mismatch error');
    } catch (e) {
      if (e.toString().contains('dimension mismatch') ||
          e.toString().contains('expected 768, got 256')) {
        _log('✅ Correctly rejected mismatched dimension');
      } else {
        _log('❌ ERROR: Wrong error type: $e');
        rethrow;
      }
    }

    _log('✅ Dimension validation test passed!');
  }

  // ============================================================================
  // TEST 4: Storage Optimization
  // ============================================================================
  Future<void> _testStorageOptimization() async {
    final dbPath = await _getDatabasePath('test_performance.db');

    // Delete old DB if exists (mobile only)
    if (!kIsWeb) {
      final dbFile = File(dbPath);
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
    }

    await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);

    // Add 100 documents with actual model dimension
    _log('📊 Adding 100 documents with ${_modelDimension}D embeddings...');
    final stopwatch = Stopwatch()..start();

    for (int i = 0; i < 100; i++) {
      final embedding = List.generate(_modelDimension, (j) => (i + j) / _modelDimension.toDouble());
      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc_$i',
        content: 'Document number $i',
        embedding: embedding,
        metadata: '{"index": $i}',
      );

      if ((i + 1) % 20 == 0) {
        _log('  Added ${i + 1} documents...');
      }
    }

    stopwatch.stop();
    _log('✅ Added 100 documents in ${stopwatch.elapsedMilliseconds}ms');

    // Check file size (mobile only - web uses OPFS which doesn't expose file stats)
    if (!kIsWeb) {
      final dbFile = File(dbPath);
      final stats = await dbFile.stat();
      final sizeKB = stats.size / 1024;
      _log('📦 Database size: ${sizeKB.toStringAsFixed(2)} KB');

      // Expected size with BLOB:
      // 100 docs * dimension * 4 bytes (float32)
      final expectedBlobSizeKB = (100 * _modelDimension * 4) / 1024;
      final expectedWithOverheadKB = expectedBlobSizeKB + 100; // +overhead

      // JSON size would be larger (~13.7 bytes per float as string)
      final expectedJsonSizeKB = (100 * _modelDimension * 13.7) / 1024;

      final expectedMaxSize = (expectedWithOverheadKB * 1.5).toInt(); // 50% buffer
      if (sizeKB >= expectedMaxSize) {
        throw Exception('Database too large: $sizeKB KB (expected < $expectedMaxSize KB)');
      }

      _log('✅ Storage optimization verified!');
      _log('   Expected JSON size: ~${expectedJsonSizeKB.toStringAsFixed(0)} KB');
      _log('   Actual BLOB size: ${sizeKB.toStringAsFixed(2)} KB');
      _log(
          '   Savings: ${((expectedJsonSizeKB - sizeKB) / expectedJsonSizeKB * 100).toStringAsFixed(1)}%');
    } else {
      _log('ℹ️ Skipping file size check on web (OPFS doesn\'t expose stats)');
      _log('✅ Storage test completed (100 documents added)');
    }
  }

  // ============================================================================
  // TEST 5: Search Performance Comparison (Real Embeddings)
  // ============================================================================
  Future<void> _testSearchPerformance() async {
    // Generate realistic documents across different topics
    final documents = _generateTestDocuments(100);

    // ========================================================================
    // TEST 1: EmbeddingGemma 256 (current model from Test 2)
    // ========================================================================
    _log('📊 Performance Test 1: EmbeddingGemma 256');
    _log('   Model: 300M params, seq=256, 179MB');

    // Create separate database for EmbeddingGemma 256
    final gemmaDbPath = await _getDatabasePath('test_search_perf_embeddinggemma256.db');
    await FlutterGemmaPlugin.instance.initializeVectorStore(gemmaDbPath);

    _log('📊 Adding 100 documents with EmbeddingGemma 256 embeddings...');
    _log('   This will take ~1-2 minutes...');

    final gemmaAddStopwatch = Stopwatch()..start();

    for (int i = 0; i < documents.length; i++) {
      // Generate embedding via EmbeddingGemma 256
      final embedding = await _embeddingModel!.generateEmbedding(documents[i]);

      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc_$i',
        content: documents[i],
        embedding: embedding,
      );

      if ((i + 1) % 25 == 0) {
        _log('   Added ${i + 1}/${documents.length} documents...');
      }
    }

    gemmaAddStopwatch.stop();
    _log(
        '✅ Added ${documents.length} documents in ${(gemmaAddStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
    _log(
        '   Avg embedding generation: ${(gemmaAddStopwatch.elapsedMilliseconds / documents.length).toStringAsFixed(0)}ms per doc\n');

    _log('🔍 Running 5 semantic search queries...');

    final searchQueries = [
      'mobile application development', // Should find Flutter, React
      'artificial intelligence and machine learning', // Should find ML, neural networks
      'travel destinations in Europe', // Should find Paris, Rome, Barcelona
      'healthy food and nutrition', // Should find various cuisines
      'sports and physical exercise', // Should find various sports
    ];

    final gemmaStopwatch = Stopwatch()..start();
    int totalResults = 0;

    for (int i = 0; i < searchQueries.length; i++) {
      final queryStopwatch = Stopwatch()..start();
      final results = await FlutterGemmaPlugin.instance.searchSimilar(
        query: searchQueries[i],
        topK: 5,
        threshold: 0.0,
      );
      queryStopwatch.stop();
      totalResults += results.length;

      _log(
          '   Query ${i + 1}: ${queryStopwatch.elapsedMilliseconds}ms (${results.length} results)');
      if (results.isNotEmpty) {
        final content = results.first.content;
        final preview = content.length > 50 ? content.substring(0, 50) : content;
        _log('      Top result: "$preview${content.length > 50 ? "..." : ""}"');
      }

      if (results.length > 5) {
        throw Exception('Expected max 5 results, got ${results.length}');
      }
    }

    gemmaStopwatch.stop();
    final gemmaAvgMs = gemmaStopwatch.elapsedMilliseconds / searchQueries.length;

    _log('✅ EmbeddingGemma 256 results:');
    _log('   Average: ${gemmaAvgMs.toStringAsFixed(2)}ms per query');
    _log('   Total: ${gemmaStopwatch.elapsedMilliseconds}ms for ${searchQueries.length} queries');
    _log(
        '   Found: $totalResults total results (avg ${(totalResults / searchQueries.length).toStringAsFixed(1)} per query)\n');

    // ========================================================================
    // TEST 2: Gecko 64 - create separate database with Gecko embeddings
    // ========================================================================
    _log('📊 Performance Test 2: Gecko 64');
    _log('   Model: 110M params, seq=64, 110MB');
    _log('🔄 Switching to Gecko 64...');

    await _embeddingModel!.close();

    // Install Gecko 64
    final downloadService = EmbeddingModelDownloadService(
      model: model_config.EmbeddingModel.gecko64,
    );
    try {
      await downloadService.downloadModel('', (_, __) {});
    } catch (e) {
      _log('   ℹ️  Using already installed model');
    }

    // Create with GPU acceleration
    _log('🔧 Initializing Gecko 64 with GPU...');
    final initStopwatch = Stopwatch()..start();
    _embeddingModel = await FlutterGemmaPlugin.instance.createEmbeddingModel(
      preferredBackend: PreferredBackend.gpu,
    );
    initStopwatch.stop();
    _log('   ⏱️  Initialization: ${initStopwatch.elapsedMilliseconds}ms');

    // Create separate database for Gecko 64
    final geckoDbPath = await _getDatabasePath('test_search_perf_gecko64.db');
    await FlutterGemmaPlugin.instance.initializeVectorStore(geckoDbPath);

    _log('📊 Adding 100 documents with Gecko 64 embeddings...');
    _log('   This will take ~30-60 seconds...');

    final geckoAddStopwatch = Stopwatch()..start();

    for (int i = 0; i < documents.length; i++) {
      // Generate embedding via Gecko 64
      final embedding = await _embeddingModel!.generateEmbedding(documents[i]);

      await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
        id: 'doc_$i',
        content: documents[i],
        embedding: embedding,
      );

      if ((i + 1) % 25 == 0) {
        _log('   Added ${i + 1}/${documents.length} documents...');
      }
    }

    geckoAddStopwatch.stop();
    _log(
        '✅ Added ${documents.length} documents in ${(geckoAddStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s');
    _log(
        '   Avg embedding generation: ${(geckoAddStopwatch.elapsedMilliseconds / documents.length).toStringAsFixed(0)}ms per doc\n');

    _log('🔍 Running 5 semantic search queries...');
    final geckoStopwatch = Stopwatch()..start();
    int geckoTotalResults = 0;

    for (int i = 0; i < searchQueries.length; i++) {
      final queryStopwatch = Stopwatch()..start();
      final results = await FlutterGemmaPlugin.instance.searchSimilar(
        query: searchQueries[i],
        topK: 5,
        threshold: 0.0,
      );
      queryStopwatch.stop();
      geckoTotalResults += results.length;

      _log(
          '   Query ${i + 1}: ${queryStopwatch.elapsedMilliseconds}ms (${results.length} results)');
      if (results.isNotEmpty) {
        final content = results.first.content;
        final preview = content.length > 50 ? content.substring(0, 50) : content;
        _log('      Top result: "$preview${content.length > 50 ? "..." : ""}"');
      }

      if (results.length > 5) {
        throw Exception('Expected max 5 results, got ${results.length}');
      }
    }

    geckoStopwatch.stop();
    final geckoAvgMs = geckoStopwatch.elapsedMilliseconds / searchQueries.length;

    _log('✅ Gecko 64 results:');
    _log('   Average: ${geckoAvgMs.toStringAsFixed(2)}ms per query');
    _log('   Total: ${geckoStopwatch.elapsedMilliseconds}ms for ${searchQueries.length} queries');
    _log(
        '   Found: $geckoTotalResults total results (avg ${(geckoTotalResults / searchQueries.length).toStringAsFixed(1)} per query)\n');

    // ========================================================================
    // RESULTS COMPARISON
    // ========================================================================
    _log('📊 PERFORMANCE COMPARISON:');
    _log('┌────────────────────────────────────────────────────────────────────┐');
    _log('│                    EmbeddingGemma 256     │  Gecko 64              │');
    _log('├────────────────────────────────────────────────────────────────────┤');
    _log('│ Model size:        179MB                  │  110MB                 │');
    _log('│ Parameters:        300M                   │  110M                  │');
    _log('│ Max seq length:    256 tokens             │  64 tokens             │');
    _log('├────────────────────────────────────────────────────────────────────┤');
    _log(
        '│ Avg query time:    ${gemmaAvgMs.toStringAsFixed(0).padLeft(7)}ms           │  ${geckoAvgMs.toStringAsFixed(0).padLeft(7)}ms         │');
    _log(
        '│ Total search time: ${gemmaStopwatch.elapsedMilliseconds.toString().padLeft(7)}ms           │  ${geckoStopwatch.elapsedMilliseconds.toString().padLeft(7)}ms         │');
    _log(
        '│ Results found:     ${totalResults.toString().padLeft(7)} docs        │  ${geckoTotalResults.toString().padLeft(7)} docs       │');
    _log('└────────────────────────────────────────────────────────────────────┘');

    final speedup = gemmaAvgMs / geckoAvgMs;
    if (speedup > 1) {
      _log('🚀 Gecko 64 is ${speedup.toStringAsFixed(1)}x FASTER than EmbeddingGemma 256!');
    } else if (speedup < 1) {
      _log('🚀 EmbeddingGemma 256 is ${(1 / speedup).toStringAsFixed(1)}x FASTER than Gecko 64!');
    } else {
      _log('⚖️  Both models have similar performance!');
    }

    _log('\n💡 Recommendation:');
    if (speedup > 1.2) {
      _log('   ✅ Use Gecko 64 for speed (110M params, fast inference)');
      _log('   ✅ Use EmbeddingGemma 256 for accuracy (300M params, better quality)');
    } else if (speedup < 0.8) {
      _log('   ✅ Use EmbeddingGemma 256 - better quality AND faster!');
    } else {
      _log(
          '   ℹ️  Similar speed - choose EmbeddingGemma 256 for better quality (300M vs 110M params)');
    }

    // Check result quality
    if (totalResults == 0 && geckoTotalResults == 0) {
      _log('\n⚠️  WARNING: Both models found 0 results. Check embeddings or threshold.');
    } else if (totalResults == 0) {
      _log('\n⚠️  WARNING: EmbeddingGemma 256 found 0 results. May need threshold adjustment.');
    } else if (geckoTotalResults == 0) {
      _log('\n⚠️  WARNING: Gecko 64 found 0 results. May need threshold adjustment.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VectorStore Tests'),
        backgroundColor: Colors.deepPurple,
      ),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.deepPurple.shade50,
            child: Column(
              children: [
                ElevatedButton.icon(
                  onPressed: _isTesting ? null : _runAllTests,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_isTesting ? 'Testing...' : 'Run All Tests'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _embeddingModel == null
                      ? 'ℹ️ Tests will download models as needed'
                      : '✅ Using ${_modelDimension}D embeddings',
                  style: TextStyle(
                    color: _embeddingModel == null ? Colors.blue : Colors.green,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _isTesting ? Icons.science : Icons.check_circle_outline,
                    size: 80,
                    color: _isTesting ? Colors.deepPurple : Colors.green,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    _currentTest.isEmpty
                        ? 'Tap "Run All Tests" to begin\n\nAll logs will appear in console'
                        : _currentTest,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _isTesting ? Colors.deepPurple : Colors.green,
                    ),
                  ),
                  if (!_isTesting && _currentTest.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      '✅ Check console for detailed logs',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _embeddingModel?.close();
    super.dispose();
  }
}
