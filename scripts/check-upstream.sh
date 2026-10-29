#!/usr/bin/env bash
# 检测上游更新，列出需要编译发布的版本。
# 用法：bash scripts/check-upstream.sh [--self-test]
# 环境变量：GH_TOKEN、UPSTREAM_REPO、GITHUB_REPOSITORY
# 输出：candidates（JSON 数组）与 has_work，写入 $GITHUB_OUTPUT（本地运行时打印）

set -euo pipefail

UPSTREAM_REPO="${UPSTREAM_REPO:-amtoaer/bili-sync}"
TARGET_REPO="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner --jq '.nameWithOwner')}"
ASSET_SUFFIX="-Linux-armv7-gnueabihf.tar.gz"

die() { echo "错误：$*" >&2; exit 1; }

# 正式版：v2.11.1-g<sha12>-custom-build
# 普通提交：v2.11.1-dev-g<sha12>-custom-build
build_tag() {
  local base="$1" sha="$2" kind="$3"
  case "$kind" in
    release) printf '%s-g%s-custom-build\n' "$base" "${sha:0:12}" ;;
    commit) printf '%s-dev-g%s-custom-build\n' "$base" "${sha:0:12}" ;;
    *) die "未知类型：$kind" ;;
  esac
}

asset_name() { printf 'bili-sync-rs-%s%s\n' "$1" "$ASSET_SUFFIX"; }

# 同一提交既可能是普通提交、后来又成为正式版，因此两种身份分别判断
candidates_json() {
  local rel_tag="$1" rel_sha="$2" dev_base="$3" main_sha="$4" rel_done="$5" dev_done="$6"
  local json='[]' tag
  if [[ "$rel_done" != "true" ]]; then
    tag="$(build_tag "$rel_tag" "$rel_sha" release)"
    json="$(jq -c --arg t "$tag" --arg s "$rel_sha" --arg b "$rel_tag" \
      '. + [{tag: $t, sha: $s, base: $b, kind: "release", prerelease: "false"}]' <<<"$json")"
  fi
  # 正式版提交本身不再重复构建普通提交版本
  if [[ "$dev_done" != "true" && "$main_sha" != "$rel_sha" ]]; then
    tag="$(build_tag "$dev_base" "$main_sha" commit)"
    json="$(jq -c --arg t "$tag" --arg s "$main_sha" --arg b "$dev_base" \
      '. + [{tag: $t, sha: $s, base: $b, kind: "commit", prerelease: "true"}]' <<<"$json")"
  fi
  printf '%s\n' "$json"
}

# 只有“已发布且附件完整”才算完成，草稿或缺附件留给发布脚本处理
release_done() {
  local tag="$1" info
  info="$(gh release view "$tag" --repo "$TARGET_REPO" --json isDraft,assets 2>/dev/null || true)"
  [[ -n "$info" ]] || return 1
  [[ "$(jq -r '.isDraft' <<<"$info")" == "false" ]] || return 1
  jq -e --arg a "$(asset_name "$tag")" 'any(.assets[]; .name == $a)' <<<"$info" >/dev/null
}

self_test() {
  local json
  [[ "$(build_tag v2.11.1 abcdef123456789 release)" == "v2.11.1-gabcdef123456-custom-build" ]] || die "正式版标签不一致"
  [[ "$(build_tag v2.11.1 abcdef123456789 commit)" == "v2.11.1-dev-gabcdef123456-custom-build" ]] || die "普通提交标签不一致"
  [[ "$(asset_name v2.11.1-gabcdef123456-custom-build)" == "bili-sync-rs-v2.11.1-gabcdef123456-custom-build-Linux-armv7-gnueabihf.tar.gz" ]] || die "附件名不一致"

  json="$(candidates_json v2.11.1 sha1 v2.11.1 sha1 false false)"
  [[ "$(jq length <<<"$json")" == "1" ]] || die "同一提交不应重复构建"
  [[ "$(jq -r '.[0].kind' <<<"$json")" == "release" ]] || die "同一提交应优先正式版"

  json="$(candidates_json v2.11.1 sha1 v2.11.1 sha2 false false)"
  [[ "$(jq -r '[.[].kind] | join(",")' <<<"$json")" == "release,commit" ]] || die "正式版与后续提交应分别构建"

  json="$(candidates_json v2.11.1 sha1 v2.11.1 sha2 true false)"
  [[ "$(jq -r '[.[].kind] | join(",")' <<<"$json")" == "commit" ]] || die "正式版完成后只构建提交"

  json="$(candidates_json v2.11.1 sha1 v2.11.1 sha2 true true)"
  [[ "$(jq length <<<"$json")" == "0" ]] || die "全部完成后不应有候选"

  json="$(candidates_json v2.11.1 sha1 v2.11.0 sha1 true false)"
  [[ "$(jq length <<<"$json")" == "0" ]] || die "正式版提交不应再作为普通提交构建"

  echo "自检通过"
}

main() {
  local dir rel_tag rel_sha dev_base main_sha rel_done=false dev_done=false json
  TRAP_DIR="$(mktemp -d)"
  dir="$TRAP_DIR"
  trap 'rm -rf "$TRAP_DIR"' EXIT

  echo "读取上游 $UPSTREAM_REPO ..."
  git init -q "$dir"
  git -C "$dir" remote add upstream "https://github.com/$UPSTREAM_REPO.git"
  # 只需要提交和标签：blob 全部省略，用于定位版本与 describe
  git -C "$dir" fetch -q --filter=blob:none --tags upstream '+refs/heads/main:refs/remotes/upstream/main'

  main_sha="$(git -C "$dir" rev-parse refs/remotes/upstream/main)"
  rel_tag="$(gh api "repos/$UPSTREAM_REPO/releases/latest" --jq '.tag_name' 2>/dev/null || true)"
  [[ -n "$rel_tag" ]] || die "无法获取上游最新正式版"
  if ! rel_sha="$(git -C "$dir" rev-parse "refs/tags/$rel_tag^{commit}" 2>/dev/null)"; then
    die "无法解析 $rel_tag 对应的提交，请检查上游标签"
  fi

  # 普通提交的版本号取该提交可达的最近正式标签
  dev_base="$(git -C "$dir" describe --tags --abbrev=0 --match 'v[0-9]*' "$main_sha" 2>/dev/null || true)"
  [[ -n "$dev_base" ]] || dev_base="$rel_tag"

  if release_done "$(build_tag "$rel_tag" "$rel_sha" release)"; then rel_done=true; fi
  if release_done "$(build_tag "$dev_base" "$main_sha" commit)"; then dev_done=true; fi

  json="$(candidates_json "$rel_tag" "$rel_sha" "$dev_base" "$main_sha" "$rel_done" "$dev_done")"

  echo "上游正式版：$rel_tag（$rel_sha）"
  echo "上游 main：$main_sha（最近标签 $dev_base）"
  echo "候选：$json"

  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    {
      echo "candidates=$json"
      if [[ "$json" == "[]" ]]; then echo "has_work=false"; else echo "has_work=true"; fi
    } >>"$GITHUB_OUTPUT"
  fi
}

case "${1:-}" in
  --self-test) self_test ;;
  "") main ;;
  *) die "未知参数：$1" ;;
esac
