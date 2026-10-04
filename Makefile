PRODUCT    := PrinboxApp
EXECUTABLE := Prinbox
APP_NAME   := PRInbox
BUNDLE_ID  := io.github.creeonix.prinbox
VERSION    ?= 0.4.0
BUILD_DIR  := build
APP        := $(BUILD_DIR)/$(APP_NAME).app
DMG        := $(BUILD_DIR)/$(APP_NAME)-$(VERSION).dmg
INSTALLED  := /Applications/$(APP_NAME).app

# Universal by default, so local builds match the released DMG. Use ARCHS=arm64 for a faster local build.
ARCHS         ?= arm64 x86_64
ARCH_FLAGS    := $(foreach arch,$(ARCHS),--arch $(arch))
# "-" signs ad hoc. A Developer ID identity also gets the hardened runtime and a secure timestamp,
# which notarization requires (see RELEASING.md).
SIGN_IDENTITY ?= -
SIGN_FLAGS    := $(if $(filter -,$(SIGN_IDENTITY)),,--options runtime --timestamp)

# Command Line Tools keep the swift-testing macro plugin in host/plugins/testing, which the default
# explicit-module dependency scan intermittently misses ("plugin for module 'TestingMacros' not found").
# Pass the directory explicitly when it exists; Xcode toolchains do not need it.
TESTING_PLUGINS := $(shell d="$$(dirname "$$(dirname "$$(xcrun --find swift)")")/lib/swift/host/plugins/testing"; [ -d "$$d" ] && echo "$$d")
SWIFT_TEST_FLAGS := $(if $(TESTING_PLUGINS),-Xswiftc -plugin-path -Xswiftc $(TESTING_PLUGINS))

.PHONY: test lint format coverage build icon app dmg install uninstall run clean

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
	swift build -c release --product $(PRODUCT) $(ARCH_FLAGS)

# Regenerates Resources/AppIcon.icns from Resources/AppIcon-source.png: opaque, full-bleed, square
# artwork. macOS 26+ applies its own rounded mask and margins to such icons; artwork that already carries
# a shape or transparent margins gets boxed in a grey rounded square instead.
ICON_SIZES := 16x16:16 16x16@2x:32 32x32:32 32x32@2x:64 128x128:128 128x128@2x:256 256x256:256 \
	256x256@2x:512 512x512:512 512x512@2x:1024

icon:
	rm -rf "$(BUILD_DIR)/AppIcon.iconset"
	mkdir -p "$(BUILD_DIR)/AppIcon.iconset"
	for spec in $(ICON_SIZES); do \
		sips -z "$${spec##*:}" "$${spec##*:}" Resources/AppIcon-source.png \
			--out "$(BUILD_DIR)/AppIcon.iconset/icon_$${spec%%:*}.png" >/dev/null || exit 1; \
	done
	iconutil -c icns "$(BUILD_DIR)/AppIcon.iconset" -o Resources/AppIcon.icns

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp "$$(swift build -c release --product $(PRODUCT) $(ARCH_FLAGS) --show-bin-path)/$(PRODUCT)" \
		"$(APP)/Contents/MacOS/$(EXECUTABLE)"
	cp Resources/AppIcon.icns "$(APP)/Contents/Resources/AppIcon.icns"
	sed 's/__VERSION__/$(VERSION)/g' Resources/Info.plist > "$(APP)/Contents/Info.plist"
	codesign --force --sign "$(SIGN_IDENTITY)" $(SIGN_FLAGS) --identifier $(BUNDLE_ID) "$(APP)"
	codesign --verify --strict "$(APP)"

dmg: app
	scripts/make-dmg.sh "$(APP)" "$(DMG)" "$(APP_NAME) $(VERSION)"

install: app
	-pkill -x $(EXECUTABLE)
	@for i in $$(seq 50); do pgrep -xq $(EXECUTABLE) || break; sleep 0.1; done
	rm -rf "$(INSTALLED)"
	cp -R "$(APP)" /Applications/
	open "$(INSTALLED)"

uninstall:
	-"$(INSTALLED)/Contents/MacOS/$(EXECUTABLE)" --unregister-login-item
	-pkill -x $(EXECUTABLE)
	rm -rf "$(INSTALLED)" "$(HOME)/Library/Caches/$(BUNDLE_ID)" "$(HOME)/Library/Application Support/prinbox" "$(HOME)/.config/prinbox"
	-defaults delete $(BUNDLE_ID)
	-defaults delete $(BUNDLE_ID).demo

run:
	swift run $(PRODUCT)

clean:
	rm -rf .build $(BUILD_DIR)
