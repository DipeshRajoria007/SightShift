# SightShift build commands. Requires Xcode 16 or later.
APP_NAME    := SightShift
BUNDLE_ID   := app.sightshift.SightShift
CONFIG      ?= Release
BUILD_DIR   := build
DERIVED     := $(BUILD_DIR)/DerivedData
APP         := $(BUILD_DIR)/$(APP_NAME).app
INSTALL_DIR ?= /Applications

.PHONY: all build run install test project icon reset-permissions clean

all: build

## Regenerate SightShift.xcodeproj from project.yml (needs `brew install xcodegen`).
project:
	xcodegen generate

SightShift.xcodeproj/project.pbxproj: project.yml
	@if command -v xcodegen >/dev/null; then xcodegen generate --quiet; else touch $@; fi

## Build and sign build/SightShift.app.
build: SightShift.xcodeproj/project.pbxproj
	xcodebuild -project SightShift.xcodeproj -scheme $(APP_NAME) -configuration $(CONFIG) \
		-destination 'generic/platform=macOS' -derivedDataPath $(DERIVED) CODE_SIGNING_ALLOWED=NO -quiet build
	rm -rf $(APP)
	cp -R $(DERIVED)/Build/Products/$(CONFIG)/$(APP_NAME).app $(APP)
	scripts/sign.sh $(APP)

## Build and launch from the build folder.
run: build
	-pkill -x $(APP_NAME); sleep 0.5
	open $(APP)

## Build, copy to /Applications (override with INSTALL_DIR=~/Applications) and launch.
install: build
	-pkill -x $(APP_NAME); sleep 0.5
	rm -rf "$(INSTALL_DIR)/$(APP_NAME).app"
	cp -R $(APP) "$(INSTALL_DIR)/"
	open "$(INSTALL_DIR)/$(APP_NAME).app"

## Run the unit tests for the gaze model and decision logic.
test:
	cd Packages/SightShiftCore && swift test

## Regenerate the app icon.
icon:
	swift scripts/make-icon.swift App/Resources/Assets.xcassets/AppIcon.appiconset

## Make macOS forget SightShift's Camera and Accessibility permissions.
reset-permissions:
	-tccutil reset Accessibility $(BUNDLE_ID)
	-tccutil reset Camera $(BUNDLE_ID)

clean:
	rm -rf $(BUILD_DIR)
