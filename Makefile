# Define a directory for dependencies in the user's home folder
DEPS_DIR := $(HOME)/VoiceInk-Dependencies
WHISPER_CPP_DIR := $(DEPS_DIR)/whisper.cpp
FRAMEWORK_PATH := $(WHISPER_CPP_DIR)/build-apple/whisper.xcframework
STATIC_WHISPER_XCFRAMEWORK_CHECK := scripts/verify-static-whisper-xcframework.sh
STATIC_WHISPER_APP_CHECK := scripts/verify-static-whisper-app.sh
ADHOC_LIBRARY_VALIDATION_CHECK := scripts/verify-adhoc-library-validation.sh
LOCAL_DERIVED_DATA := $(CURDIR)/.local-build
LOCAL_APP_DEST := $(HOME)/Applications/roma just talk.app
LATENCY_HARNESS := $(LOCAL_DERIVED_DATA)/Tools/VisibleTextLatencyHarness
LATENCY_HARNESS_SOURCE := Tools/VisibleTextLatencyHarness/VisibleTextLatencyHarness.swift
LATENCY_HARNESS_INFO_PLIST := Tools/VisibleTextLatencyHarness/Info.plist
LATENCY_HARNESS_APP := $(LOCAL_DERIVED_DATA)/Tools/VisibleTextLatencyHarness.app
LATENCY_HARNESS_APP_EXECUTABLE := $(LATENCY_HARNESS_APP)/Contents/MacOS/VisibleTextLatencyHarness
LATENCY_HARNESS_BUNDLE_ID ?= com.happyf.roma-just-talk.VisibleTextLatencyHarness
LATENCY_HARNESS_REPORT ?= $(LOCAL_DERIVED_DATA)/Tools/visible-text-latency.json
LATENCY_HARNESS_STDOUT ?= $(LOCAL_DERIVED_DATA)/Tools/visible-text-latency.out.log
LATENCY_HARNESS_STDERR ?= $(LOCAL_DERIVED_DATA)/Tools/visible-text-latency.err.log
CONFIGURATION ?= Debug
LATENCY_EXPECTED ?=
LATENCY_SAMPLES ?= 5
LATENCY_TRIGGER ?= left-shift
LATENCY_THRESHOLD_MS ?= 440
RUNTIME_E2E_PACKAGE := Tools/RuntimeE2EHarness
RUNTIME_E2E_SCRATCH := $(LOCAL_DERIVED_DATA)/RuntimeE2EHarness
RUNTIME_E2E_BINARY := $(RUNTIME_E2E_SCRATCH)/release/RuntimeE2EHarness
RUNTIME_E2E_DEBUG_BINARY := $(RUNTIME_E2E_SCRATCH)/debug/RuntimeE2EHarness
RUNTIME_E2E_INFO_PLIST := $(RUNTIME_E2E_PACKAGE)/Info.plist
RUNTIME_E2E_APP := $(LOCAL_DERIVED_DATA)/Tools/RuntimeE2EHarness.app
RUNTIME_E2E_APP_EXECUTABLE := $(RUNTIME_E2E_APP)/Contents/MacOS/RuntimeE2EHarness
RUNTIME_E2E_BUNDLE_ID ?= com.happyf.roma-just-talk.RuntimeE2EHarness
RUNTIME_E2E_CONFIG ?=
RUNTIME_E2E_REPORT ?= $(LOCAL_DERIVED_DATA)/Tools/runtime-e2e-report.json
RUNTIME_E2E_STDOUT ?= $(LOCAL_DERIVED_DATA)/Tools/runtime-e2e.out.log
RUNTIME_E2E_STDERR ?= $(LOCAL_DERIVED_DATA)/Tools/runtime-e2e.err.log
RUNTIME_E2E_CONFIG_ABS := $(abspath $(RUNTIME_E2E_CONFIG))
RUNTIME_E2E_REPORT_ABS := $(abspath $(RUNTIME_E2E_REPORT))

.PHONY: all clean whisper setup build local static-whisper-app-check adhoc-library-validation-check check healthcheck help dev run latency-harness-build latency-harness-app latency-harness-check latency-harness-run latency-harness-app-run runtime-e2e-build runtime-e2e-app runtime-e2e-check runtime-e2e-preflight runtime-e2e-target-probe runtime-e2e-run runtime-e2e-restore

# Default target
all: check build

# Development workflow
dev: build run

# Prerequisites
check:
	@echo "Checking prerequisites..."
	@command -v git >/dev/null 2>&1 || { echo "git is not installed"; exit 1; }
	@command -v xcodebuild >/dev/null 2>&1 || { echo "xcodebuild is not installed (need Xcode)"; exit 1; }
	@command -v swift >/dev/null 2>&1 || { echo "swift is not installed"; exit 1; }
	@echo "Prerequisites OK"

healthcheck: check

latency-harness-build:
	@mkdir -p "$(dir $(LATENCY_HARNESS))"
	swiftc "$(LATENCY_HARNESS_SOURCE)" \
		-framework AppKit \
		-framework ApplicationServices \
		-o "$(LATENCY_HARNESS)"

latency-harness-app: latency-harness-build
	@rm -rf "$(LATENCY_HARNESS_APP)"
	@mkdir -p "$(LATENCY_HARNESS_APP)/Contents/MacOS"
	@cp "$(LATENCY_HARNESS)" "$(LATENCY_HARNESS_APP_EXECUTABLE)"
	@cp "$(LATENCY_HARNESS_INFO_PLIST)" "$(LATENCY_HARNESS_APP)/Contents/Info.plist"
	@plutil -replace CFBundleIdentifier -string "$(LATENCY_HARNESS_BUNDLE_ID)" "$(LATENCY_HARNESS_APP)/Contents/Info.plist"
	@codesign --force --sign - "$(LATENCY_HARNESS_APP)" >/dev/null
	@echo "Harness app: $(LATENCY_HARNESS_APP)"
	@codesign -dvvv "$(LATENCY_HARNESS_APP)" 2>&1 | sed -n '1,8p'

latency-harness-check:
	bash scripts/check-latency-harness-makefile.sh
	bash scripts/check-visible-text-latency-harness.sh

latency-harness-run: latency-harness-build
	@if [ -z "$(LATENCY_EXPECTED)" ]; then \
		echo "Set LATENCY_EXPECTED to a unique transcript marker."; \
		echo "Example: make latency-harness-run LATENCY_EXPECTED='roma latency marker'"; \
		exit 2; \
	fi
	"$(LATENCY_HARNESS)" \
		--expected "$(LATENCY_EXPECTED)" \
		--samples "$(LATENCY_SAMPLES)" \
		--trigger "$(LATENCY_TRIGGER)" \
		--threshold-ms "$(LATENCY_THRESHOLD_MS)"

latency-harness-app-run:
	@if [ -z "$(LATENCY_EXPECTED)" ]; then \
		echo "Set LATENCY_EXPECTED to a unique transcript marker."; \
		echo "Example: make latency-harness-app-run LATENCY_EXPECTED='roma latency marker'"; \
		exit 2; \
	fi
	@if [ ! -x "$(LATENCY_HARNESS_APP_EXECUTABLE)" ]; then \
		echo "Build the helper app first with: make latency-harness-app"; \
		exit 2; \
	fi
	@rm -f "$(LATENCY_HARNESS_REPORT)" "$(LATENCY_HARNESS_STDOUT)" "$(LATENCY_HARNESS_STDERR)"
	open -W -n \
		-o "$(LATENCY_HARNESS_STDOUT)" \
		--stderr "$(LATENCY_HARNESS_STDERR)" \
		"$(LATENCY_HARNESS_APP)" \
		--args \
		--expected "$(LATENCY_EXPECTED)" \
		--samples "$(LATENCY_SAMPLES)" \
		--trigger "$(LATENCY_TRIGGER)" \
		--threshold-ms "$(LATENCY_THRESHOLD_MS)" \
		--json-output "$(LATENCY_HARNESS_REPORT)"
	@if [ -s "$(LATENCY_HARNESS_STDOUT)" ]; then cat "$(LATENCY_HARNESS_STDOUT)"; fi
	@if [ -s "$(LATENCY_HARNESS_STDERR)" ]; then cat "$(LATENCY_HARNESS_STDERR)" >&2; fi
	@if [ ! -f "$(LATENCY_HARNESS_REPORT)" ]; then \
		echo "No latency JSON report written. Check $(LATENCY_HARNESS_STDOUT) and $(LATENCY_HARNESS_STDERR)."; \
		exit 1; \
	fi
	@PASSED=$$(plutil -extract passed raw -o - "$(LATENCY_HARNESS_REPORT)" 2>/dev/null || echo false); \
	if [ "$$PASSED" != "true" ]; then \
		echo "Latency harness failed. Report: $(LATENCY_HARNESS_REPORT)"; \
		exit 1; \
	fi

runtime-e2e-build:
	swift build \
		-c release \
		--package-path "$(RUNTIME_E2E_PACKAGE)" \
		--scratch-path "$(RUNTIME_E2E_SCRATCH)" \
		--product RuntimeE2EHarness

runtime-e2e-app: runtime-e2e-build
	@rm -rf "$(RUNTIME_E2E_APP)"
	@mkdir -p "$(RUNTIME_E2E_APP)/Contents/MacOS"
	@cp "$(RUNTIME_E2E_BINARY)" "$(RUNTIME_E2E_APP_EXECUTABLE)"
	@cp "$(RUNTIME_E2E_INFO_PLIST)" "$(RUNTIME_E2E_APP)/Contents/Info.plist"
	@plutil -replace CFBundleIdentifier -string "$(RUNTIME_E2E_BUNDLE_ID)" "$(RUNTIME_E2E_APP)/Contents/Info.plist"
	@codesign --force --sign - "$(RUNTIME_E2E_APP)" >/dev/null
	@echo "Runtime E2E app: $(RUNTIME_E2E_APP)"
	@codesign -dvvv "$(RUNTIME_E2E_APP)" 2>&1 | sed -n '1,8p'

runtime-e2e-check:
	swift run \
		--package-path "$(RUNTIME_E2E_PACKAGE)" \
		--scratch-path "$(RUNTIME_E2E_SCRATCH)" \
		RuntimeE2ECoreChecks
	swift build \
		--package-path "$(RUNTIME_E2E_PACKAGE)" \
		--scratch-path "$(RUNTIME_E2E_SCRATCH)" \
		--product RuntimeE2EHarness
	bash scripts/check-runtime-e2e-makefile.sh "$(RUNTIME_E2E_DEBUG_BINARY)"
	bash -n scripts/runtime-e2e-model-bootstrap.sh
	bash -n scripts/runtime-e2e-phase-runner.sh
	bash -n scripts/run-macos-runtime-e2e.sh
	bash scripts/tests/verify-runtime-empty-final-regression.test.sh
	bash scripts/tests/verify-macos-framework-signature-crash.test.sh

runtime-e2e-preflight:
	@if [ ! -x "$(RUNTIME_E2E_APP_EXECUTABLE)" ]; then \
		echo "Build the helper once with: make runtime-e2e-app"; \
		exit 2; \
	fi
	@rm -f "$(RUNTIME_E2E_REPORT_ABS)" "$(RUNTIME_E2E_STDOUT)" "$(RUNTIME_E2E_STDERR)"
	@if [ -n "$(RUNTIME_E2E_CONFIG)" ]; then \
		open -W -n -o "$(RUNTIME_E2E_STDOUT)" --stderr "$(RUNTIME_E2E_STDERR)" "$(RUNTIME_E2E_APP)" --args --preflight --config "$(RUNTIME_E2E_CONFIG_ABS)" --json-output "$(RUNTIME_E2E_REPORT_ABS)"; \
	else \
		open -W -n -o "$(RUNTIME_E2E_STDOUT)" --stderr "$(RUNTIME_E2E_STDERR)" "$(RUNTIME_E2E_APP)" --args --preflight --json-output "$(RUNTIME_E2E_REPORT_ABS)"; \
	fi
	@if [ -s "$(RUNTIME_E2E_STDOUT)" ]; then cat "$(RUNTIME_E2E_STDOUT)"; fi
	@if [ -s "$(RUNTIME_E2E_STDERR)" ]; then cat "$(RUNTIME_E2E_STDERR)" >&2; fi
	@if [ ! -f "$(RUNTIME_E2E_REPORT_ABS)" ]; then \
		echo "No runtime E2E preflight report written. Check $(RUNTIME_E2E_STDOUT) and $(RUNTIME_E2E_STDERR)."; \
		exit 1; \
	fi
	@PASSED=$$(plutil -extract passed raw -o - "$(RUNTIME_E2E_REPORT_ABS)" 2>/dev/null || echo false); \
	if [ "$$PASSED" != "true" ]; then \
		echo "Runtime E2E preflight failed. Report: $(RUNTIME_E2E_REPORT_ABS)"; \
		exit 1; \
	fi

runtime-e2e-target-probe:
	@if [ ! -x "$(RUNTIME_E2E_APP_EXECUTABLE)" ]; then \
		echo "Build the helper once with: make runtime-e2e-app"; \
		exit 2; \
	fi
	@rm -f "$(RUNTIME_E2E_REPORT_ABS)" "$(RUNTIME_E2E_STDOUT)" "$(RUNTIME_E2E_STDERR)"
	@if [ -n "$(RUNTIME_E2E_CONFIG)" ]; then \
		open -W -n -o "$(RUNTIME_E2E_STDOUT)" --stderr "$(RUNTIME_E2E_STDERR)" "$(RUNTIME_E2E_APP)" --args --target-probe --config "$(RUNTIME_E2E_CONFIG_ABS)" --json-output "$(RUNTIME_E2E_REPORT_ABS)"; \
	else \
		open -W -n -o "$(RUNTIME_E2E_STDOUT)" --stderr "$(RUNTIME_E2E_STDERR)" "$(RUNTIME_E2E_APP)" --args --target-probe --json-output "$(RUNTIME_E2E_REPORT_ABS)"; \
	fi
	@if [ -s "$(RUNTIME_E2E_STDOUT)" ]; then cat "$(RUNTIME_E2E_STDOUT)"; fi
	@if [ -s "$(RUNTIME_E2E_STDERR)" ]; then cat "$(RUNTIME_E2E_STDERR)" >&2; fi
	@if [ ! -f "$(RUNTIME_E2E_REPORT_ABS)" ]; then \
		echo "No runtime target-probe report written. Check $(RUNTIME_E2E_STDOUT) and $(RUNTIME_E2E_STDERR)."; \
		exit 1; \
	fi
	@PASSED=$$(plutil -extract passed raw -o - "$(RUNTIME_E2E_REPORT_ABS)" 2>/dev/null || echo false); \
	if [ "$$PASSED" != "true" ]; then \
		echo "Runtime target probe failed. Report: $(RUNTIME_E2E_REPORT_ABS)"; \
		exit 1; \
	fi

runtime-e2e-run:
	@if [ ! -x "$(RUNTIME_E2E_APP_EXECUTABLE)" ]; then \
		echo "Build the helper once with: make runtime-e2e-app"; \
		exit 2; \
	fi
	@rm -f "$(RUNTIME_E2E_REPORT_ABS)" "$(RUNTIME_E2E_STDOUT)" "$(RUNTIME_E2E_STDERR)"
	@if [ -n "$(RUNTIME_E2E_CONFIG)" ]; then \
		open -W -n -o "$(RUNTIME_E2E_STDOUT)" --stderr "$(RUNTIME_E2E_STDERR)" "$(RUNTIME_E2E_APP)" --args --config "$(RUNTIME_E2E_CONFIG_ABS)" --json-output "$(RUNTIME_E2E_REPORT_ABS)"; \
	else \
		open -W -n -o "$(RUNTIME_E2E_STDOUT)" --stderr "$(RUNTIME_E2E_STDERR)" "$(RUNTIME_E2E_APP)" --args --json-output "$(RUNTIME_E2E_REPORT_ABS)"; \
	fi
	@if [ -s "$(RUNTIME_E2E_STDOUT)" ]; then cat "$(RUNTIME_E2E_STDOUT)"; fi
	@if [ -s "$(RUNTIME_E2E_STDERR)" ]; then cat "$(RUNTIME_E2E_STDERR)" >&2; fi
	@if [ ! -f "$(RUNTIME_E2E_REPORT_ABS)" ]; then \
		echo "No runtime E2E report written. Check $(RUNTIME_E2E_STDOUT) and $(RUNTIME_E2E_STDERR)."; \
		exit 1; \
	fi
	@PASSED=$$(plutil -extract summary.passed raw -o - "$(RUNTIME_E2E_REPORT_ABS)" 2>/dev/null || echo false); \
	if [ "$$PASSED" != "true" ]; then \
		echo "Runtime E2E failed. Report: $(RUNTIME_E2E_REPORT_ABS)"; \
		exit 1; \
	fi

runtime-e2e-restore:
	@if [ ! -x "$(RUNTIME_E2E_APP_EXECUTABLE)" ]; then \
		echo "Runtime E2E helper is not built."; \
		exit 2; \
	fi
	@if [ -n "$(RUNTIME_E2E_CONFIG)" ]; then \
		open -W -n "$(RUNTIME_E2E_APP)" --args --restore --config "$(RUNTIME_E2E_CONFIG_ABS)"; \
	else \
		open -W -n "$(RUNTIME_E2E_APP)" --args --restore; \
	fi

# Build process
whisper:
	@mkdir -p $(DEPS_DIR)
	@if ! bash "$(STATIC_WHISPER_XCFRAMEWORK_CHECK)" "$(FRAMEWORK_PATH)" >/dev/null 2>&1; then \
		echo "Building static whisper.xcframework in $(DEPS_DIR)..."; \
		if [ ! -d "$(WHISPER_CPP_DIR)" ]; then \
			git clone https://github.com/ggerganov/whisper.cpp.git $(WHISPER_CPP_DIR); \
		else \
			(cd $(WHISPER_CPP_DIR) && git pull --ff-only); \
		fi; \
		cd $(WHISPER_CPP_DIR) && BUILD_STATIC_XCFRAMEWORK=ON ./build-xcframework.sh; \
	else \
		echo "Static whisper.xcframework already built in $(DEPS_DIR), skipping build"; \
	fi
	@bash "$(STATIC_WHISPER_XCFRAMEWORK_CHECK)" "$(FRAMEWORK_PATH)"

setup: whisper
	@echo "Whisper framework is ready at $(FRAMEWORK_PATH)"
	@echo "Please ensure your Xcode project references the framework from this new location."

build: setup
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration Debug CODE_SIGN_IDENTITY="" build

# Build for local use without Apple Developer certificate
local: check setup
	@echo "Building roma just talk ($(CONFIGURATION)) for local use (no Apple Developer certificate required)..."
	@rm -rf "$(LOCAL_DERIVED_DATA)"
	xcodebuild -project VoiceInk.xcodeproj -scheme VoiceInk -configuration "$(CONFIGURATION)" \
		-derivedDataPath "$(LOCAL_DERIVED_DATA)" \
		-xcconfig LocalBuild.xcconfig \
		CLANG_ENABLE_CODE_COVERAGE=NO \
		CODE_SIGN_IDENTITY="-" \
		CODE_SIGNING_REQUIRED=NO \
		CODE_SIGNING_ALLOWED=YES \
		DEVELOPMENT_TEAM="" \
		CODE_SIGN_ENTITLEMENTS="$(CURDIR)/VoiceInk/VoiceInk.local.entitlements" \
		SWIFT_ACTIVE_COMPILATION_CONDITIONS='$$(inherited) LOCAL_BUILD' \
		build
	@APP_PATH="$(LOCAL_DERIVED_DATA)/Build/Products/$(CONFIGURATION)/roma just talk.app" && \
	STAGED_APP="$(LOCAL_DERIVED_DATA)/Install/roma just talk.app" && \
	PREVIOUS_APP="$(LOCAL_DERIVED_DATA)/Install/previous-roma-just-talk.app" && \
	if [ -d "$$APP_PATH" ]; then \
		echo "Verifying the built app before installation..."; \
		if ! bash "$(STATIC_WHISPER_APP_CHECK)" "$$APP_PATH"; then exit 1; fi; \
		if ! bash "$(ADHOC_LIBRARY_VALIDATION_CHECK)" "$$APP_PATH"; then exit 1; fi; \
		if ! mkdir -p "$$(dirname "$$STAGED_APP")"; then exit 1; fi; \
		if ! ditto "$$APP_PATH" "$$STAGED_APP"; then exit 1; fi; \
		if ! xattr -cr "$$STAGED_APP"; then exit 1; fi; \
		if ! bash "$(STATIC_WHISPER_APP_CHECK)" "$$STAGED_APP"; then exit 1; fi; \
		if ! bash "$(ADHOC_LIBRARY_VALIDATION_CHECK)" "$$STAGED_APP"; then exit 1; fi; \
		echo "Copying roma just talk.app to $(LOCAL_APP_DEST)..."; \
		if ! mkdir -p "$$(dirname "$(LOCAL_APP_DEST)")"; then exit 1; fi; \
		if [ -e "$(LOCAL_APP_DEST)" ]; then \
			if ! mv "$(LOCAL_APP_DEST)" "$$PREVIOUS_APP"; then exit 1; fi; \
		fi; \
		if ! mv "$$STAGED_APP" "$(LOCAL_APP_DEST)"; then \
			if [ -e "$$PREVIOUS_APP" ]; then mv "$$PREVIOUS_APP" "$(LOCAL_APP_DEST)" || true; fi; \
			exit 1; \
		fi; \
		if ! /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -lint -v -R -f "$(LOCAL_APP_DEST)"; then \
			if [ -e "$$PREVIOUS_APP" ]; then \
				rm -rf "$(LOCAL_APP_DEST)"; \
				mv "$$PREVIOUS_APP" "$(LOCAL_APP_DEST)" || true; \
			fi; \
			exit 1; \
		fi; \
		if ! rm -rf "$$PREVIOUS_APP"; then exit 1; fi; \
		echo ""; \
		echo "Build complete! App saved to: $(LOCAL_APP_DEST)"; \
		echo "Run with: open $(LOCAL_APP_DEST)"; \
		echo ""; \
		echo "Limitations of local builds:"; \
		echo "  - No iCloud dictionary sync"; \
		echo "  - No automatic updates (pull new code and rebuild to update)"; \
	else \
		echo "Error: Could not find built roma just talk.app at $$APP_PATH"; \
		exit 1; \
	fi

static-whisper-app-check:
	bash "$(STATIC_WHISPER_APP_CHECK)" "$(LOCAL_APP_DEST)"

adhoc-library-validation-check:
	bash "$(ADHOC_LIBRARY_VALIDATION_CHECK)" "$(LOCAL_APP_DEST)"

# Run application
run:
	@if [ -d "$(LOCAL_APP_DEST)" ]; then \
		echo "Opening $(LOCAL_APP_DEST)..."; \
		open "$(LOCAL_APP_DEST)"; \
	else \
		echo "Looking for roma just talk.app in DerivedData..."; \
		APP_PATH=$$(find "$$HOME/Library/Developer/Xcode/DerivedData" -name "roma just talk.app" -type d | head -1) && \
		if [ -n "$$APP_PATH" ]; then \
			echo "Found app at: $$APP_PATH"; \
			open "$$APP_PATH"; \
		else \
			echo "roma just talk.app not found. Please run 'make build' or 'make local' first."; \
			exit 1; \
		fi; \
	fi

# Cleanup
clean:
	@echo "Cleaning build artifacts..."
	@rm -rf $(DEPS_DIR)
	@echo "Clean complete"

# Help
help:
	@echo "Available targets:"
	@echo "  check/healthcheck  Check if required CLI tools are installed"
	@echo "  whisper            Clone and build whisper.cpp XCFramework"
	@echo "  setup              Copy whisper XCFramework to VoiceInk project"
	@echo "  build              Build the VoiceInk Xcode project"
	@echo "  local              Build for local use (Debug default; use CONFIGURATION=Release for packaging)"
	@echo "  static-whisper-app-check Verify the built app does not embed or load Whisper dynamically"
	@echo "  adhoc-library-validation-check Verify the local app can load its bundled frameworks"
	@echo "  run                Launch the built VoiceInk app"
	@echo "  dev                Build and run the app (for development)"
	@echo "  all                Run full build process (default)"
	@echo "  latency-harness-build  Compile real visible-text latency harness"
	@echo "  latency-harness-app    Build stable signed helper app for TCC grants"
	@echo "  latency-harness-check  Verify helper-app run target preserves TCC identity"
	@echo "  latency-harness-run    Run CLI latency samples; set LATENCY_EXPECTED"
	@echo "  latency-harness-app-run Run helper-app latency samples; set LATENCY_EXPECTED"
	@echo "  runtime-e2e-build      Compile autonomous runtime E2E harness"
	@echo "  runtime-e2e-app        Build stable helper app for one-time TCC grants"
	@echo "  runtime-e2e-check      Run core checks and verify stable helper invocation"
	@echo "  runtime-e2e-preflight  Check fixtures, BlackHole, exact build, apps, and TCC"
	@echo "  runtime-e2e-target-probe Validate four already-running app targets without Roma/audio"
	@echo "  runtime-e2e-run        Run autonomous fixture x app x repetition matrix"
	@echo "  runtime-e2e-restore    Restore state after an interrupted harness run"
	@echo "  clean              Remove build artifacts"
	@echo "  help               Show this help message"
