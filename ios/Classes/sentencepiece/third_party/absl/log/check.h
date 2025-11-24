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

#ifndef ABSL_LOG_CHECK_H_
#define ABSL_LOG_CHECK_H_

#include <iostream>

#include "third_party/absl/log/log.h"

#define CHECK(condition)                                                    \
  (condition) ? 0                                                           \
              : ::absl::logging::Die(true) &                                \
                    std::cerr << ::absl::logging::BaseName(__FILE__) << "(" \
                              << __LINE__ << ") [" << #condition << "] "

#define CHECK_EQ(a, b) CHECK((a) == (b))
#define CHECK_NE(a, b) CHECK((a) != (b))
#define CHECK_GE(a, b) CHECK((a) >= (b))
#define CHECK_LE(a, b) CHECK((a) <= (b))
#define CHECK_GT(a, b) CHECK((a) > (b))
#define CHECK_LT(a, b) CHECK((a) < (b))

#define QCHECK CHECK
#define QCHECK_EQ CHECK_EQ
#define QCHECK_NE CHECK_NE
#define QCHECK_GE CHECK_GE
#define QCHECK_LE CHECK_LE
#define QCHECK_GT CHECK_GT
#define QCHECK_LT CHECK_LT

#define CHECK_OK(expr)                         \
  do {                                         \
    const auto _status = expr;                 \
    CHECK(_status.ok()) << _status.ToString(); \
  } while (0)

#define QCHECK_OK CHECK_OK

#endif  // ABSL_LOG_CHECK_H_
