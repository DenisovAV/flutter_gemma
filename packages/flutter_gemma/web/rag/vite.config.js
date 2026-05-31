import { defineConfig } from 'vite';
import { resolve } from 'path';
import { nodePolyfills } from 'vite-plugin-node-polyfills';
import { viteStaticCopy } from 'vite-plugin-static-copy';

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
    // Copy hand-written cache_api.js (lives one folder up at web/cache_api.js
    // and defines window.cacheHas/cachePut/cacheGet that the runtime needs)
    // and the LiteRT WASM runtime files into dist/ so consumers get a
    // self-contained build output (#251).
    viteStaticCopy({
      targets: [
        {
          src: resolve(__dirname, '../cache_api.js'),
          dest: '.',
        },
        {
          src: resolve(__dirname, 'node_modules/@litertjs/core/wasm/*'),
          dest: 'wasm',
        },
      ],
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

  // Server configuration
  server: {
    port: 8000,
    headers: {
      // Required for SharedArrayBuffer (used by WASM)
      'Cross-Origin-Opener-Policy': 'same-origin',
      'Cross-Origin-Embedder-Policy': 'require-corp'
    },
    fs: {
      // Allow serving files from node_modules for WASM
      allow: ['..']
    }
  },

  // Build configuration
  build: {
    target: 'esnext',
    lib: {
      entry: {
        litert_embeddings: resolve(__dirname, 'litert_embeddings_api.js'),
        sqlite_vector_store: resolve(__dirname, 'sqlite_vector_store.js'),
        sqlite_vector_store_worker: resolve(__dirname, 'sqlite_vector_store_worker.js')
      },
      name: 'FlutterGemmaWeb',
      formats: ['es']
    },
    rollupOptions: {
      output: {
        entryFileNames: '[name].js',
        chunkFileNames: '[name].js',
        manualChunks: {
          'tensorflow': ['@tensorflow/tfjs-core', '@tensorflow/tfjs-backend-webgl'],
          'litert': ['@litertjs/core'],
          'sentencepiece': ['@sctg/sentencepiece-js']
        }
      }
    }
  },

  // Worker configuration for WASM
  worker: {
    format: 'es'
  },

  // Resolve WASM files from node_modules
  resolve: {
    alias: {
      '@litert-wasm': resolve(__dirname, 'node_modules/@litertjs/core/wasm')
    }
  }
});
