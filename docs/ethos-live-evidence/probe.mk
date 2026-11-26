.PHONY: quarry-evidence-write
check: quarry-evidence-write
quarry-evidence-write:
	python3 "$(QUARRY_EVIDENCE_SCRIPT)" write LICENSE
