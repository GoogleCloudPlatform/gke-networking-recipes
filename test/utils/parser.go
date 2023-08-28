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
	"fmt"
	"os"
	"regexp"
	"strings"

	"k8s.io/client-go/kubernetes/scheme"
	v1 "k8s.io/ingress-gce/pkg/apis/backendconfig/v1"
	"k8s.io/klog/v2"
	ctrlClient "sigs.k8s.io/controller-runtime/pkg/client"
	"sigs.k8s.io/yaml"
)

type ParsedObjects struct {
	K8sObjects []ctrlClient.Object
	BeConfigs  []v1.BackendConfig
}

func NewParsedObjects() *ParsedObjects {
	return &ParsedObjects{
		K8sObjects: []ctrlClient.Object{},
		BeConfigs:  []v1.BackendConfig{},
	}
}

// ParseK8sYaml takes a yaml file path to create a list of runtime objects.
func ParseK8sYamlFile(filePath string) (*ParsedObjects, error) {
	klog.Infof("Parse K8s resources from path %s.", filePath)

	yamlText, err := os.ReadFile(filePath)
	if err != nil {
		return nil, err
	}
	return ParseK8sYAML(string(yamlText))
}

// ParseK8sYaml converts a yaml text to a list of runtime objects.
func ParseK8sYAML(yamlText string) (*ParsedObjects, error) {
	sepYamlfiles := regexp.MustCompile("\n---\n").Split(string(yamlText), -1)

	retVal := NewParsedObjects()
	for _, f := range sepYamlfiles {
		f = strings.TrimSpace(f)
		if f == "\n" || f == "" {
			// ignore empty cases
			continue
		}

		if strings.Contains(f, "kind: BackendConfig") {
			backendConfig := v1.BackendConfig{}
			err := yaml.Unmarshal([]byte(f), &backendConfig)
			if err != nil {
				return nil, fmt.Errorf("failed to decode YAML text: %w", err)
			}
			retVal.BeConfigs = append(retVal.BeConfigs, backendConfig)
			continue
		}

		decode := scheme.Codecs.UniversalDeserializer().Decode
		runtimeObj, _, err := decode([]byte(f), nil, nil)
		if err != nil {
			return NewParsedObjects(), fmt.Errorf("failed to decode YAML text: %w", err)
		}

		clientObj, ok := runtimeObj.(ctrlClient.Object)
		if !ok {
			return NewParsedObjects(), fmt.Errorf("cast failed: want Object, got %T", runtimeObj)
		}
		retVal.K8sObjects = append(retVal.K8sObjects, clientObj)
	}
	return retVal, nil
}
