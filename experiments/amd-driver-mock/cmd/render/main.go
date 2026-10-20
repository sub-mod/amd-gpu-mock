// SPDX-License-Identifier: Apache-2.0
// Adapter: reuse the original profile and renderer, not a second fake inventory.
package main

import (
	"flag"
	"github.com/amd-gpu-mock/pkg/gpu/kfd"
	"gopkg.in/yaml.v3"
	"log"
	"os"
)

func main() {
	profile := flag.String("profile", "profiles/mi300x.yaml", "original profile")
	root := flag.String("root", "tmp/hami/state", "output root")
	flag.Parse()
	b, err := os.ReadFile(*profile)
	if err != nil {
		log.Fatal(err)
	}
	var p kfd.Profile
	if err = yaml.Unmarshal(b, &p); err != nil {
		log.Fatal(err)
	}
	if len(p.Devices) < 1 {
		log.Fatal("empty inventory")
	}
	p.Devices = p.Devices[:1]
	if err = kfd.NewRenderer(&p, *root).RenderAll(); err != nil {
		log.Fatal(err)
	}
	log.Printf("rendered one %s using original profile/renderer", p.DeviceDefault.Name)
}
