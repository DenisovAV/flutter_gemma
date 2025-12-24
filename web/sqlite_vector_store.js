class u {
  constructor(e = null) {
    this.worker = null, this.dimension = e, this.requestId = 0, this.pendingRequests = /* @__PURE__ */ new Map();
  }
  /**
   * Initialize SQLite WASM database via worker
   */
  async initialize(e) {
    console.log("[SQLiteVectorStore] Creating worker...");
    const s = await (await fetch("./sqlite_vector_store_worker.js")).text(), o = new Blob([s], { type: "application/javascript" }), l = URL.createObjectURL(o);
    this.worker = new Worker(l, { type: "module" }), this.worker.onmessage = (i) => {
      const { id: a, success: c, result: h, error: w } = i.data, n = this.pendingRequests.get(a);
      n && (this.pendingRequests.delete(a), c ? n.resolve(h) : n.reject(new Error(w)));
    }, this.worker.onerror = (i) => {
      console.error("[SQLiteVectorStore] Worker error:", i);
    }, await this._call("initialize", [e, this.dimension]), URL.revokeObjectURL(l), console.log("[SQLiteVectorStore] Initialized successfully via worker");
  }
  /**
   * Add document with embedding
   */
  async addDocument(e, t, r, s = null) {
    return this._call("addDocument", [e, t, r, s]);
  }
  /**
   * Search similar documents using cosine similarity
   */
  async searchSimilar(e, t, r) {
    return this._call("searchSimilar", [e, t, r]);
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
  _call(e, t) {
    return new Promise((r, s) => {
      if (!this.worker && e !== "initialize") {
        s(new Error("Worker not initialized"));
        return;
      }
      const o = ++this.requestId;
      this.pendingRequests.set(o, { resolve: r, reject: s }), this.worker.postMessage({ id: o, method: e, args: t });
    });
  }
}
window.SQLiteVectorStore = u;
console.log("[SQLiteVectorStore] Module loaded (worker proxy)");
