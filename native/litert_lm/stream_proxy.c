#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
#define STREAM_PROXY_EXPORT __declspec(dllexport)
#else
#define STREAM_PROXY_EXPORT __attribute__((visibility("default")))
#endif

// Callback type matching LiteRtLmStreamCallback
typedef void (*LiteRtLmStreamCallback)(void* callback_data, const char* chunk,
                                       _Bool is_final, const char* error_msg);

// Proxy callback data: holds the Dart callback and memory to free
typedef struct {
  LiteRtLmStreamCallback dart_callback;
  void* dart_data;
} ProxyData;

// This is the C callback given to LiteRT-LM.
// It copies chunk/error strings to heap (strdup) so they survive
// until Dart's NativeCallable.listener processes them.
static void stream_proxy_callback(void* callback_data, const char* chunk,
                                  _Bool is_final, const char* error_msg) {
  ProxyData* proxy = (ProxyData*)callback_data;

  // Copy strings to heap — Dart callback will free them
  char* chunk_copy = chunk ? strdup(chunk) : NULL;
  char* error_copy = error_msg ? strdup(error_msg) : NULL;

  proxy->dart_callback(proxy->dart_data, chunk_copy, is_final, error_copy);

  // If final, free the proxy struct itself
  if (is_final) {
    free(proxy);
  }
}

// Create a proxy that wraps a Dart callback.
// Returns: proxy callback function pointer (to pass to LiteRT-LM)
// Out: proxy_data (to pass as callback_data to LiteRT-LM)
STREAM_PROXY_EXPORT
void* stream_proxy_create(LiteRtLmStreamCallback dart_callback,
                          void* dart_data,
                          LiteRtLmStreamCallback* out_proxy_fn) {
  ProxyData* proxy = (ProxyData*)malloc(sizeof(ProxyData));
  proxy->dart_callback = dart_callback;
  proxy->dart_data = dart_data;
  *out_proxy_fn = stream_proxy_callback;
  return proxy;
}

// Free a chunk or error string that was strdup'd by the proxy.
STREAM_PROXY_EXPORT
void stream_proxy_free_string(char* str) {
  free(str);
}

// Load a shared library with RTLD_GLOBAL so its symbols are visible
// to other dlopen'd libraries (e.g. GPU accelerator plugins).
// Dart's DynamicLibrary.open uses RTLD_LOCAL which hides symbols.
#ifndef _WIN32
#include <dlfcn.h>
STREAM_PROXY_EXPORT
void* stream_proxy_load_global(const char* path) {
  return dlopen(path, RTLD_LAZY | RTLD_GLOBAL);
}
#endif
