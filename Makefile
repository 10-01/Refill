.PHONY: all build check install lint media package test verify clean

all: check

build:
	./build.sh

test:
	./test.sh

lint:
	zsh -n build.sh install.sh test.sh Scripts/*.sh
	plutil -lint Resources/Info.plist Resources/Refill.entitlements

verify: build
	./Scripts/verify-build.sh

check: lint test verify

install:
	./install.sh

media: build
	./Scripts/capture-media.sh

package: test
	./Scripts/package.sh

clean:
	rm -rf build dist
