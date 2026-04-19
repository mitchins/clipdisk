APP_NAME     = ClipboardFolder
BUNDLE_ID    = com.mitchellcurrie.clipboard-folder
VERSION      = 1.1
BUILD_DIR    = .build/release
APP_BUNDLE   = $(APP_NAME).app
DMG_FILE     = $(APP_NAME)-$(VERSION).dmg
OWNER_REPO   ?= mitchins/clipdisk
HOMEBREW_TAP ?= mitchins/homebrew-tap
HOMEBREW_CASK ?= clipdisk
NOTARY_PROFILE ?= NotaryTool
CODESIGN_IDENTITY ?= Developer ID Application: Mitchell Currie

.PHONY: build test lint setup-hooks icon app clean run sign dmg notarize package verify-sign verify-gatekeeper release-check release brew-publish

build:
	swift build -c release

test:
	swift test

lint:
	@set -e; \
	if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint lint --reporter emoji; \
	elif command -v docker >/dev/null 2>&1; then \
		docker run --rm \
			-v "$(CURDIR):/work" -w /work \
			ghcr.io/realm/swiftlint:latest \
			swiftlint lint --reporter emoji; \
	else \
		echo "SwiftLint requires either swiftlint or Docker"; \
		exit 1; \
	fi

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
	cp Resources/AppIcon.icns    $(APP_BUNDLE)/Contents/Resources/
	cp Resources/VolumeIcon.icns $(APP_BUNDLE)/Contents/Resources/
	cp Sources/ClipboardFolder/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon.png $(APP_BUNDLE)/Contents/Resources/
	cp Sources/ClipboardFolder/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@2x.png $(APP_BUNDLE)/Contents/Resources/
	cp Sources/ClipboardFolder/Assets.xcassets/MenuBarIcon.imageset/MenuBarIcon@3x.png $(APP_BUNDLE)/Contents/Resources/
	@if [ -d Resources/FinderTemplate ]; then cp -R Resources/FinderTemplate $(APP_BUNDLE)/Contents/Resources/; fi
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

release: lint
	$(MAKE) package
	gh release create "v$(VERSION)" "$(DMG_FILE)" \
		--title "v$(VERSION)" \
		--generate-notes

brew-publish:
	VERSION="$(VERSION)" \
	DMG_FILE="$(DMG_FILE)" \
	OWNER_REPO="$(OWNER_REPO)" \
	TAP_REPO="$(HOMEBREW_TAP)" \
	CASK_NAME="$(HOMEBREW_CASK)" \
	bash Scripts/publish-homebrew-cask.sh

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
	rm -f $(APP_NAME)-*.dmg
