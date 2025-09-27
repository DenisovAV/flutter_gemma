import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_gemma/flutter_gemma.dart';
import 'package:flutter_gemma_example/models/embedding_model.dart' as example_embedding_model;
import 'package:flutter_gemma_example/services/embedding_download_service.dart';

class EmbeddingTestScreen extends StatefulWidget {
  final example_embedding_model.EmbeddingModel model;
  
  const EmbeddingTestScreen({super.key, required this.model});

  @override
  State<EmbeddingTestScreen> createState() => _EmbeddingTestScreenState();
}

class _EmbeddingTestScreenState extends State<EmbeddingTestScreen> {
  final TextEditingController _textController = TextEditingController();

  List<double>? _embeddingResult;
  bool _isGenerating = false;
  String? _errorMessage;
  EmbeddingModel? _embeddingModel;

  @override
  void initState() {
    super.initState();
    _initializeEmbeddingModelIfNeeded();
  }

  @override
  void dispose() {
    _textController.dispose();
    _embeddingModel?.close();
    super.dispose();
  }

  /// Initialize embedding model if it's not already initialized
  Future<void> _initializeEmbeddingModelIfNeeded() async {
    try {
      // Create a download service to get file paths
      final service = EmbeddingModelDownloadService(model: widget.model);

      // Check if files exist
      final modelExists = await service.checkModelExistence('');
      if (!modelExists) {
        if (kDebugMode) {
          print('⚠️ Embedding model files not found. Download required.');
        }
        return;
      }

      // Try to create the embedding model
      final modelPath = await service.getModelFilePath();
      final tokenizerPath = await service.getTokenizerFilePath();

      _embeddingModel = await FlutterGemmaPlugin.instance.createEmbeddingModel(
        modelPath: modelPath,
        tokenizerPath: tokenizerPath,
        preferredBackend: PreferredBackend.gpu, // Use GPU mode for better performance
      );

      setState(() {
        // Model initialized successfully
      });

      if (kDebugMode) {
        print('✅ Embedding model created on test screen');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Could not create embedding model: $e');
      }
      // Don't set error state here - let user try to generate and see the error
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0b2351),
      appBar: AppBar(
        title: Text(widget.model.displayName),
        backgroundColor: const Color(0xFF0b2351),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Model info
            Card(
              color: const Color(0xFF1a3a5c),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Model Information',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildInfoRow('Size:', widget.model.size),
                    _buildInfoRow('Dimension:', '${widget.model.dimension}D'),
                    _buildInfoRow('Type:', 'Embedding Model'),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            // Input section
            const Text(
              'Test Embedding Generation',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _textController,
              maxLines: 4,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                hintText: 'Enter text to generate embeddings...',
                hintStyle: TextStyle(color: Colors.white60),
                border: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white30),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
                filled: true,
                fillColor: Color(0xFF1a3a5c),
              ),
            ),
            
            const SizedBox(height: 16),
            
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isGenerating ? null : _generateEmbedding,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isGenerating ? Colors.grey : const Color(0xFF1a4a7c),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: _isGenerating 
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              ),
                              SizedBox(width: 8),
                              Text('Generating...'),
                            ],
                          )
                        : const Text('Generate Embedding'),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: _clearResults,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[600],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 24),
                  ),
                  child: const Text('Clear'),
                ),
              ],
            ),
            
            const SizedBox(height: 24),
            
            // Results section placeholder
            SizedBox(
              height: 300,
              child: Card(
                color: const Color(0xFF1a3a5c),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Embedding Results',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: _buildResultsContent(),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
  
  Future<void> _generateEmbedding() async {
    if (_textController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter some text to generate embeddings'),
        ),
      );
      return;
    }
    
    setState(() {
      _isGenerating = true;
      _errorMessage = null;
      _embeddingResult = null;
    });
    
    try {
      final text = _textController.text.trim();
      if (_embeddingModel == null) {
        throw Exception('Embedding model not initialized');
      }
      final embedding = await _embeddingModel!.generateEmbedding(text);
      
      setState(() {
        _embeddingResult = embedding;
        _isGenerating = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Generated ${embedding.length}-dimensional embedding vector'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error generating embedding: $e');
      }
      
      setState(() {
        _errorMessage = e.toString();
        _isGenerating = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
  
  void _clearResults() {
    setState(() {
      _textController.clear();
      _embeddingResult = null;
      _errorMessage = null;
    });
  }
  
  Widget _buildResultsContent() {
    if (_isGenerating) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.blue),
            SizedBox(height: 16),
            Text(
              'Generating embedding...',
              style: TextStyle(color: Colors.white60),
            ),
          ],
        ),
      );
    }
    
    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 48, color: Colors.red),
            const SizedBox(height: 16),
            const Text(
              'Error generating embedding',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.white60, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ],
        ),
      );
    }
    
    if (_embeddingResult != null && _embeddingResult!.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vector (${_embeddingResult!.length} dimensions):',
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              child: Container(
                padding: const EdgeInsets.all(8.0),
                decoration: BoxDecoration(
                  color: const Color(0xFF0b2351),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.white30),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Show first few dimensions
                    Text(
                      _embeddingResult!.take(10).map((v) => v.toStringAsFixed(4)).join(', ') + 
                      (_embeddingResult!.length > 10 ? '...' : ''),
                      style: const TextStyle(
                        color: Colors.white,
                        fontFamily: 'monospace',
                        fontSize: 10,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Magnitude: ${_calculateMagnitude(_embeddingResult!).toStringAsFixed(6)}',
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }
    
    // Default state
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.psychology, size: 48, color: Colors.white30),
          const SizedBox(height: 16),
          const Text(
            'Enter text above and click "Generate Embedding"',
            style: TextStyle(color: Colors.white60, fontSize: 14),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Will generate ${widget.model.dimension}-dimensional vectors',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
  
  double _calculateMagnitude(List<double> vector) {
    double sum = 0.0;
    for (double value in vector) {
      sum += value * value;
    }
    return math.sqrt(sum);
  }
}