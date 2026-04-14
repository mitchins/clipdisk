APP_NAME     = ClipboardFolder
BUNDLE_ID    = com.mitchellcurrie.clipboard-folder
VERSION      = 1.0.0
BUILD_DIR    = .build/release
APP_BUNDLE   = $(APP_NAME).app
ZIP_FILE     = $(APP_NAME)-$(VERSION).zip
NOTARY_PROFILE ?= NotaryTool
CODESIGN_IDENTITY ?= Developer ID Application: Mitchell Currie

.PHONY: build test icon app clean run sign notarize package verify-sign verify-gatekeeper release-check release

build:
	swift build -c release

test:
	swift test

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

notarize: sign
	ditto -c -k --keepParent $(APP_BUNDLE) $(ZIP_FILE)
	xcrun notarytool submit $(ZIP_FILE) \
		--keychain-profile "$(NOTARY_PROFILE)" \
		--wait
	xcrun stapler staple $(APP_BUNDLE)

package: notarize
	ditto -c -k --keepParent $(APP_BUNDLE) $(ZIP_FILE)
	@echo "Package ready: $(ZIP_FILE)"

verify-sign:
	codesign --verify --deep --strict --verbose=2 $(APP_BUNDLE)
	codesign -dv --verbose=4 $(APP_BUNDLE)

verify-gatekeeper:
	spctl --assess --type exec --verbose=4 $(APP_BUNDLE)

release-check: verify-sign verify-gatekeeper

release: package
	gh release create "v$(VERSION)" "$(ZIP_FILE)" \
		--title "v$(VERSION)" \
		--generate-notes

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
	rm -f $(APP_NAME)-*.zip
