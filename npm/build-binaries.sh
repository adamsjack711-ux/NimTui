#!/bin/sh
# Build the dashboard for all npm-shipped platforms into npm/dist/.
# Run from the repo root on macOS. Linux targets cross-compile through
# `zig cc` (static musl); darwin-x64 through Apple clang's -arch flag.
set -e

cd "$(dirname "$0")/.."

mkdir -p /tmp/loom-zigcc
cat > /tmp/loom-zigcc/zigcc-linux-x64 <<'EOF'
#!/bin/sh
exec zig cc -target x86_64-linux-musl "$@"
EOF
cat > /tmp/loom-zigcc/zigcc-linux-arm64 <<'EOF'
#!/bin/sh
exec zig cc -target aarch64-linux-musl "$@"
EOF
chmod +x /tmp/loom-zigcc/zigcc-*

build_linux() {
  cpu="$1"; triple="$2"; out="$3"
  mkdir -p "npm/dist/$out"
  nim c -d:release --opt:size --hints:off \
    --os:linux --cpu:"$cpu" --cc:clang \
    --clang.exe="/tmp/loom-zigcc/zigcc-$triple" \
    --clang.linkerexe="/tmp/loom-zigcc/zigcc-$triple" \
    --passL:"-static -s" \
    -o:"npm/dist/$out/nimtui" examples/dashboard.nim
}

echo "== linux-x64 (static musl)"
build_linux amd64 linux-x64 linux-x64

echo "== linux-arm64 (static musl)"
build_linux arm64 linux-arm64 linux-arm64

echo "== darwin-x64"
mkdir -p npm/dist/darwin-x64
nim c -d:release --opt:size --hints:off --cpu:amd64 \
  --passC:"-arch x86_64" --passL:"-arch x86_64" \
  -o:npm/dist/darwin-x64/nimtui examples/dashboard.nim

echo "== darwin-arm64 (native)"
mkdir -p npm/dist/darwin-arm64
nim c -d:release --opt:size --hints:off \
  -o:npm/dist/darwin-arm64/nimtui examples/dashboard.nim

chmod +x npm/dist/*/nimtui
echo "== done:"
file npm/dist/*/nimtui
