#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#ifndef _WIN32
#include <unistd.h>
#include <fcntl.h>
#endif

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

// Redirect stderr (and stdout) to a file at `path`. Used to capture native
// glog/abseil output on iOS/Android where we can't see process stderr from
// the Flutter test runner. Pass NULL to skip stdout redirect.
// Returns 0 on success, errno on failure.
STREAM_PROXY_EXPORT
int stream_proxy_redirect_stderr(const char* path) {
#ifdef _WIN32
  FILE* f = NULL;
  if (freopen_s(&f, path, "w", stderr) != 0) return 1;
  freopen_s(&f, path, "a", stdout);
  setvbuf(stderr, NULL, _IOLBF, 0);
  setvbuf(stdout, NULL, _IOLBF, 0);
  return 0;
#else
  // Append mode so multi-session test runs accumulate log instead of
  // truncating on every _ensureBindings call (different LiteRtLmFfiClient
  // instances each redirect to the same path).
  int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0644);
  if (fd < 0) return 1;
  // Redirect both fd 1 (stdout) and fd 2 (stderr).
  dup2(fd, 1);
  dup2(fd, 2);
  close(fd);
  // Disable buffering so writes hit the file immediately.
  setvbuf(stderr, NULL, _IOLBF, 0);
  setvbuf(stdout, NULL, _IOLBF, 0);
  return 0;
#endif
}

// Load a shared library so its exports are visible to subsequent
// dlopen/LoadLibrary calls and to dlsym(RTLD_DEFAULT)-style lookups.
//
// POSIX: Dart's DynamicLibrary.open uses RTLD_LOCAL which hides symbols
// from other modules; we re-open with RTLD_GLOBAL so accelerator plugins
// can resolve LiteRt* symbols against the LiteRt C API at registration.
//
// Windows: there is no RTLD_GLOBAL. PE modules expose exports through
// the Loaded Modules list automatically, so the trick reduces to
// "load the DLL into the process before anyone else needs it" — which
// is what `LoadLibraryExA(LOAD_WITH_ALTERED_SEARCH_PATH)` does when
// given an absolute or bundle-relative path.
#ifdef _WIN32
#include <windows.h>
STREAM_PROXY_EXPORT
void* stream_proxy_load_global(const char* path) {
  // LOAD_WITH_ALTERED_SEARCH_PATH lets the loader resolve dependent DLLs
  // from the directory of `path` (i.e. the bundle dir) instead of just
  // the application directory — same effect as preloading on POSIX with
  // RTLD_GLOBAL: the module is now reachable by name for later loads.
  return (void*)LoadLibraryExA(path, NULL, LOAD_WITH_ALTERED_SEARCH_PATH);
}
#else
#include <dlfcn.h>
STREAM_PROXY_EXPORT
void* stream_proxy_load_global(const char* path) {
  return dlopen(path, RTLD_LAZY | RTLD_GLOBAL);
}
#endif
