PROJECT_DIR = Hyperactive
PROJECT = $(PROJECT_DIR)/Hyperactive.xcodeproj
SCHEME = Hyperactive
CONFIG_DEBUG = Debug
CONFIG_RELEASE = Release
BUILD_DIR = build
APP_NAME = Hyperactive.app

.PHONY: build release clean archive dmg open

# Debug build
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG_DEBUG) \
		-derivedDataPath $(BUILD_DIR) build

# Release build
release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG_RELEASE) \
		-derivedDataPath $(BUILD_DIR) build

# Open in Xcode
open:
	open $(PROJECT)

# Clean build artifacts
clean:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) clean
	rm -rf $(BUILD_DIR)

# Archive for distribution
archive:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG_RELEASE) \
		-archivePath $(BUILD_DIR)/Hyperactive.xcarchive archive

# Create DMG (requires built app)
dmg: release
	@mkdir -p $(BUILD_DIR)/dmg
	@cp -R $(BUILD_DIR)/Build/Products/Release/$(APP_NAME) $(BUILD_DIR)/dmg/
	hdiutil create -volname Hyperactive -srcfolder $(BUILD_DIR)/dmg \
		-ov -format UDZO $(BUILD_DIR)/Hyperactive.dmg
	@rm -rf $(BUILD_DIR)/dmg
	@echo "DMG created at $(BUILD_DIR)/Hyperactive.dmg"
