#!/bin/sh

APP_NAME="ve_examples"
SRC_DIR="examples"
BIN_DIR="bin"
DEBUG_BIN="$BIN_DIR/debug/$APP_NAME"
RELEASE_BIN="$BIN_DIR/release/$APP_NAME"

ODIN_FLAGS="-custom-attribute:buffer"
ODIN_DEBUG_FLAGS="-debug $ODIN_FLAGS"
ODIN_RELEASE_FLAGS="-o:speed -no-bounds-check -disable-assert $ODIN_FLAGS"
ODIN="odin"

show_help() {
    echo "Usage: $0 {debug|release|all|run|run-release|gen|clean}"
    echo ""
    echo "Commands:"
    echo "  debug        - Build debug version"
    echo "  release      - Build release version"
    echo "  all          - Build both debug and release versions"
    echo "  run          - Build and run debug version"
    echo "  run-release  - Build and run release version"
    echo "  gen          - Generate shaders"
    echo "  clean        - Remove build directory"
    exit 0
}

case "$1" in
    debug)
        echo "Building debug examples ..."
        mkdir -p "$BIN_DIR/debug"
        $ODIN build "$SRC_DIR" -out:"$DEBUG_BIN" $ODIN_DEBUG_FLAGS
        echo "Built: $DEBUG_BIN"
        ;;
    
    release)
        echo "Building release examples ..."
        mkdir -p "$BIN_DIR/release"
        $ODIN build "$SRC_DIR" -out:"$RELEASE_BIN" -o:speed $ODIN_FLAGS
        echo "Built: $RELEASE_BIN"
        ;;
    
    all)
        echo "Building all examples ..."
        mkdir -p "$BIN_DIR/debug" "$BIN_DIR/release"
        $ODIN build "$SRC_DIR" -out:"$DEBUG_BIN" $ODIN_DEBUG_FLAGS
        echo "Built: $DEBUG_BIN"
        $ODIN build "$SRC_DIR" -out:"$RELEASE_BIN" -o:speed $ODIN_FLAGS
        echo "Built: $RELEASE_BIN"
        ;;
    
    run)
        echo "Building debug examples ..."
        mkdir -p "$BIN_DIR/debug"
        $ODIN build "$SRC_DIR" -out:"$DEBUG_BIN" $ODIN_DEBUG_FLAGS
        echo "Built: $DEBUG_BIN"
        echo "🐢 Running examples $DEBUG_BIN..."
        "$DEBUG_BIN"
        ;;
    
    run-release)
        echo "Building release examples ..."
        mkdir -p "$BIN_DIR/release"
        $ODIN build "$SRC_DIR" -out:"$RELEASE_BIN" -o:speed $ODIN_FLAGS
        echo "Built: $RELEASE_BIN"
        echo "🐇 Running example $RELEASE_BIN..."
        "$RELEASE_BIN"
        ;;
    
    gen)
        echo "Generating..."
        $ODIN run ./tools/shadertypegen/ -- \
            -outpute-glsl-dir:examples/assets/shaders/ \
            -src-dir:./examples \
            -ve-import:"ve .."
        ;;
    
    clean)
        echo "Cleaning..."
        rm -rf "$BIN_DIR"
        ;;
    
    help|--help|-h)
        show_help
        ;;
    
    *)
        echo "Error: Unknown command '$1'"
        echo ""
        show_help
        ;;
esac
