// Rename protobuf namespace to avoid conflicts with MediaPipe
// This must be included BEFORE any protobuf headers

#ifndef PROTOBUF_NAMESPACE_H_
#define PROTOBUF_NAMESPACE_H_

// Rename the entire google::protobuf namespace
#define protobuf protobuf_sp
#define google_protobuf google_protobuf_sp

#endif  // PROTOBUF_NAMESPACE_H_
