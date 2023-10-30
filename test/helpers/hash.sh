#!/bin/bash

# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Genereate a hash of length 20 using sha1 checksum and take the first 20 characters.
# Argument:
#   Value to be hashed, a string
# Outputs:
#   Writes the hashed result to stdout.
get_hash() {
    # By default, sha1sum prints out hash and filename, so we only access the 
    # [0] element for the hash.
    local h
    h=($(echo -n $1 | sha1sum))
    echo "${h:0:20}"
}
