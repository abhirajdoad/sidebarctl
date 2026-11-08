VERSION ?= 1.0.0
PREFIX  ?= /usr/local
ARCHS   ?= -arch arm64 -arch x86_64
CFLAGS  ?= -O2 -Wall -Wextra -fobjc-arc -mmacosx-version-min=11.0
LIBS     = -framework Foundation -framework CoreServices
SIGN_ID ?= io.github.abhirajdoad.sidebarctl

# VERSION reaches recipes only through the environment ("$$VERSION"), never by
# text substitution into shell commands, and is validated before any build step.
export VERSION

BIN  = sidebarctl

.PHONY: all clean install uninstall test dist FORCE

all: $(BIN)

FORCE:

# Always rebuilt (about 1 s), so a changed VERSION can never leave a stale binary behind.
$(BIN): FORCE
	@printf '%s' "$$VERSION" | grep -Eq '^[0-9A-Za-z.+-]+$$' || { echo "invalid VERSION: $$VERSION" >&2; exit 1; }
	clang $(CFLAGS) $(ARCHS) -DSIDEBARCTL_VERSION="\"$$VERSION\"" $(LIBS) src/main.m -o $@
	codesign --force --sign - --identifier $(SIGN_ID) $@

test: $(BIN)
	./scripts/smoke-test.sh

install: $(BIN)
	install -d $(DESTDIR)$(PREFIX)/bin
	install -m 0755 $(BIN) $(DESTDIR)$(PREFIX)/bin/$(BIN)

uninstall:
	rm -f $(DESTDIR)$(PREFIX)/bin/$(BIN)

# The .sha256 file names the tarball without a directory, so `shasum -a 256 -c` works after download.
dist: $(BIN)
	mkdir -p dist
	tar -czf "dist/$(BIN)-$$VERSION-macos-universal.tar.gz" $(BIN) README.md LICENSE CHANGELOG.md
	cd dist && shasum -a 256 "$(BIN)-$$VERSION-macos-universal.tar.gz" > "$(BIN)-$$VERSION-macos-universal.tar.gz.sha256"

clean:
	rm -rf $(BIN) dist
