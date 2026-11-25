#!/usr/bin/env bash
# 第二步：把包发布到 npm。
#
# 发之前先自己重跑一遍构建与自检，再核对 tarball 里只有该有的文件；
# 同名同版本已经发过就停下，不会覆盖。
#
# 用法：
#   bash scripts/release/2-publish-npm.sh              # 试跑
#   DRY_RUN=0 bash scripts/release/2-publish-npm.sh    # 真发
#
# 登录方式二选一：
#   npm login                                  （交互，最稳）
#   export NPM_TOKEN=...                       （有 token 时脚本用临时 npmrc，用完删掉）

set -euo pipefail
cd "$(dirname "$0")/../.."
. scripts/release/lib.sh

DRY_RUN="${DRY_RUN:-1}"
export DRY_RUN

say "包：$PKG@$VERSION"
say "模式：$([ "$DRY_RUN" = "1" ] && echo '试跑（不发布）' || echo '真跑')"

say ""
say "1) 构建 + 自检 + 打包检查（本地操作，试跑时也照做）"
node scripts/build.mjs
node --test --test-reporter=dot test/plugin.test.js
node --check lib/client.js
node --check lib/index.js
pack_json="$(npm pack --dry-run --json --ignore-scripts 2>/dev/null)"
printf '%s' "$pack_json" | python3 -c '
import json,sys
entry=json.load(sys.stdin)[0]
files=[f["path"] for f in entry["files"]]
required={"package.json","cordis.patch.yml","lib/index.js","lib/client.js","README.md","LICENSE"}
missing=required-set(files)
if missing:
    print("包里缺文件：", ", ".join(sorted(missing)));raise SystemExit(1)
for banned in ("node_modules","assets/","src/","test/","screenshots/","market/"):
    if any(f.startswith(banned) for f in files):
        print("包里混进了不该发布的目录：", banned);raise SystemExit(1)
print("   tarball：%d 个文件，压缩 %d 字节，展开 %d 字节" % (len(files), entry["size"], entry["unpackedSize"]))
if entry["size"] > 50*1024*1024:
    print("   超过市场 50 MiB 上限");raise SystemExit(1)
'

say ""
say "2) 确认线上还没有这个版本"
published="$(
  node --input-type=module -e '
const [pkg, version] = process.argv.slice(1)
const response = await fetch("https://registry.npmjs.org/" + encodeURIComponent(pkg))
if (!response.ok) { console.log(""); process.exit(0) }
const data = await response.json()
console.log(data.versions && data.versions[version] ? "yes" : "")
' "$PKG" "$VERSION"
)"
if [ "$published" = "yes" ]; then
  die "$PKG@$VERSION 已经在 npm 上了。改 package.json 的 version 再发，不要覆盖已发布版本。"
fi
say "   线上没有 $VERSION，可以发"

say ""
say "3) 确认登录身份"
who="$(npm whoami 2>/dev/null || true)"
npmrc=""
if [ -z "$who" ] && [ -n "${NPM_TOKEN:-}" ]; then
  npmrc="$(mktemp)"
  chmod 600 "$npmrc"
  printf '//registry.npmjs.org/:_authToken=${NPM_TOKEN}\n' > "$npmrc"
  trap '[ -n "%s" ] && rm -f "%s"' EXIT
  who="$(npm whoami --userconfig "$npmrc" 2>/dev/null || true)"
fi
if [ -z "$who" ]; then
  if dry; then
    say "   试跑：当前没登录；真跑前先 npm login，或者 export NPM_TOKEN=..."
    who="(未登录)"
  else
    die "npm 没登录。先跑 npm login，或者 export NPM_TOKEN=... 再重跑。"
  fi
fi
say "   当前身份：$who"
case "$PKG" in
  @*)
    scope="${PKG%%/*}"
    scope="${scope#@}"
    if [ "$who" != "$scope" ] && [ "$who" != "(未登录)" ]; then
      say "   提醒：包在 @$scope 名下，但登录的是 $who。"
      say "         有该 scope 的发布权限就行；没有的话 npm 会直接拒绝。"
    fi
    ;;
esac

say ""
say "4) 发布"
confirm "要把 $PKG@$VERSION 公开发布到 npm 吗？这一步发出去就收不回。"
if dry; then
  say "  [试跑] npm publish --access public --ignore-scripts"
else
  if [ -n "$npmrc" ]; then
    npm publish --access public --ignore-scripts --userconfig "$npmrc"
  else
    npm publish --access public --ignore-scripts
  fi
fi

say ""
say "5) 核对线上元数据"
if dry; then
  say "  [试跑] npm view $PKG name version license repository dist.integrity --json"
else
  npm view "$PKG" name version license repository dist.integrity --json
fi

say ""
say "下一步：bash scripts/release/3-submit-market.sh"
