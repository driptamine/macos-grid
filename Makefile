APP_NAME = macos_grid
BUILD_DIR = build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app

$(APP_BUNDLE): $(BUILD_DIR)/$(APP_NAME) Resources/Info.plist
	mkdir -p $(APP_BUNDLE)/Contents/MacOS
	mkdir -p $(APP_BUNDLE)/Contents/Resources
	cp $(BUILD_DIR)/$(APP_NAME) $(APP_BUNDLE)/Contents/MacOS/
	cp Resources/Info.plist $(APP_BUNDLE)/Contents/Info.plist

$(BUILD_DIR)/$(APP_NAME): Sources/macos_grid/*.swift
	mkdir -p $(BUILD_DIR)
	swiftc \
		-sdk $(shell xcrun --show-sdk-path --sdk macosx) \
		-target x86_64-apple-macos12.0 \
		-framework Cocoa \
		-framework Carbon \
		$(wildcard Sources/macos_grid/*.swift) \
		-o $(BUILD_DIR)/$(APP_NAME)

build: $(APP_BUNDLE)

run: $(APP_BUNDLE)
	open $(APP_BUNDLE)

clean:
	rm -rf $(BUILD_DIR)

.PHONY: build run clean
