# OPFSCoopSyncVFS Failure - Executive Summary

## THE PROBLEM

OPFSCoopSyncVFS crashes with:
```
NoSuchMethodError: tried to call a non-function, such as null: '(intermediate value).createSyncAccessHandle'
```

Location: `web/rag/sqlite_vector_store.js` line 68 during VFS initialization

## ROOT CAUSE

OPFSCoopSyncVFS requires **SharedArrayBuffer** to function:

1. `createSyncAccessHandle()` only exists when SharedArrayBuffer is available
2. SharedArrayBuffer needs HTTPS + COOP/COEP headers
3. Flutter web deployment doesn't have these headers configured
4. Therefore, the method is `null` and the call fails

## THE SOLUTION

Replace OPFSCoopSyncVFS with **OPFSAnyContextVFS**

### Why OPFSAnyContextVFS?

| Aspect | OPFSCoopSyncVFS | OPFSAnyContextVFS |
|--------|-----------------|-------------------|
| SharedArrayBuffer needed? | YES ✗ | NO ✓ |
| HTTPS required? | YES ✗ | NO ✓ |
| Browser headers needed? | YES ✗ | NO ✓ |
| OPFS performance? | 3-4x faster ✓ | 3-4x faster ✓ |
| Thread support? | Main only | Any ✓ |
| Fully async? | Partially | YES ✓ |

## IMPLEMENTATION

### File: `web/rag/sqlite_vector_store.js`

**Change 1 - Line 20 (import statement):**
```javascript
// OLD:
import { OPFSCoopSyncVFS } from 'wa-sqlite/src/examples/OPFSCoopSyncVFS.js';

// NEW:
import { OPFSAnyContextVFS } from 'wa-sqlite/src/examples/OPFSAnyContextVFS.js';
```

**Change 2 - Line 68 (VFS creation):**
```javascript
// OLD:
this.vfs = await OPFSCoopSyncVFS.create('flutter-gemma-vfs', module);

// NEW:
this.vfs = await OPFSAnyContextVFS.create('flutter-gemma-vfs', module);
```

That's it! Only 2 lines need to change.

## VERIFICATION

After making changes:

1. Browser console should show: `[SQLiteVectorStore] Initialized successfully with OPFSAnyContextVFS`
2. No "createSyncAccessHandle" errors
3. Database operations work correctly
4. Data persists across page reloads

## PERFORMANCE IMPACT

**None** - OPFSAnyContextVFS has identical performance to OPFSCoopSyncVFS:
- 3-4x faster than IndexedDB
- OPFS persistence works the same
- Fully compatible with existing VectorStore API

## FALLBACK STRATEGY (Optional)

If OPFSAnyContextVFS ever fails (very unlikely), you could add:

```javascript
let selectedVFS;
try {
  selectedVFS = await OPFSAnyContextVFS.create('flutter-gemma-vfs', module);
} catch (e) {
  console.warn('[SQLiteVectorStore] Fallback to IDBBatchAtomicVFS');
  selectedVFS = await IDBBatchAtomicVFS.create('flutter-gemma-vfs', module);
}
this.vfs = selectedVFS;
```

But this is NOT needed for the main solution.

## CONTEXT

OPFSCoopSyncVFS was chosen for synchronous OPFS access on main thread, which requires SharedArrayBuffer. However, Flutter web doesn't configure the necessary headers, making it impossible to use.

OPFSAnyContextVFS uses fully async operations instead, which:
- Works without SharedArrayBuffer
- Works without special headers
- Maintains OPFS performance
- Is compatible with Dart/Flutter async model
- Is the better choice for web deployments

