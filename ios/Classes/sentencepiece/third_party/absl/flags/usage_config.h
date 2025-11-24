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

#ifndef ABSL_FLAGS_USAGE_CONFIG_H_
#define ABSL_FLAGS_USAGE_CONFIG_H_

#include <functional>
#include <string>

namespace absl {

struct FlagsUsageConfig {
  std::function<std::string()> version_string;
};

void SetFlagsUsageConfig(FlagsUsageConfig usage_config);

}  // namespace absl

#endif  // ABSL_FLAGS_USAGE_CONFIG_H_
