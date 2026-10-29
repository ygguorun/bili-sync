#!/usr/bin/env bash
# 推送标签并发布 Release；重复运行会复用已有草稿或补传附件后重新发布。
# 环境变量：GITHUB_REPOSITORY、TAG、SHA、KIND（release|commit）、ASSET_PATH、UPSTREAM_REPO

set -euo pipefail

: "${GITHUB_REPOSITORY:?缺少 GITHUB_REPOSITORY}"
: "${TAG:?缺少 TAG}"
: "${SHA:?缺少 SHA}"
: "${KIND:?缺少 KIND}"
: "${ASSET_PATH:?缺少 ASSET_PATH}"

UPSTREAM_REPO="${UPSTREAM_REPO:-amtoaer/bili-sync}"
SERVER_URL="${GITHUB_SERVER_URL:-https://github.com}"

die() { echo "错误：$*" >&2; exit 1; }

[[ -f "$ASSET_PATH" ]] || die "找不到产物：$ASSET_PATH"

case "$KIND" in
  release) PRERELEASE=false; LATEST=true ;;
  commit) PRERELEASE=true; LATEST=false ;;
  *) die "未知类型：$KIND" ;;
esac

# 标签必须指向上游提交，而该提交不在本仓库，需要先取回对象再推送
git remote add upstream "https://github.com/$UPSTREAM_REPO.git" 2>/dev/null || true
git fetch -q --no-tags upstream main
# 提交通常就在 main 上；不在时按 SHA 取回，保证标签与 Release 指向正确提交
if ! git cat-file -e "$SHA^{commit}" 2>/dev/null; then
  git fetch -q upstream "$SHA"
fi

remote_sha="$(git ls-remote --tags origin "refs/tags/$TAG" | awk '{print $1}')"
if [[ -z "$remote_sha" ]]; then
  git tag -f "$TAG" "$SHA"
  git push -q origin "refs/tags/$TAG"
elif [[ "$remote_sha" != "$SHA" ]]; then
  die "标签 $TAG 已存在且指向 $remote_sha，与 $SHA 不一致"
fi

BODY="$(printf '%s\n' \
  "上游提交：$SERVER_URL/$UPSTREAM_REPO/commit/$SHA")"

# gh api 在 404 时仍会把错误 JSON 写到 stdout，必须按退出码判断
release_id=""
if ! release_id="$(gh api "repos/$GITHUB_REPOSITORY/releases/tags/$TAG" --jq '.id' 2>/dev/null)"; then
  release_id=""
fi
if [[ -z "$release_id" ]]; then
  release_id="$(gh api -X POST "repos/$GITHUB_REPOSITORY/releases" \
    -f tag_name="$TAG" -f name="$TAG" -f body="$BODY" -F draft=true --jq '.id')"
fi

gh release upload "$TAG" "$ASSET_PATH" --repo "$GITHUB_REPOSITORY" --clobber

gh api -X PATCH "repos/$GITHUB_REPOSITORY/releases/$release_id" \
  -F draft=false -F prerelease="$PRERELEASE" -f make_latest="$LATEST" >/dev/null

echo "已发布：$TAG"
