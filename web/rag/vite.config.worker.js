import { defineConfig } from 'vite';
import { resolve } from 'path';
import { nodePolyfills } from 'vite-plugin-node-polyfills';

export default defineConfig({
  // Plugins
  plugins: [
    nodePolyfills({
      // Enable polyfills for Buffer and other Node.js globals
      globals: {
        Buffer: true,
        global: true,
        process: true,
      },
      // Enable polyfills for specific modules
      protocolImports: true,
    }),
  ],

  // Optimize dependencies
  optimizeDeps: {
    exclude: [
      '@litertjs/core',
      '@sctg/sentencepiece-js'
    ],
    include: [
      '@tensorflow/tfjs-core',
      '@tensorflow/tfjs-backend-webgl'
    ],
    esbuildOptions: {
      // Define global for browser
      define: {
        global: 'globalThis'
      }
    }
  },

  // Build configuration for worker (all dependencies inlined)
  build: {
    target: 'esnext',
    outDir: 'dist',
    // Don't wipe dist/ — the main vite.config.js already wrote
    // litert_embeddings.js + sqlite_vector_store.js + cache_api.js + wasm/
    // there. Worker build only adds sqlite_vector_store_worker.js next to
    // them. (Without this, the second `vite build` clobbered the first —
    // which is what the now-removed POSIX `mkdir -p /tmp/...` shell glue
    // in package.json was working around. See #251.)
    emptyOutDir: false,
    lib: {
      entry: resolve(__dirname, 'sqlite_vector_store_worker.js'),
      name: 'SQLiteVectorStoreWorker',
      formats: ['es'],
      fileName: () => 'sqlite_vector_store_worker.js'
    },
    rollupOptions: {
      output: {
        inlineDynamicImports: true,  // Inline ALL dependencies - no imports
      }
    }
  },

  // Resolve WASM files from node_modules
  resolve: {
    alias: {
      '@litert-wasm': resolve(__dirname, 'node_modules/@litertjs/core/wasm')
    }
  }
});
