# Quarry Menu Bar - CLI Build Commands
# Usage: make <target>

SCHEME = QuarryMenuBar
DESTINATION = platform=macOS
DERIVED_DATA = ./DerivedData
TEST_DERIVED_DATA ?= $(DERIVED_DATA)
PROJECT_DIR = build/xcodegen
PROJECT = $(PROJECT_DIR)/$(SCHEME).xcodeproj

.PHONY: help generate build test clean lint format format-check check all run version bump-patch bump-minor bump-major bump-build

help:
	@echo "Available commands:"
	@echo ""
	@echo "  Development:"
	@echo "    make generate    - Regenerate Xcode project from project.yml"
	@echo "    make format      - Run SwiftFormat to auto-format code"
	@echo "    make format-check - Check SwiftFormat without changing source"
	@echo "    make lint        - Run SwiftLint on source files"
	@echo "    make build       - Build the app (runs format + lint first)"
	@echo "    make test        - Run unit tests"
	@echo "    make check       - Check formatting, lint, and run unit tests"
	@echo "    make coverage    - Run tests with code coverage report"
	@echo "    make clean       - Clean build artifacts"
	@echo "    make run         - Build and launch the menu bar app"
	@echo "    make all         - Generate, format, lint, build, and test"
	@echo ""
	@echo "  Versioning:"
	@echo "    make version     - Show current version and build number"
	@echo "    make bump-patch  - Bump patch version (0.1.0 -> 0.1.1)"
	@echo "    make bump-minor  - Bump minor version (0.1.0 -> 0.2.0)"
	@echo "    make bump-major  - Bump major version (0.1.0 -> 1.0.0)"

# XcodeGen emits project-relative paths for the app plist and entitlements.
generate:
	@echo "Generating Xcode project..."
	@mkdir -p "$(PROJECT_DIR)"
	@ln -sfn "$(CURDIR)/QuarryMenuBar" "$(PROJECT_DIR)/QuarryMenuBar"
	xcodegen generate --project "$(PROJECT_DIR)"

format:
	@echo "Running SwiftFormat..."
	@if command -v swiftformat >/dev/null 2>&1; then \
		swiftformat . --quiet && \
		echo "SwiftFormat: Complete."; \
	else \
		echo "SwiftFormat not installed. Install with: brew install swiftformat"; \
		exit 1; \
	fi

format-check:
	swiftformat QuarryMenuBar QuarryMenuBarTests --lint

lint:
	@echo "Running SwiftLint..."
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --quiet || { echo "SwiftLint found violations. Fix them before continuing." >&2; exit 1; }; \
		echo "SwiftLint: No violations found."; \
	else \
		echo "SwiftLint not installed. Install with: brew install swiftlint"; \
		exit 1; \
	fi

build: generate format lint
	@echo "Building $(SCHEME)..."
	xcodebuild build \
		-project "$(PROJECT)" \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA) \
		-quiet

test: generate
	@echo "Running unit tests..."
	@xcodebuild test \
		-project "$(PROJECT)" \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-derivedDataPath "$(TEST_DERIVED_DATA)" \
		-only-testing:QuarryMenuBarTests \
		-quiet

clean:
	@echo "Cleaning..."
	xcodebuild clean -project "$(PROJECT)" -scheme $(SCHEME) -derivedDataPath $(DERIVED_DATA) -quiet 2>/dev/null || true
	rm -rf $(DERIVED_DATA)
	@echo "Clean complete."

coverage: generate
	@echo "Running unit tests with coverage..."
	@xcodebuild test \
		-project "$(PROJECT)" \
		-scheme $(SCHEME) \
		-destination '$(DESTINATION)' \
		-derivedDataPath $(DERIVED_DATA) \
		-only-testing:QuarryMenuBarTests \
		-enableCodeCoverage YES \
		-resultBundlePath ./build/TestResults.xcresult \
		2>&1 | grep -E "(Executed|TEST SUCCEEDED|TEST FAILED)" | tail -3
	@echo ""
	@echo "Extracting coverage data..."
	@xcrun xccov view --report --json ./build/TestResults.xcresult 2>/dev/null | \
		python3 -c "import json,sys; d=json.load(sys.stdin); \
		targets=[t for t in d.get('targets',[]) if t.get('name')=='QuarryMenuBar.app']; \
		cov=targets[0].get('lineCoverage',0)*100 if targets else 0; \
		print(f'Line Coverage: {cov:.1f}%')" 2>/dev/null || echo "Could not parse coverage report."

run: build
	@echo "Launching $(SCHEME)..."
	@open $(DERIVED_DATA)/Build/Products/Debug/QuarryMenuBar.app

all: generate format lint build test
	@echo "All steps complete."

check: format-check lint test
	@echo "make check: format-check + lint + test passed."

# =============================================================================
# Versioning
# =============================================================================

VERSION := $(shell grep 'MARKETING_VERSION:' project.yml | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')
BUILD := $(shell grep 'CURRENT_PROJECT_VERSION:' project.yml | head -1 | sed 's/.*: *"\([^"]*\)".*/\1/')

version:
	@echo "Version: $(VERSION) (build $(BUILD))"

bump-patch:
	@echo "Bumping patch version..."
	@NEW_VERSION=$$(echo $(VERSION) | awk -F. '{print $$1"."$$2"."$$3+1}'); \
	sed -i '' "s/MARKETING_VERSION: \"$(VERSION)\"/MARKETING_VERSION: \"$$NEW_VERSION\"/" project.yml; \
	echo "Version: $(VERSION) -> $$NEW_VERSION"

bump-minor:
	@echo "Bumping minor version..."
	@NEW_VERSION=$$(echo $(VERSION) | awk -F. '{print $$1"."$$2+1".0"}'); \
	sed -i '' "s/MARKETING_VERSION: \"$(VERSION)\"/MARKETING_VERSION: \"$$NEW_VERSION\"/" project.yml; \
	echo "Version: $(VERSION) -> $$NEW_VERSION"

bump-major:
	@echo "Bumping major version..."
	@NEW_VERSION=$$(echo $(VERSION) | awk -F. '{print $$1+1".0.0"}'); \
	sed -i '' "s/MARKETING_VERSION: \"$(VERSION)\"/MARKETING_VERSION: \"$$NEW_VERSION\"/" project.yml; \
	echo "Version: $(VERSION) -> $$NEW_VERSION"

bump-build:
	@echo "Bumping build number..."
	@NEW_BUILD=$$(($(BUILD) + 1)); \
	sed -i '' "s/CURRENT_PROJECT_VERSION: \"$(BUILD)\"/CURRENT_PROJECT_VERSION: \"$$NEW_BUILD\"/" project.yml; \
	echo "Build: $(BUILD) -> $$NEW_BUILD"
