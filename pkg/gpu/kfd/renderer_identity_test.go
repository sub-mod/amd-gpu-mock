package kfd

import (
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func TestKFDDecimalUniqueID(t *testing.T) {
	p := profilesForTest(t)["mi300x"]
	for _, input := range []string{"0x9c4f000000000001", "11263221293014450177", "18446744073709551615", "0", ""} {
		t.Run(input, func(t *testing.T) {
			root := t.TempDir()
			dev := p.Devices[0]
			dev.UniqueID = input
			if err := NewRenderer(p, root).renderGPUNode(root, &dev); err != nil {
				t.Fatal(err)
			}
			b, err := os.ReadFile(filepath.Join(root, "properties"))
			if err != nil {
				t.Fatal(err)
			}
			var got string
			for _, line := range strings.Split(string(b), "\n") {
				if strings.HasPrefix(line, "unique_id ") {
					got = strings.TrimPrefix(line, "unique_id ")
				}
			}
			actual, err := strconv.ParseUint(got, 10, 64)
			if err != nil {
				t.Fatalf("not a decimal kernel property: %q", got)
			}
			var expected uint64
			if input != "" {
				base := 10
				if strings.HasPrefix(input, "0x") {
					base = 0
				}
				expected, err = strconv.ParseUint(input, base, 64)
				if err != nil {
					t.Fatal(err)
				}
			}
			if actual != expected {
				t.Fatalf("identity changed: %d != %d", actual, expected)
			}
		})
	}
	dev := p.Devices[0]
	dev.UniqueID = "not-a-number"
	if err := NewRenderer(p, t.TempDir()).renderGPUNode(t.TempDir(), &dev); err == nil {
		t.Fatal("invalid identity accepted")
	}
}
