import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:path_provider/path_provider.dart';

import 'rag_demo/rag_demo_data.dart';
import 'rag_demo/widgets/status_card.dart';
import 'rag_demo/widgets/knowledge_base_section.dart';
import 'rag_demo/widgets/search_section.dart';
import 'rag_demo/widgets/result_card.dart';

/// Get database path - returns virtual path on web, real path on mobile
Future<String> _getDatabasePath(String filename) async {
  if (kIsWeb) {
    return filename;
  } else {
    final appDir = await getApplicationDocumentsDirectory();
    return '${appDir.path}/$filename';
  }
}

class RagDemoScreen extends StatefulWidget {
  const RagDemoScreen({super.key});

  @override
  State<RagDemoScreen> createState() => _RagDemoScreenState();
}

class _RagDemoScreenState extends State<RagDemoScreen> {
  final TextEditingController _searchController = TextEditingController(
    text: 'What is Flutter?',
  );

  bool _isInitialized = false;
  bool _isLoading = false;
  bool _hasEmbeddingModel = false;
  String _statusMessage = 'Checking embedding model...';
  List<RetrievalResult> _results = [];
  VectorStoreStats? _stats;

  double _threshold = 0.0;
  int _topK = 5;

  int _addTimeMs = 0;
  int _searchTimeMs = 0;

  @override
  void initState() {
    super.initState();
    _checkEmbeddingModel();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _checkEmbeddingModel() async {
    // Check if embedding model is already initialized
    final hasModel = FlutterGemmaPlugin.instance.initializedEmbeddingModel != null;

    setState(() {
      _hasEmbeddingModel = hasModel;
      _statusMessage = hasModel
          ? 'Embedding model ready. Initialize VectorStore to begin.'
          : 'WARNING: No embedding model!\n'
              'Please create an embedding model first from the Embedding Models screen.';
    });
  }

  Future<void> _initializeVectorStore() async {
    if (!_hasEmbeddingModel) {
      _showError('Please install an embedding model first!');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Initializing VectorStore...';
    });

    try {
      final dbPath = await _getDatabasePath('rag_demo.db');
      await FlutterGemmaPlugin.instance.initializeVectorStore(dbPath);

      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();

      setState(() {
        _isInitialized = true;
        _stats = stats;
        _statusMessage = 'VectorStore initialized! ${stats.documentCount} documents stored.';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[RagDemo] Error initializing VectorStore: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error initializing VectorStore: $e';
      });
    }
  }

  Future<void> _addDocuments() async {
    if (!_isInitialized) {
      _showError('Please initialize VectorStore first!');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Adding documents...';
    });

    final stopwatch = Stopwatch()..start();

    try {
      // Collect all content texts
      final contents = sampleDocuments.map((d) => d['content']!).toList();

      // Batch embedding - one call instead of multiple
      final embeddingModel = FlutterGemmaPlugin.instance.initializedEmbeddingModel!;
      final embeddings = await embeddingModel.generateEmbeddings(contents);

      // Add documents with pre-computed embeddings
      for (int i = 0; i < sampleDocuments.length; i++) {
        await FlutterGemmaPlugin.instance.addDocumentWithEmbedding(
          id: sampleDocuments[i]['id']!,
          content: sampleDocuments[i]['content']!,
          embedding: embeddings[i],
          metadata: '{"source": "sample"}',
        );
      }

      stopwatch.stop();

      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();

      setState(() {
        _stats = stats;
        _addTimeMs = stopwatch.elapsedMilliseconds;
        _statusMessage = 'Added ${sampleDocuments.length} documents in ${_addTimeMs}ms';
        _isLoading = false;
      });
    } catch (e) {
      stopwatch.stop();
      debugPrint('[RagDemo] Error adding documents: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error adding documents: $e';
      });
    }
  }

  Future<void> _clearDocuments() async {
    if (!_isInitialized) {
      _showError('Please initialize VectorStore first!');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Clearing documents...';
    });

    try {
      await FlutterGemmaPlugin.instance.clearVectorStore();

      final stats = await FlutterGemmaPlugin.instance.getVectorStoreStats();

      setState(() {
        _stats = stats;
        _results = [];
        _statusMessage = 'All documents cleared';
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('[RagDemo] Error clearing documents: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Error clearing documents: $e';
      });
    }
  }

  Future<void> _search() async {
    if (!_isInitialized) {
      _showError('Please initialize VectorStore first!');
      return;
    }

    final query = _searchController.text.trim();
    if (query.isEmpty) {
      _showError('Please enter a search query');
      return;
    }

    setState(() {
      _isLoading = true;
      _statusMessage = 'Searching...';
    });

    final stopwatch = Stopwatch()..start();

    try {
      final results = await FlutterGemmaPlugin.instance.searchSimilar(
        query: query,
        topK: _topK,
        threshold: _threshold,
      );

      stopwatch.stop();

      setState(() {
        _results = results;
        _searchTimeMs = stopwatch.elapsedMilliseconds;
        _statusMessage = 'Found ${results.length} results in ${_searchTimeMs}ms';
        _isLoading = false;
      });
    } catch (e) {
      stopwatch.stop();
      debugPrint('[RagDemo] Search error: $e');
      setState(() {
        _isLoading = false;
        _statusMessage = 'Search error: $e';
      });
    }
  }

  void _showError(String message) {
    debugPrint('[RagDemo] ERROR: $message');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RAG Demo'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            StatusCard(
              hasEmbeddingModel: _hasEmbeddingModel,
              statusMessage: _statusMessage,
              stats: _stats,
            ),
            const SizedBox(height: 16),

            // Initialize Button
            if (!_isInitialized)
              ElevatedButton.icon(
                onPressed: _isLoading || !_hasEmbeddingModel ? null : _initializeVectorStore,
                icon: _isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.storage),
                label: const Text('Initialize VectorStore'),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),

            if (_isInitialized) ...[
              KnowledgeBaseSection(
                isLoading: _isLoading,
                addTimeMs: _addTimeMs,
                onAddDocuments: _addDocuments,
                onClearDocuments: _clearDocuments,
              ),
              const SizedBox(height: 24),

              SearchSection(
                controller: _searchController,
                threshold: _threshold,
                topK: _topK,
                isLoading: _isLoading,
                searchTimeMs: _searchTimeMs,
                onSearch: _search,
                onThresholdChanged: (value) => setState(() => _threshold = value),
                onTopKChanged: (value) => setState(() => _topK = value),
              ),
              const SizedBox(height: 24),

              // Results Section
              if (_results.isNotEmpty) ...[
                const Text(
                  'Results',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                ..._results.map((result) => ResultCard(result: result)),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
