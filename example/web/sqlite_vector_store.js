class l {
  constructor(e = null) {
    this.worker = null, this.dimension = e, this.requestId = 0, this.pendingRequests = /* @__PURE__ */ new Map();
  }
  /**
   * Initialize SQLite WASM database via worker
   */
  async initialize(e) {
    console.log("[SQLiteVectorStore] Creating worker..."), this.worker = new Worker(
      new URL(
        /* @vite-ignore */
        "/assets/sqlite_vector_store_worker-CfG9aZgP.js",
        import.meta.url
      ),
      { type: "module" }
    ), this.worker.onmessage = (r) => {
      const { id: t, success: s, result: i, error: n } = r.data, o = this.pendingRequests.get(t);
      o && (this.pendingRequests.delete(t), s ? o.resolve(i) : o.reject(new Error(n)));
    }, this.worker.onerror = (r) => {
      console.error("[SQLiteVectorStore] Worker error:", r);
    }, await this._call("initialize", [e, this.dimension]), console.log("[SQLiteVectorStore] Initialized successfully via worker");
  }
  /**
   * Add document with embedding
   */
  async addDocument(e, r, t, s = null) {
    return this._call("addDocument", [e, r, t, s]);
  }
  /**
   * Search similar documents using cosine similarity
   */
  async searchSimilar(e, r, t) {
    return this._call("searchSimilar", [e, r, t]);
  }
  /**
   * Get vector store statistics
   */
  async getStats() {
    return this._call("getStats", []);
  }
  /**
   * Clear all documents
   */
  async clear() {
    return this._call("clear", []);
  }
  /**
   * Close database and terminate worker
   */
  async close() {
    this.worker && (await this._call("close", []), this.worker.terminate(), this.worker = null), this.pendingRequests.clear();
  }
  /**
   * Call worker method and wait for response
   */
  _call(e, r) {
    return new Promise((t, s) => {
      if (!this.worker && e !== "initialize") {
        s(new Error("Worker not initialized"));
        return;
      }
      const i = ++this.requestId;
      this.pendingRequests.set(i, { resolve: t, reject: s }), this.worker.postMessage({ id: i, method: e, args: r });
    });
  }
}
window.SQLiteVectorStore = l;
console.log("[SQLiteVectorStore] Module loaded (worker proxy)");
