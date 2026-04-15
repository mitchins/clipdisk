APP_NAME     = ClipboardFolder
BUNDLE_ID    = com.mitchellcurrie.clipboard-folder
VERSION      = 1.0.2
BUILD_DIR    = .build/release
APP_BUNDLE   = $(APP_NAME).app
DMG_FILE     = $(APP_NAME)-$(VERSION).dmg
NOTARY_PROFILE ?= NotaryTool
CODESIGN_IDENTITY ?= Developer ID Application: Mitchell Currie

.PHONY: build test lint setup-hooks icon app clean run sign dmg notarize package verify-sign verify-gatekeeper release-check release

build:
	swift build -c release

test:
	swift test

lint:
	swiftlint lint --reporter emoji

setup-hooks:
	@echo '#!/bin/sh\n[ -n "$$CI" ] && exit 0\nswiftlint lint --quiet' > .git/hooks/pre-commit
	@chmod +x .git/hooks/pre-commit
	@echo "Pre-commit hook installed (skips on CI)"

icon:
	bash Scripts/create-volume-icon.sh

app: build icon
	@echo "Creating $(APP_BUNDLE)..."
	rm -rf $(APP_BUNDLE)
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/
	cp Resources/VolumeIcon.icns $(APP_BUNDLE)/Contents/Resources/
	@echo "Done: $(APP_BUNDLE)"

run: app
	open $(APP_BUNDLE)

sign: app
	codesign --force --deep --timestamp --options runtime \
		--entitlements Resources/ClipboardFolder.entitlements \
		--sign "$(CODESIGN_IDENTITY)" \
		$(APP_BUNDLE)

dmg: sign
	hdiutil create -volname "$(APP_NAME)" -srcfolder "$(APP_BUNDLE)" \
		-ov -format UDZO "$(DMG_FILE)"
	codesign --force --timestamp \
		--sign "$(CODESIGN_IDENTITY)" \
		"$(DMG_FILE)"

notarize: dmg
	xcrun notarytool submit "$(DMG_FILE)" \
		--keychain-profile "$(NOTARY_PROFILE)" \
		--wait
	xcrun stapler staple "$(DMG_FILE)"

package: notarize
	@echo "Package ready: $(DMG_FILE)"

verify-sign:
	codesign --verify --deep --strict --verbose=2 $(APP_BUNDLE)
	codesign -dv --verbose=4 $(APP_BUNDLE)

verify-gatekeeper:
	spctl --assess --type exec --verbose=4 $(APP_BUNDLE)

release-check: verify-sign verify-gatekeeper

release: package
	gh release create "v$(VERSION)" "$(DMG_FILE)" \
		--title "v$(VERSION)" \
		--generate-notes

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
	rm -f $(APP_NAME)-*.dmg
