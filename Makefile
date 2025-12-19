# PowerUserMail Makefile — developer ergonomics

# Defaults (can be overridden: make build CONFIGURATION=Release)
SCHEME ?= PowerUserMail
CONFIGURATION ?= Debug
DESTINATION ?= platform=macOS
PROJECT ?= PowerUserMail.xcodeproj
BUILD_DIR ?= build

XCODEBUILD = xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIGURATION) -destination '$(DESTINATION)' -derivedDataPath $(BUILD_DIR)

.PHONY: help build test unit-test ui-test quicktest run perf clean archive ci dev dev-test format lint open-logs open-test-results

help:
	@echo "Targets:"
	@echo "  build       - Build the app"
	@echo "  test        - Run all tests (unit + UI)"
	@echo "  unit-test   - Run unit tests only"
	@echo "  quicktest   - Fast feedback: unit tests only, parallel enabled"
	@echo "  ui-test     - Run UI tests only (requires Accessibility/Automation perms)"
	@echo "  run         - Open the built app"
	@echo "  dev         - Watch files & rebuild on change (requires 'entr' or 'fswatch')"
	@echo "  dev-test    - Watch files & rerun unit tests on change"
	@echo "  perf        - Run performance tests"
	@echo "  clean       - Clean build artifacts"
	@echo "  archive     - Create an xcarchive"
	@echo "  ci          - Build, test, perf (CI-friendly)"
	@echo "  format      - Run swiftformat if installed"
	@echo "  lint        - Run swiftlint if installed"
	@echo "  open-logs   - Open Xcode build logs"
	@echo "  open-test-results - Open latest xcresult bundle"

build:
	@echo "[Build] $(SCHEME) ($(CONFIGURATION))"
	@if command -v xcpretty >/dev/null 2>&1; then \
		$(XCODEBUILD) build | xcpretty; \
	else \
		$(XCODEBUILD) build; \
	fi

clean:
	@echo "[Clean] Removing derived data in $(BUILD_DIR)"
	@if command -v xcpretty >/dev/null 2>&1; then \
		$(XCODEBUILD) clean | xcpretty; \
	else \
		$(XCODEBUILD) clean; \
	fi
	@rm -rf $(BUILD_DIR)

# Runs both unit and UI tests if the scheme contains them
# You can narrow tests via: make test DESTINATION="platform=macOS,name=Any Mac"

test:
	@echo "[Test] $(SCHEME) on $(DESTINATION)"
	@if command -v xcpretty >/dev/null 2>&1; then \
		$(XCODEBUILD) test | xcpretty; \
	else \
		$(XCODEBUILD) test; \
	fi

# Unit tests only (skips UI tests)
unit-test:
	@echo "[Unit Test] $(SCHEME) on $(DESTINATION)"
	@if command -v xcpretty >/dev/null 2>&1; then \
		$(XCODEBUILD) test -only-testing:PowerUserMailTests | xcpretty; \
	else \
		$(XCODEBUILD) test -only-testing:PowerUserMailTests; \
	fi

# Fast feedback target: unit tests only with parallelization
quicktest:
	@echo "[Quick Test] $(SCHEME) on $(DESTINATION) (parallel)"
	@if command -v xcpretty >/dev/null 2>&1; then \
		$(XCODEBUILD) test -only-testing:PowerUserMailTests -parallel-testing-enabled YES -parallel-testing-worker-count 8 | xcpretty; \
	else \
		$(XCODEBUILD) test -only-testing:PowerUserMailTests -parallel-testing-enabled YES -parallel-testing-worker-count 8; \
	fi

# UI tests only (requires macOS Accessibility/Automation permissions)
ui-test:
	@echo "[UI Test] $(SCHEME) on $(DESTINATION)"
	@echo "Ensure System Settings > Privacy & Security > Accessibility/Automation allow Terminal/Xcode."
	@if command -v xcpretty >/dev/null 2>&1; then \
		$(XCODEBUILD) test -only-testing:PowerUserMailUITests | xcpretty; \
	else \
		$(XCODEBUILD) test -only-testing:PowerUserMailUITests; \
	fi

# Opens the built app from derived data products
run:
	@APP_PATH="$(BUILD_DIR)/Build/Products/$(CONFIGURATION)/PowerUserMail.app"; \
	if [ -d "$$APP_PATH" ]; then \
		echo "[Run] Stopping any running PowerUserMail instances..."; \
		pkill -x PowerUserMail 2>/dev/null || true; \
		sleep 0.5; \
		echo "[Run] Opening $$APP_PATH"; \
		open "$$APP_PATH"; \
	else \
		echo "[Run] App not found at $$APP_PATH. Run 'make build' first."; \
		exit 1; \
	fi

# Delegates to existing performance test script
perf:
	@echo "[Perf] Running performance tests via scripts/run_performance_tests.sh"
	@bash scripts/run_performance_tests.sh

archive:
	@echo "[Archive] Creating xcarchive in $(BUILD_DIR)/archive"
	@mkdir -p $(BUILD_DIR)/archive
	@if command -v xcpretty >/dev/null 2>&1; then \
		$(XCODEBUILD) archive -archivePath $(BUILD_DIR)/archive/PowerUserMail.xcarchive | xcpretty; \
	else \
		$(XCODEBUILD) archive -archivePath $(BUILD_DIR)/archive/PowerUserMail.xcarchive; \
	fi

ci:
	@$(MAKE) clean
	@$(MAKE) build
	@$(MAKE) test
	@$(MAKE) perf || true

format:
	@echo "[Format] Running swiftformat (if installed)"
	@command -v swiftformat >/dev/null 2>&1 && swiftformat PowerUserMail || echo "swiftformat not installed"

lint:
	@echo "[Lint] Running swiftlint (if installed)"
	@command -v swiftlint >/dev/null 2>&1 && swiftlint || echo "swiftlint not installed"

open-logs:
	@LOG_DIR="$(BUILD_DIR)/Logs/Build"; \
	if [ -d "$$LOG_DIR" ]; then \
		echo "[Logs] Opening $$LOG_DIR"; \
		open "$$LOG_DIR"; \
	else \
		echo "[Logs] Not found: $$LOG_DIR"; \
	fi

open-test-results:
	@RES_DIR="$(BUILD_DIR)/Logs/Test"; \
	if [ -d "$$RES_DIR" ]; then \
		LATEST=$$(ls -t "$$RES_DIR"/*.xcresult 2>/dev/null | head -n1); \
		if [ -n "$$LATEST" ]; then \
			echo "[Results] Opening $$LATEST"; \
			open "$$LATEST"; \
		else \
			echo "[Results] No xcresult bundles found in $$RES_DIR"; \
		fi; \
	else \
		echo "[Results] Not found: $$RES_DIR"; \
	fi

dev:
	@echo "[Dev] Watching PowerUserMail/ for changes..."
	@echo "Tip: Press Ctrl+C to stop."
	@if command -v entr >/dev/null 2>&1; then \
		while true; do \
			find PowerUserMail -type f \( -name "*.swift" -o -name "*.entitlements" -o -name "*.plist" \) 2>/dev/null | \
			entr -d sh -c 'if make build; then make run; fi'; \
		done; \
	elif command -v fswatch >/dev/null 2>&1; then \
		fswatch -r PowerUserMail --event Created --event Updated --event Removed | \
		while read -r event; do \
			if make build; then make run; fi; \
		done; \
	else \
		echo "[Dev] ERROR: 'entr' or 'fswatch' not found."; \
		echo "Install via:"; \
		echo "  brew install entr        # Recommended (simpler)"; \
		echo "  brew install fswatch     # Alternative"; \
		exit 1; \
	fi

dev-test:
	@echo "[Dev Test] Watching PowerUserMail/ for changes..."
	@echo "Tip: Press Ctrl+C to stop."
	@if command -v entr >/dev/null 2>&1; then \
		find PowerUserMail -type f \( -name "*.swift" -o -name "*.entitlements" -o -name "*.plist" \) | entr -r make unit-test; \
	elif command -v fswatch >/dev/null 2>&1; then \
		fswatch -r PowerUserMail --event Created --event Updated --event Removed | xargs -n 1 -I {} make unit-test; \
	else \
		echo "[Dev Test] ERROR: 'entr' or 'fswatch' not found."; \
		echo "Install via:"; \
		echo "  brew install entr        # Recommended (simpler)"; \
		echo "  brew install fswatch     # Alternative"; \
		exit 1; \
	fi
