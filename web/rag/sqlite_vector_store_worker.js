/**
 * SQLite VectorStore Web Worker
 *
 * Runs wa-sqlite with OPFSCoopSyncVFS in dedicated worker thread.
 * Required for createSyncAccessHandle() which only works in worker context.
 *
 * Message Protocol:
 * - Request: { id: number, method: string, args: any[] }
 * - Response: { id: number, success: boolean, result?: any, error?: string }
 */

import SQLiteESMFactory from 'wa-sqlite/dist/wa-sqlite-async.mjs';
import * as SQLite from 'wa-sqlite';
import { OPFSCoopSyncVFS } from 'wa-sqlite/src/examples/OPFSCoopSyncVFS.js';

// Constants - IDENTICAL to Android VectorStore.kt:31-36
const DB_NAME = 'flutter_gemma_vectors.db';
const TABLE_DOCUMENTS = 'documents';
const COLUMN_ID = 'id';
const COLUMN_CONTENT = 'content';
const COLUMN_EMBEDDING = 'embedding';
const COLUMN_METADATA = 'metadata';
const COLUMN_CREATED_AT = 'created_at';

// Schema IDENTICAL to Android VectorStore.kt:41-51
const CREATE_TABLE_SQL = `
    CREATE TABLE IF NOT EXISTS ${TABLE_DOCUMENTS} (
        ${COLUMN_ID} TEXT PRIMARY KEY,
        ${COLUMN_CONTENT} TEXT NOT NULL,
        ${COLUMN_EMBEDDING} BLOB NOT NULL,
        ${COLUMN_METADATA} TEXT,
        ${COLUMN_CREATED_AT} INTEGER DEFAULT (strftime('%s', 'now'))
    );
    CREATE INDEX IF NOT EXISTS idx_created_at ON ${TABLE_DOCUMENTS}(${COLUMN_CREATED_AT});
`;

// Worker state
let db = null;
let sqlite3 = null;
let vfs = null;
let dimension = null;
let detectedDimension = null;

// ============================================================================
// Helper Functions - IDENTICAL to Android VectorStore.kt
// ============================================================================

/**
 * Convert embedding to BLOB (float32)
 * IDENTICAL to Android VectorStore.kt:204-209
 */
function embeddingToBlob(embedding) {
    const buffer = new ArrayBuffer(embedding.length * 4);
    const view = new DataView(buffer);

    for (let i = 0; i < embedding.length; i++) {
        view.setFloat32(i * 4, embedding[i], true); // little-endian
    }

    return new Uint8Array(buffer);
}

/**
 * Convert BLOB to embedding
 * IDENTICAL to Android VectorStore.kt:214-220
 */
function blobToEmbedding(blob) {
    const buffer = blob instanceof ArrayBuffer ? blob : blob.buffer;
    const byteOffset = blob instanceof Uint8Array ? blob.byteOffset : 0;
    const byteLength = blob instanceof Uint8Array ? blob.byteLength : buffer.byteLength;

    const view = new DataView(buffer, byteOffset, byteLength);
    const embedding = [];

    for (let i = 0; i < byteLength / 4; i++) {
        embedding.push(view.getFloat32(i * 4, true)); // little-endian
    }

    return embedding;
}

/**
 * Cosine similarity calculation
 * IDENTICAL to Android VectorStore.kt:180-196
 */
function cosineSimilarity(a, b) {
    if (a.length !== b.length) return 0.0;

    let dotProduct = 0.0;
    let normA = 0.0;
    let normB = 0.0;

    for (let i = 0; i < a.length; i++) {
        dotProduct += a[i] * b[i];
        normA += a[i] * a[i];
        normB += b[i] * b[i];
    }

    return (normA !== 0.0 && normB !== 0.0)
        ? dotProduct / (Math.sqrt(normA) * Math.sqrt(normB))
        : 0.0;
}

// ============================================================================
// SQLite Operations
// ============================================================================

async function initialize(databasePath, dim) {
    console.log('[SQLiteWorker] Initializing wa-sqlite with OPFSCoopSyncVFS...');

    dimension = dim;

    // Initialize SQLite WASM module
    const module = await SQLiteESMFactory();
    sqlite3 = SQLite.Factory(module);

    // Register OPFSCoopSyncVFS - works in worker context
    vfs = await OPFSCoopSyncVFS.create('flutter-gemma-vfs', module);
    sqlite3.vfs_register(vfs, true);

    // Open database
    db = await sqlite3.open_v2(
        DB_NAME,
        SQLite.SQLITE_OPEN_CREATE | SQLite.SQLITE_OPEN_READWRITE,
        'flutter-gemma-vfs'
    );

    // Create table
    await sqlite3.exec(db, CREATE_TABLE_SQL);

    console.log('[SQLiteWorker] Initialized successfully');
    return true;
}

async function addDocument(id, content, embedding, metadata) {
    if (!db) {
        throw new Error('Database not initialized');
    }

    // Auto-detect dimension
    if (detectedDimension === null) {
        detectedDimension = dimension || embedding.length;

        if (dimension !== null && dimension !== embedding.length) {
            throw new Error(
                `Embedding dimension mismatch: expected ${dimension}, got ${embedding.length}`
            );
        }
    }

    // Validate dimension consistency
    if (embedding.length !== detectedDimension) {
        throw new Error(
            `Embedding dimension mismatch: expected ${detectedDimension}, got ${embedding.length}`
        );
    }

    // Convert to BLOB
    const embeddingBlob = embeddingToBlob(embedding);

    // INSERT OR REPLACE
    const sql = `
        INSERT OR REPLACE INTO ${TABLE_DOCUMENTS}
        (${COLUMN_ID}, ${COLUMN_CONTENT}, ${COLUMN_EMBEDDING}, ${COLUMN_METADATA})
        VALUES (?, ?, ?, ?)
    `;

    // Use new wa-sqlite 1.0 API with statements() generator
    for await (const stmt of sqlite3.statements(db, sql)) {
        sqlite3.bind_collection(stmt, [id, content, embeddingBlob, metadata]);
        await sqlite3.step(stmt);
    }

    return true;
}

async function searchSimilar(queryEmbedding, topK, threshold) {
    if (!db) {
        throw new Error('Database not initialized');
    }

    // Validate query dimension
    if (detectedDimension !== null && queryEmbedding.length !== detectedDimension) {
        throw new Error(
            `Query embedding dimension mismatch: expected ${detectedDimension}, got ${queryEmbedding.length}`
        );
    }

    const sql = `SELECT ${COLUMN_ID}, ${COLUMN_CONTENT}, ${COLUMN_EMBEDDING}, ${COLUMN_METADATA} FROM ${TABLE_DOCUMENTS}`;

    const results = [];

    // Use new wa-sqlite 1.0 API with statements() generator
    for await (const stmt of sqlite3.statements(db, sql)) {
        while (await sqlite3.step(stmt) === SQLite.SQLITE_ROW) {
            const row = sqlite3.row(stmt);
            const id = row[0];
            const content = row[1];
            const embeddingBlob = row[2];
            const metadata = row[3];

            const embedding = blobToEmbedding(embeddingBlob);
            const similarity = cosineSimilarity(queryEmbedding, embedding);

            if (similarity >= threshold) {
                results.push({ id, content, similarity, metadata });
            }
        }
    }

    // Sort and take top K
    results.sort((a, b) => b.similarity - a.similarity);
    return results.slice(0, topK);
}

async function getStats() {
    if (!db) {
        throw new Error('Database not initialized');
    }

    let count = 0;
    await sqlite3.exec(
        db,
        `SELECT COUNT(*) FROM ${TABLE_DOCUMENTS}`,
        (row) => {
            count = row[0];
        }
    );

    return {
        documentCount: count || 0,
        vectorDimension: detectedDimension || 0
    };
}

async function clear() {
    if (!db) {
        throw new Error('Database not initialized');
    }

    await sqlite3.exec(db, `DELETE FROM ${TABLE_DOCUMENTS}`);
    detectedDimension = null;
    return true;
}

async function close() {
    if (db) {
        await sqlite3.close(db);
        db = null;
    }
    if (vfs) {
        await vfs.close();
        vfs = null;
    }
    sqlite3 = null;
    detectedDimension = null;
    return true;
}

// ============================================================================
// Message Handler
// ============================================================================

self.onmessage = async (event) => {
    const { id, method, args } = event.data;

    try {
        let result;

        switch (method) {
            case 'initialize':
                result = await initialize(args[0], args[1]);
                break;
            case 'addDocument':
                result = await addDocument(args[0], args[1], args[2], args[3]);
                break;
            case 'searchSimilar':
                result = await searchSimilar(args[0], args[1], args[2]);
                break;
            case 'getStats':
                result = await getStats();
                break;
            case 'clear':
                result = await clear();
                break;
            case 'close':
                result = await close();
                break;
            default:
                throw new Error(`Unknown method: ${method}`);
        }

        self.postMessage({ id, success: true, result });
    } catch (error) {
        console.error(`[SQLiteWorker] Error in ${method}:`, error);
        self.postMessage({ id, success: false, error: error.message });
    }
};

console.log('[SQLiteWorker] Worker loaded');
