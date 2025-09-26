package dev.flutterberlin.flutter_gemma

import android.content.ContentValues
import android.content.Context
import android.database.sqlite.SQLiteDatabase
import android.database.sqlite.SQLiteOpenHelper
import kotlin.math.sqrt

class VectorStore(private val context: Context) {
    private var dbHelper: VectorDatabaseHelper? = null
    private var database: SQLiteDatabase? = null
    
    companion object {
        const val DATABASE_NAME = "flutter_gemma_vectors.db"
        const val DATABASE_VERSION = 1
        const val VECTOR_DIMENSION = 768
        
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
                    $COLUMN_EMBEDDING TEXT NOT NULL,
                    $COLUMN_METADATA TEXT,
                    $COLUMN_CREATED_AT INTEGER DEFAULT (strftime('%s', 'now'))
                )
            """.trimIndent()
            db.execSQL(createTableSQL)
        }
        
        override fun onUpgrade(db: SQLiteDatabase, oldVersion: Int, newVersion: Int) {
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
        
        val embeddingJson = embedding.joinToString(",", "[", "]")
        
        val values = ContentValues().apply {
            put(COLUMN_ID, id)
            put(COLUMN_CONTENT, content)
            put(COLUMN_EMBEDDING, embeddingJson)
            put(COLUMN_METADATA, metadata)
        }
        
        db.insertWithOnConflict(TABLE_DOCUMENTS, null, values, SQLiteDatabase.CONFLICT_REPLACE)
    }
    
    fun searchSimilar(queryEmbedding: List<Double>, topK: Int, threshold: Double): List<RetrievalResult> {
        val db = database ?: throw IllegalStateException("Database not initialized")
        
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
                val embeddingJson = cursor.getString(embeddingIndex)
                val metadata = cursor.getString(metadataIndex)
                
                // Parse embedding from JSON
                val embedding = embeddingJson
                    .removeSurrounding("[", "]")
                    .split(",")
                    .map { it.trim().toDouble() }
                
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
            vectorDimension = VECTOR_DIMENSION.toLong()
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
}