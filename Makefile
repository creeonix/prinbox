APP_NAME  := Prinbox
BUNDLE_ID := io.github.creeonix.prinbox
VERSION   := 0.1.0
BUILD_DIR := build
APP       := $(BUILD_DIR)/$(APP_NAME).app
INSTALLED := /Applications/$(APP_NAME).app

# Command Line Tools keep the swift-testing macro plugin in host/plugins/testing, which the default
# explicit-module dependency scan intermittently misses ("plugin for module 'TestingMacros' not found").
# Pass the directory explicitly when it exists; Xcode toolchains do not need it.
TESTING_PLUGINS := $(shell d="$$(dirname "$$(dirname "$$(xcrun --find swift)")")/lib/swift/host/plugins/testing"; [ -d "$$d" ] && echo "$$d")
SWIFT_TEST_FLAGS := $(if $(TESTING_PLUGINS),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS))

.PHONY: test lint format coverage build app install uninstall run clean

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

coverage:
	SWIFT_TEST_FLAGS="$(SWIFT_TEST_FLAGS)" scripts/coverage.sh 80

build:
	swift build -c release --product $(APP_NAME)

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS"
	cp "$$(swift build -c release --show-bin-path)/$(APP_NAME)" "$(APP)/Contents/MacOS/$(APP_NAME)"
	sed 's/__VERSION__/$(VERSION)/g' Resources/Info.plist > "$(APP)/Contents/Info.plist"
	codesign --force --sign - --identifier $(BUNDLE_ID) "$(APP)"
	codesign --verify --strict "$(APP)"

install: app
	-pkill -x $(APP_NAME)
	rm -rf "$(INSTALLED)"
	cp -R "$(APP)" /Applications/
	open "$(INSTALLED)"

uninstall:
	-"$(INSTALLED)/Contents/MacOS/$(APP_NAME)" --unregister-login-item
	-pkill -x $(APP_NAME)
	rm -rf "$(INSTALLED)" "$(HOME)/Library/Caches/$(BUNDLE_ID)"
	-defaults delete $(BUNDLE_ID)

run:
	swift run $(APP_NAME)

clean:
	rm -rf .build $(BUILD_DIR)
