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
	"context"
	"time"

	networkingv1 "k8s.io/api/networking/v1"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/klog/v2"
	ctrlClient "sigs.k8s.io/controller-runtime/pkg/client"
)

const (
	ingressPollInterval = 30 * time.Second
	ingressPollTimeout  = 45 * time.Minute
)

func fetchIngress(ctx context.Context, cli ctrlClient.Client, key ctrlClient.ObjectKey) (*networkingv1.Ingress, error) {
	obj := &networkingv1.Ingress{}
	return obj, cli.Get(ctx, key, obj)
}

func WaitForIngress(ctx context.Context, cli ctrlClient.Client, ingressObjectKey ctrlClient.ObjectKey) (string, error) {
	var ingressIP string
	err := wait.PollUntilContextTimeout(ctx, ingressPollInterval, ingressPollTimeout, true, func(ctx context.Context) (done bool, err error) {
		ing, err := fetchIngress(ctx, cli, ingressObjectKey)
		if err != nil {
			klog.Infof("fetchIngress(%s)=%v", ingressObjectKey, err)
			return false, nil
		}
		ingressIPs := ing.Status.LoadBalancer.Ingress
		if len(ingressIPs) < 1 || ingressIPs[0].IP == "" {
			klog.Infof("Invalid ingress IP %s when fetchIngress(%s)", ingressIPs, ingressObjectKey)
			return false, nil
		}
		ingressIP = ingressIPs[0].IP
		return true, nil
	})
	return ingressIP, err
}
