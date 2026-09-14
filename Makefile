# Rux Build System
# Production-grade Darwin Mach-O Injection Library & Toolchain (Rust)

CARGO ?= cargo

STATIC_LIB = libmachinject.a
DYLIB = libmachinject.dylib
PAYLOAD_DYLIB = exploit.dylib
BINARIES = rux inject injectarm

.PHONY: all build test clean app

all: build app

build:
	@echo "[CARGO] Building Rux Rust workspace in release mode..."
	$(CARGO) build --release --workspace
	@cp target/release/libmachinject.a $(STATIC_LIB)
	@cp target/release/libmachinject.dylib $(DYLIB)
	@cp target/release/librux_payload.dylib $(PAYLOAD_DYLIB)
	@cp target/release/rux rux
	@cp target/release/inject inject
	@cp target/release/injectarm injectarm
	@echo "[OK] Build completed successfully."

test:
	@echo "[Test] Executing Rust unit & integration test suite..."
	$(CARGO) test --workspace
	@echo "\n[Test] Executing Rux CLI diagnostic test suite..."
	./rux test

clean:
	@echo "[Clean] Removing build artifacts..."
	$(CARGO) clean
	rm -f $(STATIC_LIB) $(DYLIB) $(PAYLOAD_DYLIB) $(BINARIES)
	rm -rf Rux.app app/build

app: build
	@echo "[APP] Building native macOS Application (Rux.app)..."
	@./app/build_app.sh
