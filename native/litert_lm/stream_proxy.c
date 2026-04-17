#include <stdlib.h>
#include <string.h>

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
void stream_proxy_free_string(char* str) {
  free(str);
}
