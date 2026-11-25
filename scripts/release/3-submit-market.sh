#!/usr/bin/env bash
# 第三步：给官方插件市场提条目。
#
# 做法：先 fork ccch1mneyyy/dsh-go-market，再在 fork 上写一个
# plugins/@twilightrain__dsh-shence.json（内容取自 market/entry.json），最后对上游 main 开 PR。
# 一个 PR 只加这一个文件，符合市场的「一次一个条目」规则。
#
# 用法：
#   export GITHUB_TOKEN=...
#   bash scripts/release/3-submit-market.sh              # 试跑
#   DRY_RUN=0 bash scripts/release/3-submit-market.sh    # 真提
#
# 前提：npm 上已经有 package.json 里这个精确版本。

set -euo pipefail
cd "$(dirname "$0")/../.."
. scripts/release/lib.sh

DRY_RUN="${DRY_RUN:-1}"
export DRY_RUN
require_github_token

MARKET_REPO="${UPSTREAM##*/}"
if [ "${PKG#@}" != "$PKG" ]; then
  # 带 scope：@scope/name 写成 plugins/@scope__name.json
  rest="${PKG#@}"
  ENTRY_PATH="plugins/@${rest/\//__}.json"
else
  # 无 scope：name 写成 plugins/name.json
  ENTRY_PATH="plugins/$PKG.json"
fi

say "包：$PKG@$VERSION"
say "条目文件：$ENTRY_PATH"
say "上游：$UPSTREAM"
say "模式：$([ "$DRY_RUN" = "1" ] && echo '试跑（不写文件、不开 PR）' || echo '真跑')"

say ""
say "1) 确认 npm 上有这个精确版本"
published="$(
  node --input-type=module -e '
const [pkg, version] = process.argv.slice(1)
const response = await fetch("https://registry.npmjs.org/" + encodeURIComponent(pkg))
if (!response.ok) { console.log(""); process.exit(0) }
const data = await response.json()
console.log(data.versions && data.versions[version] ? "yes" : "")
' "$PKG" "$VERSION"
)"
if [ "$published" != "yes" ]; then
  die "npm 上没有 $PKG@$VERSION。先跑第 2 步发布，市场只收精确版本。"
fi
say "   线上版本：$VERSION"

say ""
say "2) 生成条目（版本号以 package.json 为准）"
entry_file="$(mktemp)"
python3 - "$VERSION" "$entry_file" <<'PY'
import json,sys
version,out=sys.argv[1],sys.argv[2]
data=json.load(open("market/entry.json",encoding="utf-8"))
data["version"]=version
allowed={"tools","media","productivity","communication","other"}
if data.get("category") not in allowed:
    raise SystemExit("category 不在市场允许的集合里：%s" % data.get("category"))
for key in ("tier","risk","integrity"):
    data.pop(key,None)
if len(data.get("screenshots",[]))>4:
    raise SystemExit("截图最多 4 张")
for shot in data.get("screenshots",[]):
    if not shot.startswith("https://"):
        raise SystemExit("截图必须是 https：%s" % shot)
json.dump(data,open(out,"w",encoding="utf-8"),ensure_ascii=False,indent=2)
open(out,"a",encoding="utf-8").write("\n")
print(open(out,encoding="utf-8").read())
PY

say ""
say "3) 取当前账号"
me="$(api GET /user | read_json login || true)"
if [ -z "$me" ]; then
  if dry; then
    me="$OWNER"
    say "   试跑：令牌没验证，暂按 $me 走"
  else
    die "拿不到当前 GitHub 账号，令牌可能无效或没有 repo 权限"
  fi
fi
say "   $me"

say ""
say "4) 准备 fork"
fork_state="$(api GET "/repos/$me/$MARKET_REPO")"
if printf '%s' "$fork_state" | grep -q '"full_name"'; then
  say "   fork 已存在：https://github.com/$me/$MARKET_REPO"
else
  confirm "要在 $me 名下 fork $UPSTREAM 吗？（只是建 fork，不改上游）"
  if dry; then
    say "   [试跑] POST /repos/$UPSTREAM/forks"
  else
    forked="$(api POST "/repos/$UPSTREAM/forks" /dev/null)"
    if ! printf '%s' "$forked" | grep -q '"full_name"'; then
      # 有些情况下 fork 已经建好但接口返回慢，轮询一次
      sleep 5
    fi
    say "   已发起 fork：https://github.com/$me/$MARKET_REPO"
    for _ in $(seq 1 12); do
      sleep 5
      if api GET "/repos/$me/$MARKET_REPO" | grep -q '"full_name"'; then break; fi
    done
  fi
fi

say ""
say "5) 写入条目 $ENTRY_PATH"
existing="$(api GET "/repos/$me/$MARKET_REPO/contents/$ENTRY_PATH" 2>/dev/null || true)"
sha=""
if printf '%s' "$existing" | grep -q '"sha"'; then
  sha="$(printf '%s' "$existing" | read_json sha)"
  say "   文件已存在（sha ${sha:0:7}），会覆盖成当前版本"
fi
confirm "在 $me/$MARKET_REPO 的 main 上提交 $ENTRY_PATH（版本 $VERSION）？"
if dry; then
  say "   [试跑] PUT /repos/$me/$MARKET_REPO/contents/$ENTRY_PATH"
else
  payload="$(mktemp)"
  python3 - "$entry_file" "$sha" "$VERSION" "$payload" <<'PY'
import base64,json,sys
entry,sha,version,out=sys.argv[1],sys.argv[2],sys.argv[3],sys.argv[4]
body={
    "message": "Add entry for %s %s" % (json.load(open("package.json", encoding="utf-8"))["name"], version),
    "content": base64.b64encode(open(entry,"rb").read()).decode(),
    "branch": "main",
}
if sha:
    body["sha"]=sha
json.dump(body,open(out,"w"))
PY
  written="$(api PUT "/repos/$me/$MARKET_REPO/contents/$ENTRY_PATH" "$payload")"
  rm -f "$payload"
  printf '%s' "$written" | grep -q '"commit"' || die "写文件失败：$written"
  say "   已提交"
fi

say ""
say "6) 对上游开 PR"
pr_body="$(mktemp)"
cat > "$pr_body" <<PRBODY
New entry: \`$ENTRY_PATH\`

- npm: \`$PKG@$VERSION\` (MIT, published with \`--ignore-scripts\`)
- repo: https://github.com/$OWNER/$REPO (topic: dsh-plugin)
- What it is: a self-contained HTML text game shown in a DSH web panel
  (\`main\` key \`dsh-shence\` plus a matching \`sidebar.panellist\` row). No host-side
  tools, no network, no file access; saves live in the game's own localStorage keys.
- Checked with the dsh-go plugin checker (\`sdk/plugin-kit/bin/check.mjs\`): no errors;
  it reports "no dshGo manifest", which is expected for a web-UI-only plugin.
- Also verified on DSH 0.2.2-rc.5 web profile: the panel opens, the game plays, the save
  survives a reload, and the console stays clean.
PRBODY
payload="$(mktemp)"
python3 - "$pr_body" "$me" "Add $PKG $VERSION" "$VERSION" "$payload" <<'PY'
import json,sys
body_file,head,title,version,out=sys.argv[1:6]
text=open(body_file,encoding="utf-8").read()
json.dump({"title":title,"head":"%s:main"%head,"base":"main","body":text},open(out,"w"))
PY
if dry; then
  say "  [试跑] POST /repos/$UPSTREAM/pulls（标题：Add $PKG $VERSION）"
else
  pr="$(api POST "/repos/$UPSTREAM/pulls" "$payload" || true)"
  rm -f "$payload" "$pr_body"
  url="$(printf '%s' "$pr" | read_json html_url 2>/dev/null || true)"
  if [ -n "$url" ]; then
    say "   PR 开好了：$url"
    say "   自动检查跑完会自行合并，不需要人工点头。"
  else
    say "   没拿到 PR 链接，可能已经有一个开着的 PR："
    printf '%s\n' "$pr" | head -c 800
    say ""
  fi
fi

say ""
say "下一步：过一天再跑 bash scripts/release/4-verify.sh 看索引有没有收录。"
