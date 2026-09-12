.PHONY: build test app run clean

CC := xcrun clang
CFLAGS := -fobjc-arc -fmodules -fmodules-cache-path=.build/module-cache -mmacosx-version-min=13.0 -Wall -Wextra

build:
	mkdir -p .build/module-cache .build/bin
	$(CC) $(CFLAGS) -O2 -I Sources/TokenBar Sources/TokenBar/main.m Sources/TokenBar/TokenLogParser.m Sources/TokenBar/AccountRateLimitReader.m -framework Cocoa -framework CoreGraphics -framework QuartzCore -o .build/bin/TokenBar

test:
	mkdir -p .build/module-cache .build/bin
	$(CC) $(CFLAGS) -O0 -g -I Sources/TokenBar Tests/parser_tests.m Sources/TokenBar/TokenLogParser.m Sources/TokenBar/AccountRateLimitReader.m -framework Foundation -o .build/bin/parser-tests
	.build/bin/parser-tests

app: build
	mkdir -p "dist/Token Bar.app/Contents/MacOS"
	cp .build/bin/TokenBar "dist/Token Bar.app/Contents/MacOS/TokenBar"
	cp Packaging/Info.plist "dist/Token Bar.app/Contents/Info.plist"
	codesign --force --deep --sign - "dist/Token Bar.app"

run: app
	open "dist/Token Bar.app"

clean:
	rm -rf dist
	rm -rf .build
