# Command Line Tools keep the swift-testing macro plugin in host/plugins/testing, which the default
# explicit-module dependency scan intermittently misses ("plugin for module 'TestingMacros' not found").
# Pass the directory explicitly when it exists; Xcode toolchains do not need it.
TESTING_PLUGINS := $(shell d="$$(dirname "$$(dirname "$$(xcrun --find swift)")")/lib/swift/host/plugins/testing"; [ -d "$$d" ] && echo "$$d")
SWIFT_TEST_FLAGS := $(if $(TESTING_PLUGINS),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS))

.PHONY: test lint format

test:
	swift test $(SWIFT_TEST_FLAGS)

lint:
	swift format lint --recursive Sources Tests Package.swift
	@if grep -rnE '@State( |$$)|#Preview' Sources; then \
		echo "error: @State and #Preview need Xcode's SwiftUI macro plugin; keep view state in @Observable models"; \
		exit 1; \
	fi

format:
	swift format --in-place --recursive Sources Tests Package.swift
