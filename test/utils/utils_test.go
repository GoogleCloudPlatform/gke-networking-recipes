// Copyright 2023 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

package utils

import (
	"errors"
	"fmt"
	"testing"

	"google.golang.org/api/googleapi"
)

func TestIsHTTPErrorCode(t *testing.T) {
	t.Parallel()

	for _, tc := range []struct {
		desc   string
		err    error
		code   int
		expect bool
	}{
		{"nil error", nil, 400, false},
		{"Random error", errors.New("xxx"), 400, false},
		{"Error with code 200", &googleapi.Error{Code: 200}, 400, false},
		{"Error with code 400", &googleapi.Error{Code: 400}, 400, true},
		{"Wrapped error with code 200", fmt.Errorf("%w", &googleapi.Error{Code: 200}), 400, false},
		{"Wrapped error with code 400", fmt.Errorf("%w", &googleapi.Error{Code: 400}), 400, true},
		{"Double wrapped error with code 200", fmt.Errorf("%w: %w", &googleapi.Error{Code: 200}, errors.New("xxx")), 400, false},
		{"Double wrapped error with code 400", fmt.Errorf("%w: %w", &googleapi.Error{Code: 400}, errors.New("xxx")), 400, true},
	} {
		got := isHTTPErrorCode(tc.err, tc.code)
		if got != tc.expect {
			t.Errorf("IsHTTPErrorCode(%v, %d) = %t; want %t", tc.err, tc.code, got, tc.expect)
		}
	}
}

func TestGetRegionFromZone(t *testing.T) {
	testCases := []struct {
		desc   string
		zone   string
		expect string
	}{
		{
			desc:   "US zone",
			zone:   "us-west1-a",
			expect: "us-west1",
		},
		{
			desc:   "EU zone",
			zone:   "eu-west1-a",
			expect: "eu-west1",
		},
		{
			desc:   "invalid zone",
			zone:   "uswest1",
			expect: "",
		},
	}
	for _, tc := range testCases {
		t.Run(tc.desc, func(t *testing.T) {
			got := getRegionFromZone(tc.zone)
			if tc.expect != got {
				t.Errorf("Expect %s, got %s", tc.expect, got)
			}
		})
	}
}
