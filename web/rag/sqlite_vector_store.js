/**
 * SQLite WASM VectorStore Proxy for Web Platform
 *
 * Delegates all SQLite operations to dedicated Web Worker.
 * Required for OPFSCoopSyncVFS which uses createSyncAccessHandle().
 *
 * Architecture:
 * - Main thread: This proxy class (API for Dart interop)
 * - Worker thread: Actual SQLite operations with OPFS
 * - Communication: postMessage with request IDs
 */

class SQLiteVectorStore {
    constructor(dimension = null) {
        this.worker = null;
        this.dimension = dimension;
        this.requestId = 0;
        this.pendingRequests = new Map();
    }

    /**
     * Initialize SQLite WASM database via worker
     */
    async initialize(databasePath) {
        console.log('[SQLiteVectorStore] Creating worker...');

        // Fetch worker code (cross-origin workaround)
        // CORS allows fetch, but direct Worker creation from cross-origin URL is blocked
        // Use relative path to avoid Vite converting to data URI
        const workerPath = './sqlite_vector_store_worker.js';
        const response = await fetch(workerPath);
        const workerCode = await response.text();

        // Create blob URL for worker (same-origin, bypasses Worker restriction)
        const blob = new Blob([workerCode], { type: 'application/javascript' });
        const blobUrl = URL.createObjectURL(blob);

        // Create worker from blob URL
        this.worker = new Worker(blobUrl, { type: 'module' });

        // Set up message handler
        this.worker.onmessage = (event) => {
            const { id, success, result, error } = event.data;
            const pending = this.pendingRequests.get(id);

            if (pending) {
                this.pendingRequests.delete(id);
                if (success) {
                    pending.resolve(result);
                } else {
                    pending.reject(new Error(error));
                }
            }
        };

        this.worker.onerror = (error) => {
            console.error('[SQLiteVectorStore] Worker error:', error);
        };

        // Initialize database in worker
        await this._call('initialize', [databasePath, this.dimension]);

        // Clean up blob URL AFTER worker has loaded and initialized
        // ES6 module workers load code asynchronously, so we must wait
        URL.revokeObjectURL(blobUrl);

        console.log('[SQLiteVectorStore] Initialized successfully via worker');
    }

    /**
     * Add document with embedding
     */
    async addDocument(id, content, embedding, metadata = null) {
        return this._call('addDocument', [id, content, embedding, metadata]);
    }

    /**
     * Search similar documents using cosine similarity
     */
    async searchSimilar(queryEmbedding, topK, threshold) {
        return this._call('searchSimilar', [queryEmbedding, topK, threshold]);
    }

    /**
     * Get vector store statistics
     */
    async getStats() {
        return this._call('getStats', []);
    }

    /**
     * Clear all documents
     */
    async clear() {
        return this._call('clear', []);
    }

    /**
     * Close database and terminate worker
     */
    async close() {
        if (this.worker) {
            await this._call('close', []);
            this.worker.terminate();
            this.worker = null;
        }
        this.pendingRequests.clear();
    }

    /**
     * Call worker method and wait for response
     */
    _call(method, args) {
        return new Promise((resolve, reject) => {
            if (!this.worker && method !== 'initialize') {
                reject(new Error('Worker not initialized'));
                return;
            }

            const id = ++this.requestId;
            this.pendingRequests.set(id, { resolve, reject });
            this.worker.postMessage({ id, method, args });
        });
    }
}

// Export for Dart JS interop
window.SQLiteVectorStore = SQLiteVectorStore;

console.log('[SQLiteVectorStore] Module loaded (worker proxy)');
