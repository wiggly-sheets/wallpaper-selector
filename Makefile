APP_NAME := Wallpaper Selector
PRODUCT_NAME := WallpaperSelector
CONFIGURATION ?= debug
VERSION ?= 0.1.0
DIST_DIR := dist
APP_BUNDLE := $(DIST_DIR)/$(APP_NAME).app
INSTALL_DIR ?= $(HOME)/Applications
INSTALL_APP := $(INSTALL_DIR)/$(APP_NAME).app
RELEASE_DIR := release
DMG := $(RELEASE_DIR)/WallpaperSelector-$(VERSION).dmg
STAGING_DIR := $(RELEASE_DIR)/staging
CREATE_DMG ?= create-dmg
DMG_BACKGROUND := Support/Installer/dmg-background.png
DMG_ICON := SwiftWallpaperSelector/Sources/WallpaperSelector/Resources/AppIcon.icns

.PHONY: help build test bundle install run dmg release-artifacts clean

help:
	@echo "make build    Build Swift executable"
	@echo "make test     Run unit tests"
	@echo "make bundle   Create $(APP_BUNDLE)"
	@echo "make install  Copy app to $(INSTALL_DIR)"
	@echo "make run      Install then launch app"
	@echo "make dmg      Create versioned release DMG"
	@echo "make release-artifacts  Create DMG + SHA-256 checksum"
	@echo "                         Requires create-dmg (brew install create-dmg)"
	@echo "make clean    Remove workspace build artifacts"

build:
	swift build -c $(CONFIGURATION)

test:
	swift test

bundle: build
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS" "$(APP_BUNDLE)/Contents/Resources"
	cp "$(shell swift build -c $(CONFIGURATION) --show-bin-path)/$(PRODUCT_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(PRODUCT_NAME)"
	cp Support/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	cp SwiftWallpaperSelector/Sources/WallpaperSelector/Resources/AppIcon.icns "$(APP_BUNDLE)/Contents/Resources/AppIcon.icns"
	cp -R "$(shell swift build -c $(CONFIGURATION) --show-bin-path)"/$(PRODUCT_NAME)_*.bundle "$(APP_BUNDLE)/Contents/Resources/"
	codesign --force --sign - "$(APP_BUNDLE)"

install: bundle
	mkdir -p "$(INSTALL_DIR)"
	rm -rf "$(INSTALL_APP)"
	cp -R "$(APP_BUNDLE)" "$(INSTALL_APP)"

run: install
	open -n "$(INSTALL_APP)"

dmg: bundle
	rm -rf "$(RELEASE_DIR)"
	mkdir -p "$(STAGING_DIR)"
	cp -R "$(APP_BUNDLE)" "$(STAGING_DIR)/$(APP_NAME).app"
	$(CREATE_DMG) --volname "$(APP_NAME)" --volicon "$(DMG_ICON)" --background "$(DMG_BACKGROUND)" --window-size 660 440 --icon-size 110 --text-size 12 --icon "$(APP_NAME).app" 170 250 --app-drop-link 490 250 --hide-extension "$(APP_NAME).app" --no-internet-enable --overwrite "$(DMG)" "$(STAGING_DIR)"

release-artifacts: dmg
	shasum -a 256 "$(DMG)" > "$(DMG).sha256"

clean:
	rm -rf .build "$(DIST_DIR)" "$(RELEASE_DIR)"
