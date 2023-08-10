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
	"reflect"
	"testing"

	"github.com/kr/pretty"
	corev1 "k8s.io/api/core/v1"
	v1 "k8s.io/api/core/v1"
	networkingv1 "k8s.io/api/networking/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/util/intstr"

	ctrlClient "sigs.k8s.io/controller-runtime/pkg/client"
)

func TestParseK8sYAML(t *testing.T) {
	headerText := `# Copyright 2023 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#   https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

`

	svcText := `apiVersion: v1
kind: Service
metadata:
  name: bar
  annotations:
    cloud.google.com/neg: '{"ingress": true}'
spec:
  ports:
  - port: 80
    targetPort: 8080
    name: http
  selector:
    app: bar
  type: ClusterIP`
	svc := &corev1.Service{
		ObjectMeta: metav1.ObjectMeta{
			Name: "bar",
			Annotations: map[string]string{
				"cloud.google.com/neg": "{\"ingress\": true}",
			},
		},
		TypeMeta: metav1.TypeMeta{
			Kind:       "Service",
			APIVersion: "v1",
		},
		Spec: v1.ServiceSpec{
			Ports: []v1.ServicePort{
				{
					Name:       "http",
					Port:       80,
					TargetPort: intstr.FromInt(8080),
				},
			},
			Selector: map[string]string{"app": "bar"},
			Type:     v1.ServiceTypeClusterIP,
		},
	}

	ingText := `apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: foo-internal
  annotations:
    kubernetes.io/ingress.class: 'gce-internal'
spec:
  rules:
    - http:
        paths:
        - path: /foo
          pathType: Prefix
          backend:
            service:
              name: foo
              port:
                number: 80`
	prefix := networkingv1.PathTypePrefix
	ing := &networkingv1.Ingress{
		ObjectMeta: metav1.ObjectMeta{
			Name: "foo-internal",
			Annotations: map[string]string{
				"kubernetes.io/ingress.class": "gce-internal",
			},
		},
		TypeMeta: metav1.TypeMeta{
			Kind:       "Ingress",
			APIVersion: "networking.k8s.io/v1",
		},
		Spec: networkingv1.IngressSpec{
			Rules: []networkingv1.IngressRule{
				{
					IngressRuleValue: networkingv1.IngressRuleValue{
						HTTP: &networkingv1.HTTPIngressRuleValue{
							Paths: []networkingv1.HTTPIngressPath{
								{
									Path:     "/foo",
									PathType: &prefix,
									Backend: networkingv1.IngressBackend{
										Service: &networkingv1.IngressServiceBackend{
											Name: "foo",
											Port: networkingv1.ServiceBackendPort{
												Number: int32(80),
											},
										},
									},
								},
							},
						},
					},
				},
			},
		},
	}
	testCases := []struct {
		desc          string
		yamlText      string
		expectObjects []ctrlClient.Object
		expectNil     bool
	}{
		{
			desc:          "YAML TEXT contains headers and one properly formed object. Comments should be ignored.",
			yamlText:      headerText + svcText,
			expectObjects: []ctrlClient.Object{svc},
			expectNil:     true,
		},
		{
			desc:          "Properly formed yaml, with one k8s object",
			yamlText:      svcText,
			expectObjects: []ctrlClient.Object{svc},
			expectNil:     true,
		},
		{
			desc:          "Properly formed yaml, with multiple k8s objects",
			yamlText:      svcText + "\n---\n" + ingText,
			expectObjects: []ctrlClient.Object{svc, ing},
			expectNil:     true,
		},
		{
			desc:          "Properly formed yaml, contains invalid k8s object",
			yamlText:      svcText + "\n---\n" + "apiVersion: networking.k8s.io/v1\n", // Object missing kind
			expectObjects: nil,
			expectNil:     false,
		},
		{
			desc:          "Empty text",
			yamlText:      "",
			expectObjects: nil,
			expectNil:     true,
		},
	}

	for _, tc := range testCases {
		t.Run(tc.desc, func(t *testing.T) {
			gotObjects, err := ParseK8sYAML(tc.yamlText)

			if tc.expectNil && (err != nil) {
				t.Fatalf("Expect error to be nil, got %v", err)
			}
			if !tc.expectNil && (err == nil) {
				t.Fatal("Expect error to be NOT nil, got nil")
			}

			// Compare if we have the same set of objects.
			if len(tc.expectObjects) != len(gotObjects) {
				t.Fatalf("Expect %d objects, got %d", len(tc.expectObjects), len(gotObjects))
			}
			var match int
			for _, gotObj := range gotObjects {
				for _, expectObj := range tc.expectObjects {
					if reflect.DeepEqual(gotObj, expectObj) {
						match += 1
					}
				}
			}
			if len(tc.expectObjects) != match {
				t.Fatalf("Expect %d matching objects, got %d. Expect objects: %v, gotObjects: %v.", len(tc.expectObjects), match, pretty.Sprint(tc.expectObjects), pretty.Sprint(gotObjects))
			}
		})

	}
}
