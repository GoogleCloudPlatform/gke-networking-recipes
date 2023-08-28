// Copyright 2019 Google LLC
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

package test

import (
	"context"
	"fmt"
	"math/rand"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"time"

	"google.golang.org/api/compute/v1"
	"k8s.io/apimachinery/pkg/util/wait"
	"k8s.io/klog/v2"
)

const (
	ilbSubnetPurpose = "REGIONAL_MANAGED_PROXY"
	ilbSubnetRole    = "ACTIVE"

	sshFirewallAction = "allow"

	lbPollInterval = 10 * time.Second
	lbPollTimeout  = 20 * time.Minute
)

var podNameRE = regexp.MustCompile(`"pod_name":"([^"]*)"`)

func setEnvProject(project string) error {
	if out, err := exec.Command("gcloud", "config", "set", "project", project).CombinedOutput(); err != nil {
		return fmt.Errorf("setEnvProject(%q) failed: %q: %w", project, out, err)
	}

	return os.Setenv("PROJECT", project)
}

func randSeq(n int) string {
	letterBytes := "0123456789abcdef"
	b := make([]byte, n)
	for i := range b {
		b[i] = letterBytes[rand.Intn(len(letterBytes))]
	}
	return string(b)
}

func buildProxyOnlySubnet(subnetName, region, networkSelfLink string) *compute.Subnetwork {
	return &compute.Subnetwork{
		Name:        subnetName,
		Purpose:     ilbSubnetPurpose,
		Role:        ilbSubnetRole,
		Network:     networkSelfLink,
		IpCidrRange: "10.129.0.0/23",
	}
}

func buildAllowProxyConnectionFirewall(firewallName, networkSelfLink string) *compute.Firewall {
	return &compute.Firewall{
		Name:    firewallName,
		Network: networkSelfLink,
		SourceRanges: []string{
			"10.129.0.0/23",
		},
		Allowed: []*compute.FirewallAllowed{
			{
				IPProtocol: "tcp",
				Ports:      []string{"8080"},
			},
		},
	}
}

func buildAllowSSHFirewall(firewallName, networkSelfLink string) *compute.Firewall {
	return &compute.Firewall{
		Name:       firewallName,
		Network:    networkSelfLink,
		Direction:  "Ingress",
		TargetTags: []string{"allow-ssh"},
		Allowed: []*compute.FirewallAllowed{
			{
				IPProtocol: "tcp",
				Ports:      []string{"22"},
			},
		},
	}
}

func buildTestInstance(instanceName, networkSelfLink, subnetSelfLink, zone string) *compute.Instance {
	return &compute.Instance{
		Name: instanceName,
		Disks: []*compute.AttachedDisk{
			{
				InitializeParams: &compute.AttachedDiskInitializeParams{
					DiskSizeGb:  10,
					SourceImage: "projects/debian-cloud/global/images/family/debian-11",
				},
				AutoDelete: true,
				Boot:       true,
			},
		},
		Tags: &compute.Tags{
			Items: []string{"allow-ssh"},
		},
		MachineType: fmt.Sprintf("zones/%s/machineTypes/n1-standard-1", zone),
		NetworkInterfaces: []*compute.NetworkInterface{
			{
				Network:         networkSelfLink,
				Subnetwork:      subnetSelfLink,
				ForceSendFields: []string{"Network", "Subnetwork"},
			},
		},
	}
}

func validatePodName(response []byte, expectPodName string) error {
	matches := podNameRE.FindStringSubmatch(string(response))
	if len(matches) == 0 {
		return fmt.Errorf("not matches found")
	}
	gotPodName := matches[0]
	if !strings.Contains(gotPodName, expectPodName) {
		return fmt.Errorf("Expect response from %s, got %s", expectPodName, gotPodName)
	}
	return nil
}

func checkHTTPViaVM(address, instanceName, zone string, checkReponse func(response []byte) error) error {
	klog.Infof("SSH into instance %s in zone %s, and send traffic to address %s", instanceName, zone, address)
	params := []string{
		"compute",
		"ssh",
		instanceName,
		"--zone", zone,
		"--ssh-flag=-t", // Allocate pseudo-terminal to get rid of `Pseudo-terminal will not be allocated because stdin is not a terminal.` message in response.
		"--ssh-flag=-q", // Use quite mode to get rid of `Connection to xx.xxx.xx.xxx closed' message in reponse.
		"--",
		"curl", address,
	}
	klog.Infof("Command is: %s", exec.Command("gcloud", params...).String())

	err := wait.PollUntilContextTimeout(context.TODO(), lbPollInterval, lbPollTimeout, true, func(ctx context.Context) (done bool, err error) {
		// exec Command can only be executed once.
		// So a new command needs to be genereated for each run.
		out, err := exec.Command("gcloud", params...).CombinedOutput()
		if err != nil {
			klog.Errorf("checkHTTPViaVM(%s, %s, %s) failed: %q: %v", address, instanceName, zone, out, err)
			return false, nil
		}
		if err := checkReponse(out); err != nil {
			klog.Error("checkHTTPViaVM(%s, %s, %s) failed to check response: %v", address, instanceName, zone, err)
			return false, nil
		}
		return true, nil
	})
	return err
}
