package dev.flutterberlin.flutter_gemma

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import kotlin.math.sqrt

class VectorStore(
    private val context: Context,
    private val dimension: Int? = null  // null = auto-detect from first document
) {
    private var dbHelper: VectorDatabaseHelper? = null
    private var database: SQLiteDatabase? = null
    private var detectedDimension: Int? = null

    companion object {
        const val DATABASE_NAME = "flutter_gemma_vectors.db"
        const val DATABASE_VERSION = 2  // Increment for schema change

        // Common dimensions (informational only)
        const val DIM_GECKO_SMALL = 256
        const val DIM_MINI_LM = 384
        const val DIM_BERT_BASE = 768
        const val DIM_BERT_LARGE = 1024
        const val DIM_COHERE_V3 = 1024
        const val DIM_OPENAI_ADA = 1536
        const val DIM_OPENAI_LARGE = 3072
        const val DIM_QWEN_3 = 4096
        
        const val TABLE_DOCUMENTS = "documents"
        const val COLUMN_ID = "id"
        const val COLUMN_CONTENT = "content"
        const val COLUMN_EMBEDDING = "embedding"
        const val COLUMN_METADATA = "metadata"
        const val COLUMN_CREATED_AT = "created_at"
    }
    
    private inner class VectorDatabaseHelper(context: Context) : SQLiteOpenHelper(context, DATABASE_NAME, null, DATABASE_VERSION) {
        override fun onCreate(db: SQLiteDatabase) {
            val createTableSQL = """
                CREATE TABLE $TABLE_DOCUMENTS (
                    $COLUMN_ID TEXT PRIMARY KEY,
                    $COLUMN_CONTENT TEXT NOT NULL,
                    $COLUMN_EMBEDDING BLOB NOT NULL,
                    $COLUMN_METADATA TEXT,
                    $COLUMN_CREATED_AT INTEGER DEFAULT (strftime('%s', 'now'))
                );
                CREATE INDEX idx_created_at ON $TABLE_DOCUMENTS($COLUMN_CREATED_AT);
            """.trimIndent()
            db.execSQL(createTableSQL)
        }

        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
            // Simple DROP is acceptable: we changed embedding storage format (JSON→BLOB)
            // and migration is not possible. Users will need to re-index documents.
            db.execSQL("DROP TABLE IF EXISTS $TABLE_DOCUMENTS")
            onCreate(db)
        }
    }
    
    fun initialize(databasePath: String) {
        dbHelper = VectorDatabaseHelper(context)
        database = dbHelper?.writableDatabase
    }
    
    fun addDocument(id: String, content: String, embedding: List<Double>, metadata: String?) {
        val db = database ?: throw IllegalStateException("Database not initialized")

        // Auto-detect dimension from first document
        if (detectedDimension == null) {
            detectedDimension = dimension ?: embedding.size

            // Validate if dimension was specified
            if (dimension != null && dimension != embedding.size) {
                throw IllegalArgumentException(
                    "Embedding dimension mismatch: expected $dimension, got ${embedding.size}"
                )
            }
        }

        // Validate dimension consistency for subsequent documents
        if (embedding.size != detectedDimension) {
            throw IllegalArgumentException(
                "Embedding dimension mismatch: expected $detectedDimension, got ${embedding.size}"
            )
        }

        // Convert to binary BLOB
        val embeddingBlob = embeddingToBlob(embedding)

        val values = ContentValues().apply {
            put(COLUMN_ID, id)
            put(COLUMN_CONTENT, content)
            put(COLUMN_EMBEDDING, embeddingBlob)
            put(COLUMN_METADATA, metadata)
        }

        db.insertWithOnConflict(TABLE_DOCUMENTS, null, values, SQLiteDatabase.CONFLICT_REPLACE)
    }
    
    fun searchSimilar(queryEmbedding: List<Double>, topK: Int, threshold: Double): List<RetrievalResult> {
        val db = database ?: throw IllegalStateException("Database not initialized")

        // Validate query embedding dimension
        if (detectedDimension != null && queryEmbedding.size != detectedDimension) {
            throw IllegalArgumentException(
                "Query embedding dimension mismatch: expected $detectedDimension, got ${queryEmbedding.size}"
            )
        }

        val cursor = db.query(TABLE_DOCUMENTS, null, null, null, null, null, null)
        val results = mutableListOf<Pair<RetrievalResult, Double>>()

        cursor.use {
            val idIndex = cursor.getColumnIndexOrThrow(COLUMN_ID)
            val contentIndex = cursor.getColumnIndexOrThrow(COLUMN_CONTENT)
            val embeddingIndex = cursor.getColumnIndexOrThrow(COLUMN_EMBEDDING)
            val metadataIndex = cursor.getColumnIndexOrThrow(COLUMN_METADATA)

            while (cursor.moveToNext()) {
                val id = cursor.getString(idIndex)
                val content = cursor.getString(contentIndex)
                val embeddingBlob = cursor.getBlob(embeddingIndex)
                val metadata = cursor.getString(metadataIndex)

                // Convert BLOB to embedding
                val embedding = blobToEmbedding(embeddingBlob)

                val similarity = cosineSimilarity(queryEmbedding, embedding)

                if (similarity >= threshold) {
                    val result = RetrievalResult(
                        id = id,
                        content = content,
                        similarity = similarity,
                        metadata = metadata
                    )
                    results.add(result to similarity)
                }
            }
        }

        return results
            .sortedByDescending { it.second }
            .take(topK)
            .map { it.first }
    }
    
    fun getStats(): VectorStoreStats {
        val db = database ?: throw IllegalStateException("Database not initialized")

        val cursor = db.rawQuery("SELECT COUNT(*) FROM $TABLE_DOCUMENTS", null)
        val count = cursor.use {
            if (it.moveToFirst()) it.getLong(0) else 0L
        }

        return VectorStoreStats(
            documentCount = count,
            vectorDimension = (detectedDimension ?: 0).toLong()
        )
    }
    
    fun clear() {
        val db = database ?: throw IllegalStateException("Database not initialized")
        db.delete(TABLE_DOCUMENTS, null, null)
    }
    
    private fun cosineSimilarity(a: List<Double>, b: List<Double>): Double {
        if (a.size != b.size) return 0.0

        var dotProduct = 0.0
        var normA = 0.0
        var normB = 0.0

        for (i in a.indices) {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        return if (normA != 0.0 && normB != 0.0) {
            dotProduct / (sqrt(normA) * sqrt(normB))
        } else 0.0
    }

    /**
     * Convert embedding List<Double> to binary BLOB (float32)
     *
     * Format: Little-endian float32 array
     * Size: dimension * 4 bytes (e.g., 768D = 3,072 bytes)
     */
    private fun embeddingToBlob(embedding: List<Double>): ByteArray {
        val buffer = java.nio.ByteBuffer.allocate(embedding.size * 4)
        buffer.order(java.nio.ByteOrder.LITTLE_ENDIAN)
        embedding.forEach { buffer.putFloat(it.toFloat()) }
        return buffer.array()
    }

    /**
     * Convert binary BLOB (float32) to embedding List<Double>
     */
    private fun blobToEmbedding(blob: ByteArray): List<Double> {
        val buffer = java.nio.ByteBuffer.wrap(blob)
        buffer.order(java.nio.ByteOrder.LITTLE_ENDIAN)
        return (0 until blob.size / 4).map {
            buffer.getFloat(it * 4).toDouble()
        }
    }
}