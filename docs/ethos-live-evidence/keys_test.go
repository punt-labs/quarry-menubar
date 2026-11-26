package hook

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"sort"
	"testing"
)

func TestQuarryLiveTreeKeys(t *testing.T) {
	root := os.Getenv("QUARRY_EVIDENCE_ROOT")
	if root == "" {
		t.Fatal("QUARRY_EVIDENCE_ROOT is required")
	}
	ctx, cancel := context.WithTimeout(context.Background(), gateInputTime)
	defer cancel()
	paths, err := worktreeSnapshotInputs(ctx, root)
	if err != nil {
		t.Fatal(err)
	}
	state, proof, err := handoffGateInputs(ctx, root, paths)
	if err != nil {
		t.Fatal(err)
	}
	sort.Strings(paths)
	payload, err := json.Marshal(map[string]any{"state": state, "proof": proof, "paths": paths})
	if err != nil {
		t.Fatal(err)
	}
	fmt.Printf("QUARRY_TREE_KEYS %s\n", payload)
}
