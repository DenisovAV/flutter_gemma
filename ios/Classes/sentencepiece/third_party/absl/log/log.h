// Copyright 2016 Google Inc.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.!

#ifndef ABSL_LOG_LOG_H_
#define ABSL_LOG_LOG_H_

#include <iostream>

#include "third_party/absl/strings/string_view.h"

namespace absl {

enum LogSeverityAtLeast {
  LOG_INFO = 0,
  LOG_WARNING = 1,
  LOG_ERROR = 2,
  LOG_FATAL = 3,
  LOG_SEVERITY_SIZE = 4,
};

namespace logging {

class Die {
 public:
  explicit Die(bool die) : die_(die) {}
  Die() = delete;
  ~Die() {
    std::cerr << std::endl;
    if (die_) {
      std::cerr << "Program terminated with an unrecoverable error."
                << std::endl;
      std::exit(-1);
    }
  }
  int operator&(std::ostream &) { return 0; }

 private:
  bool die_ = false;
};

inline absl::string_view BaseName(absl::string_view path) {
#ifdef OS_WIN
  const size_t pos = path.find_last_of('\\');
#else
  const size_t pos = path.find_last_of('/');
#endif
  return pos == absl::string_view::npos ? path : path.substr(pos + 1);
}
}  // namespace logging
}  // namespace absl

#define LOG(severity)                                                       \
  (::absl::MinLogLevel() > ::absl::LOG_##severity)                          \
      ? 0                                                                   \
      : ::absl::logging::Die(::absl::LOG_##severity >= ::absl::LOG_FATAL) & \
            std::cerr << ::absl::logging::BaseName(__FILE__) << "("         \
                      << __LINE__ << ") "                                   \
                      << "LOG(" << #severity << ") "

#endif  // ABSL_LOG_LOG_H_
