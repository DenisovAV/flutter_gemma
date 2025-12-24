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
