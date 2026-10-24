# FastBullTicker 建置：helper（Rust）→ app（組裝 bundle）→ sign（ad-hoc 簽名並驗證）→ test。
# 只支援 arm64；不 notarize、不沙盒。簽名順序由內而外：先 helper、再 bundle；不遞迴簽名。
APP_NAME   := FastBullTicker
BUILD_DIR  := build
APP        := $(BUILD_DIR)/$(APP_NAME).app
MACOS_DIR  := $(APP)/Contents/MacOS
HELPER_SRC := ticker-connect/target/release/ticker-connect
HELPER_DST := $(MACOS_DIR)/ticker-connect

.PHONY: all helper app sign test clean verify

all: helper app sign

helper:
	cd ticker-connect && cargo build --release
	@lipo -archs $(HELPER_SRC) | grep -qx arm64 || { echo "error: $(HELPER_SRC) 不是 arm64"; exit 1; }

app:
	@test -x $(HELPER_SRC) || { echo "error: 找不到 $(HELPER_SRC)，請先 make helper"; exit 1; }
	swift build -c release --arch arm64 --product $(APP_NAME)
	rm -rf $(APP)
	mkdir -p $(MACOS_DIR)
	cp "$$(swift build -c release --arch arm64 --show-bin-path)/$(APP_NAME)" $(MACOS_DIR)/$(APP_NAME)
	cp $(HELPER_SRC) $(HELPER_DST)
	cp Resources/Info.plist $(APP)/Contents/Info.plist
	plutil -lint $(APP)/Contents/Info.plist

sign:
	@test -d $(APP) || { echo "error: 找不到 $(APP)，請先 make app"; exit 1; }
	codesign --force --sign - $(HELPER_DST)
	codesign --force --sign - $(APP)
	$(MAKE) verify

verify:
	codesign --verify --strict --verbose=2 $(HELPER_DST)
	codesign --verify --strict --verbose=2 $(APP)

test:
	swift test

clean:
	rm -rf $(BUILD_DIR)
