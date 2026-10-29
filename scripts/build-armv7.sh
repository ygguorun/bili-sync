#!/usr/bin/env bash
# 取回指定上游提交，应用本仓库的 Cross.toml，编译并打包 ARMv7 GNU 版本。
# 环境变量：UPSTREAM_REPO、UPSTREAM_SHA、TAG
# 可选：WORKDIR（默认 .work/upstream）、OUTDIR（默认 dist）、CONFIG_DIR（默认仓库根）

set -euo pipefail

: "${UPSTREAM_REPO:?缺少 UPSTREAM_REPO}"
: "${UPSTREAM_SHA:?缺少 UPSTREAM_SHA}"
: "${TAG:?缺少 TAG}"

TARGET=armv7-unknown-linux-gnueabihf
CONFIG_DIR="${CONFIG_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
WORKDIR="${WORKDIR:-$CONFIG_DIR/.work/upstream}"
OUTDIR="${OUTDIR:-$CONFIG_DIR/dist}"

[[ -f "$CONFIG_DIR/Cross.toml" ]] || { echo "错误：缺少 $CONFIG_DIR/Cross.toml" >&2; exit 1; }

rm -rf "$WORKDIR"
mkdir -p "$WORKDIR" "$OUTDIR"

git init -q "$WORKDIR"
git -C "$WORKDIR" remote add upstream "https://github.com/$UPSTREAM_REPO.git"
# 浅取固定提交：编译内容完全由该 SHA 决定，不受上游后续变化影响
git -C "$WORKDIR" fetch -q --depth 1 upstream "$UPSTREAM_SHA"
git -C "$WORKDIR" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD

# 自定义交叉编译配置不在上游仓库中，编译前覆盖进去
cp "$CONFIG_DIR/Cross.toml" "$WORKDIR/Cross.toml"

cd "$WORKDIR"

( cd web && bun install --frozen-lockfile && bun run build )

command -v cross >/dev/null || cargo install cross --locked
cross build --target "$TARGET" --release --locked

ASSET="bili-sync-rs-${TAG}-Linux-armv7-gnueabihf.tar.gz"
tar czf "$OUTDIR/$ASSET" -C "target/$TARGET/release" bili-sync-rs
echo "产物：$OUTDIR/$ASSET"
