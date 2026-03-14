APP_NAME     = ClipboardFolder
BUNDLE_ID    = com.mitchellcurrie.clipboard-folder
VERSION      = 0.1.0
BUILD_DIR    = .build/release
APP_BUNDLE   = $(APP_NAME).app

.PHONY: build test app clean run sign notarize package

build:
	swift build -c release

test:
	swift test

app: build
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
	codesign --deep --force --options runtime \
		--sign "Developer ID Application: Mitchell Currie" \
		$(APP_BUNDLE)

notarize: sign
	ditto -c -k --keepParent $(APP_BUNDLE) $(APP_NAME)-$(VERSION).zip
	xcrun notarytool submit $(APP_NAME)-$(VERSION).zip \
		--apple-id "$$APPLE_ID" \
		--team-id "$$TEAM_ID" \
		--password "$$AC_PASSWORD" \
		--wait
	xcrun stapler staple $(APP_BUNDLE)

package: notarize
	ditto -c -k --keepParent $(APP_BUNDLE) $(APP_NAME)-$(VERSION).zip
	@echo "Package ready: $(APP_NAME)-$(VERSION).zip"

clean:
	swift package clean
	rm -rf $(APP_BUNDLE)
	rm -f $(APP_NAME)-*.zip
