# RAG Implementation Plan for Flutter Gemma

## 🎯 Overview

Implementation plan for adding RAG (Retrieval-Augmented Generation) functionality to Flutter Gemma plugin. RAG will be integrated into the existing Pigeon architecture, initially supporting Android only with stubs for other platforms.

## 🏗️ Architecture

### Integration Approach
- **✅ Extend existing Pigeon interface** - No separate plugin creation
- **✅ Reuse existing PlatformServiceImpl** - Add RAG methods to current implementation
- **✅ Follow established patterns** - Maintain consistency with current codebase
- **🍎 iOS/🌐 Web stubs** - Platform placeholders for future implementation

## 📋 Implementation Phases

### Phase 1: Pigeon Interface Extensions

#### 1.1 Update pigeon.dart
Add RAG methods to existing `PlatformService`:

```dart
@HostApi()
abstract class PlatformService {
  // ... existing methods ...

  // RAG Embedding Methods
  @async
  void initializeEmbedding({
    required String modelPath,
    required String tokenizerPath, // MANDATORY tokenizer
    bool useGPU = true,
  });

  @async
  void closeEmbedding();

  @async
  List<double> generateEmbedding(String text);

  // RAG Vector Store Methods
  @async
  void initializeVectorStore(String databasePath);

  @async
  void addDocument(String id, String content, List<double> embedding, String? metadata);

  @async
  List<RetrievalResult> searchSimilar(List<double> queryEmbedding, int topK, double threshold);

  @async
  VectorStoreStats getVectorStoreStats();

  @async
  void clearVectorStore();
}

// Pigeon Data Classes
class RetrievalResult {
  final String id;
  final String content;
  final double similarity;
  final String? metadata;
  
  RetrievalResult(this.id, this.content, this.similarity, this.metadata);
}

class VectorStoreStats {
  final int documentCount;
  final int vectorDimension;
  
  VectorStoreStats(this.documentCount, this.vectorDimension);
}
```

#### 1.2 Regenerate Pigeon interfaces
```bash
dart run pigeon --input pigeon.dart
```

### Phase 2: Android Native Implementation

#### 2.1 Extend FlutterGemmaPlugin.kt
Add RAG components to existing `PlatformServiceImpl`:

```kotlin
private class PlatformServiceImpl(
  val context: Context
) : PlatformService, EventChannel.StreamHandler {
  // ... existing fields ...
  
  // NEW: RAG components
  private var embeddingModel: EmbeddingModel? = null
  private var vectorStore: VectorStore? = null

  // NEW: RAG method implementations
  override fun initializeEmbedding(
    modelPath: String,
    tokenizerPath: String,
    useGPU: Boolean,
    callback: (Result<Unit>) -> Unit
  ) {
    scope.launch {
      try {
        embeddingModel?.close()
        embeddingModel = EmbeddingModel(context, modelPath, tokenizerPath, useGPU)
        embeddingModel!!.initialize()
        callback(Result.success(Unit))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  override fun generateEmbedding(text: String, callback: (Result<List<Double>>) -> Unit) {
    scope.launch {
      try {
        val embedding = embeddingModel?.embed(text) 
          ?: throw IllegalStateException("Embedding model not initialized")
        callback(Result.success(embedding.toList()))
      } catch (e: Exception) {
        callback(Result.failure(e))
      }
    }
  }

  // ... additional RAG methods
}
```

#### 2.2 Create Android RAG Components

**File Structure:**
```
android/src/main/kotlin/dev/flutterberlin/flutter_gemma/
├── EmbeddingModel.kt      // Google AI Edge RAG library embedding model
├── VectorStore.kt         // SQLite vector database 
└── RagUtils.kt           // Utility functions (cosine similarity, etc.)
```

**EmbeddingModel.kt:**
```kotlin
package dev.flutterberlin.flutter_gemma

import android.content.Context
import com.google.ai.edge.localagents.rag.models.EmbedData
import com.google.ai.edge.localagents.rag.models.EmbeddingRequest
import com.google.ai.edge.localagents.rag.models.GemmaEmbeddingModel
import com.google.common.collect.ImmutableList
import java.io.File
import java.util.concurrent.Executors
import kotlinx.coroutines.guava.await
import kotlinx.coroutines.runBlocking

class EmbeddingModel(
    private val context: Context,
    private val modelPath: String,
    private val tokenizerPath: String,
    private val useGPU: Boolean = false // Use CPU by default to avoid GPU delegate issues
) {
    private var gemmaEmbeddingModel: GemmaEmbeddingModel? = null
    
    companion object {
        const val EMBEDDING_DIMENSION = 768 // EmbeddingGemma/Gecko output dimension
    }
    
    fun initialize() {
        // Verify files exist
        val modelFile = File(modelPath)
        if (!modelFile.exists()) {
            throw IllegalArgumentException("Model file not found: $modelPath")
        }
        
        val tokenizerFile = File(tokenizerPath)
        if (!tokenizerFile.exists()) {
            throw IllegalArgumentException("Tokenizer file not found: $tokenizerPath")
        }
        
        // Initialize the new GemmaEmbeddingModel from RAG library
        gemmaEmbeddingModel = GemmaEmbeddingModel(
            modelPath,
            tokenizerPath,
            useGPU
        )
    }
    
    fun embed(text: String): List<Double> {
        val model = gemmaEmbeddingModel ?: throw IllegalStateException("Tokenizer not initialized")
        
        try {
            // Create embedding request with proper structure
            val embedData = EmbedData.builder<String>()
                .setData(text)
                .setTask(EmbedData.TaskType.SEMANTIC_SIMILARITY)
                .build()
                
            val request = EmbeddingRequest.create(ImmutableList.of(embedData))
            
            // Get embeddings using the async API
            return runBlocking {
                val embeddings = model.getEmbeddings(request).await()
                // Convert ImmutableList<Float> to List<Double>
                embeddings.map { it.toDouble() }
            }
        } catch (e: Exception) {
            throw RuntimeException("Failed to generate embedding", e)
        }
    }
    
    fun close() {
        // GemmaEmbeddingModel doesn't have explicit close in the RAG library
        // but we can null it out to free resources
        gemmaEmbeddingModel = null
    }
}
```

**VectorStore.kt:**
```kotlin
package dev.flutterberlin.flutter_gemma

import android.content.Context
import androidx.sqlite.db.SupportSQLiteDatabase
import androidx.sqlite.db.SupportSQLiteOpenHelper
import androidx.sqlite.db.framework.FrameworkSQLiteOpenHelperFactory
import kotlin.math.sqrt

class VectorStore(private val context: Context) {
    private lateinit var database: SupportSQLiteDatabase
    
    companion object {
        const val DATABASE_NAME = "flutter_gemma_vectors.db"
        const val DATABASE_VERSION = 1
        const val VECTOR_DIMENSION = 768
    }
    
    fun initialize(databasePath: String) {
        val factory = FrameworkSQLiteOpenHelperFactory()
        val configuration = SupportSQLiteOpenHelper.Configuration.builder(context)
            .name(DATABASE_NAME)
            .callback(DatabaseCallback())
            .build()
        
        database = factory.create(configuration).writableDatabase
    }
    
    fun addDocument(id: String, content: String, embedding: List<Double>, metadata: String?) {
        val sql = """
            INSERT OR REPLACE INTO documents (id, content, embedding, metadata, created_at) 
            VALUES (?, ?, ?, ?, ?)
        """.trimIndent()
        
        database.execSQL(sql, arrayOf(
            id, 
            content, 
            embedding.joinToString(","), // Store as comma-separated string
            metadata,
            System.currentTimeMillis()
        ))
    }
    
    fun searchSimilar(queryEmbedding: List<Double>, topK: Int, threshold: Double): List<RetrievalResult> {
        val results = mutableListOf<Pair<RetrievalResult, Double>>()
        
        val cursor = database.query("SELECT id, content, embedding, metadata FROM documents")
        
        while (cursor.moveToNext()) {
            val id = cursor.getString(0)
            val content = cursor.getString(1)
            val embeddingStr = cursor.getString(2)
            val metadata = cursor.getString(3)
            
            val docEmbedding = embeddingStr.split(",").map { it.toDouble() }
            val similarity = cosineSimilarity(queryEmbedding, docEmbedding)
            
            if (similarity >= threshold) {
                results.add(RetrievalResult(id, content, similarity, metadata) to similarity)
            }
        }
        cursor.close()
        
        return results
            .sortedByDescending { it.second }
            .take(topK)
            .map { it.first }
    }
    
    fun getStats(): VectorStoreStats {
        val cursor = database.query("SELECT COUNT(*) FROM documents")
        cursor.moveToFirst()
        val count = cursor.getInt(0)
        cursor.close()
        
        return VectorStoreStats(count, VECTOR_DIMENSION)
    }
    
    fun clearAll() {
        database.execSQL("DELETE FROM documents")
    }
    
    fun close() {
        if (::database.isInitialized) {
            database.close()
        }
    }
    
    private fun cosineSimilarity(a: List<Double>, b: List<Double>): Double {
        require(a.size == b.size) { "Vectors must have the same dimension" }
        
        val dotProduct = a.zip(b).sumOf { it.first * it.second }
        val normA = sqrt(a.sumOf { it * it })
        val normB = sqrt(b.sumOf { it * it })
        
        return if (normA == 0.0 || normB == 0.0) 0.0 else dotProduct / (normA * normB)
    }
    
    private inner class DatabaseCallback : SupportSQLiteOpenHelper.Callback(DATABASE_VERSION) {
        override fun onCreate(db: SupportSQLiteDatabase) {
            db.execSQL("""
                CREATE TABLE documents (
                    id TEXT PRIMARY KEY,
                    content TEXT NOT NULL,
                    embedding TEXT NOT NULL,
                    metadata TEXT,
                    created_at INTEGER DEFAULT 0
                );
                CREATE INDEX idx_created_at ON documents(created_at);
            """.trimIndent())
        }
        
        override fun onUpgrade(db: SupportSQLiteDatabase, oldVersion: Int, newVersion: Int) {
            // Handle database schema upgrades
        }
    }
}
```

#### 2.3 Update Android Dependencies
**android/build.gradle:**
```gradle
dependencies {
    // ... existing dependencies ...
    
    // NEW: RAG functionality using Google AI Edge RAG library
    implementation 'com.google.mediapipe:tasks-genai:0.10.27'
    implementation 'com.google.ai.edge.localagents:localagents-rag:0.3.0'
    implementation 'com.google.guava:guava:33.3.1-android'
    implementation 'org.jetbrains.kotlinx:kotlinx-coroutines-guava:1.9.0'
    implementation 'androidx.sqlite:sqlite:2.4.0'
}
```

## 🚀 Implementation Status

### ✅ Completed
- Android RAG components with Google AI Edge RAG library
- Unified model architecture with BaseModel interfaces
- Dual progress tracking for model and tokenizer downloads
- EmbeddingTestScreen with real embedding generation
- Fixed all dependency conflicts and GPU issues
- Proper authentication handling for HuggingFace models
- UI integration with existing app theme

### 🔄 Currently Implementing
- Finalizing analyzer warnings and removing Russian text

### 📝 Remaining Tasks
- Phase 1: Pigeon interface extensions
- Phase 3: Dart API layer enhancement
- Phase 4: Full RAG chat integration
- Phase 5: Vector store UI and document management

## 📝 Testing Strategy

### Unit Tests
```
test/rag/
├── embedding_model_test.dart
├── vector_store_test.dart  
├── rag_chat_test.dart
└── model_manager_rag_test.dart
```

### Integration Tests
```
integration_test/
└── rag_integration_test.dart
```

### Test Scenarios
1. **Embedding Model**: Download, initialize, generate embeddings
2. **Vector Store**: Add documents, search similarity, manage database
3. **RAG Chat**: Context retrieval, prompt augmentation, response generation
4. **Error Handling**: Network failures, model corruption, memory constraints

---

**Total Estimated Implementation Time**: 2-3 weeks for MVP, 4-6 weeks for full feature set.