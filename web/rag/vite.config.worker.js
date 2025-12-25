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
