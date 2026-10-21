PROJECT_DIR = Hyperactive
PROJECT = $(PROJECT_DIR)/Hyperactive.xcodeproj
SCHEME = Hyperactive
CONFIG_DEBUG = Debug
CONFIG_RELEASE = Release
BUILD_DIR = build
DIST_DIR = $(BUILD_DIR)/dist
APP_NAME = Hyperactive.app
RELEASE_APP = $(BUILD_DIR)/Build/Products/Release/$(APP_NAME)

# Release version (without the leading "v"). Defaults to the latest git tag.
# CI passes VERSION and BUILD_NUMBER explicitly.
VERSION ?= $(shell git describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null | sed 's/^v//')
BUILD_NUMBER ?=
VERSION_LABEL = $(if $(VERSION),$(VERSION),dev)

VERSION_FLAGS = $(if $(VERSION),MARKETING_VERSION=$(VERSION)) $(if $(BUILD_NUMBER),CURRENT_PROJECT_VERSION=$(BUILD_NUMBER))
UNIVERSAL_FLAGS = ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO

DMG_NAME = Hyperactive-$(VERSION_LABEL).dmg
APP_ZIP_NAME = Hyperactive-$(VERSION_LABEL)-macOS.zip
SOURCE_ZIP_NAME = Hyperactive-$(VERSION_LABEL)-source.zip

.PHONY: build release clean archive dmg zip package package-dmg package-zip source-zip version open

# Debug build
build:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG_DEBUG) \
		-derivedDataPath $(BUILD_DIR) $(VERSION_FLAGS) build

# Release build (universal: Apple silicon + Intel)
release:
	xcodebuild -project $(PROJECT) -scheme $(SCHEME) -configuration $(CONFIG_RELEASE) \
		-derivedDataPath $(BUILD_DIR) $(UNIVERSAL_FLAGS) $(VERSION_FLAGS) build

# Print the version that will be embedded in the build
version:
	@echo $(VERSION_LABEL)

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
		$(UNIVERSAL_FLAGS) $(VERSION_FLAGS) -archivePath $(BUILD_DIR)/Hyperactive.xcarchive archive

# Build, then create the DMG / zipped app
dmg: release package-dmg
zip: release package-zip

# Package an already-built (and possibly re-signed) app without rebuilding it
package: package-dmg package-zip

package-dmg:
	@test -d $(RELEASE_APP) || (echo "$(RELEASE_APP) not found. Run 'make release' first." && exit 1)
	@mkdir -p $(DIST_DIR)
	@rm -rf $(BUILD_DIR)/dmg
	@mkdir -p $(BUILD_DIR)/dmg
	@cp -R $(RELEASE_APP) $(BUILD_DIR)/dmg/
	@ln -s /Applications $(BUILD_DIR)/dmg/Applications
	hdiutil create -volname Hyperactive -srcfolder $(BUILD_DIR)/dmg \
		-ov -format UDZO $(DIST_DIR)/$(DMG_NAME)
	@rm -rf $(BUILD_DIR)/dmg
	@echo "DMG created at $(DIST_DIR)/$(DMG_NAME)"

# Zipped app bundle. The in-app updater downloads this asset.
package-zip:
	@test -d $(RELEASE_APP) || (echo "$(RELEASE_APP) not found. Run 'make release' first." && exit 1)
	@mkdir -p $(DIST_DIR)
	ditto -c -k --sequesterRsrc --keepParent $(RELEASE_APP) $(DIST_DIR)/$(APP_ZIP_NAME)
	@echo "Zip created at $(DIST_DIR)/$(APP_ZIP_NAME)"

source-zip:
	@mkdir -p $(DIST_DIR)
	git archive --format=zip --prefix=Hyperactive-$(VERSION_LABEL)/ -o $(DIST_DIR)/$(SOURCE_ZIP_NAME) HEAD
	@echo "Source zip created at $(DIST_DIR)/$(SOURCE_ZIP_NAME)"
