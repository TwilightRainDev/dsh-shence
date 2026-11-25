#!/usr/bin/env bash
# 第四步：核对四个状态。发布和提 PR 之后随时可以跑，只读，不改任何东西。
#
#   顺序：npm 已发布，dshfind 索引有条目，官方市场索引有条目，最后 App 里能装
#
# 用法：bash scripts/release/4-verify.sh
# 索引是定时重建的，刚提完 PR 查不到是正常的，过几小时再来。

set -euo pipefail
cd "$(dirname "$0")/../.."
. scripts/release/lib.sh

say "包：$PKG@$VERSION"
ok()   { say "  [完成] $*"; }
todo() { say "  [等待] $*"; }
no()   { say "  [没有] $*"; }

say ""
say "1) npm"
meta="$(
  node --input-type=module -e '
const pkg = process.env.PKG
const response = await fetch("https://registry.npmjs.org/" + encodeURIComponent(pkg))
if (!response.ok) process.exit(0)
const data = await response.json()
const latest = (data["dist-tags"] && data["dist-tags"].latest) || ""
const entry = (data.versions && data.versions[latest]) || {}
const repo = typeof entry.repository === "string" ? entry.repository : (entry.repository && entry.repository.url) || ""
console.log(JSON.stringify({ latest, license: entry.license || "", repo }))
' 2>/dev/null || true
)"
if [ -z "$meta" ]; then
  no "npm 上查不到 $PKG（还没发布，或者包名写错了）"
else
  printf '%s' "$meta" | python3 -c '
import json,sys
d=json.load(sys.stdin)
latest=d.get("latest") or ""
repo=d.get("repo") or ""
print("  [完成] 线上最新版 %s，许可 %s" % (latest or "?", d.get("license") or "?"))
print("     仓库 %s%s" % (repo, "" if "github.com" in repo else "  ← 回链不对，索引不会认"))
'
  if [ "$(printf '%s' "$meta" | python3 -c 'import json,sys;print(json.load(sys.stdin).get("latest") or "")')" = "$VERSION" ]; then
    ok "线上最新版就是 package.json 里的 $VERSION"
  else
    todo "线上最新版与 package.json 的 $VERSION 不一致（提市场前必须一致）"
  fi
fi

say ""
say "2) dshfind 发现索引（决定 App 的「全部」分区）"
node --input-type=module -e '
const name = process.env.PKG
const response = await fetch("https://api.dshfind.com/market/dsh-index.json")
if (!response.ok) { console.log("  无法读取索引：HTTP " + response.status); process.exit(0) }
const index = await response.json()
const entry = (index.plugins ?? []).find((p) => p.name === name)
if (!entry) { console.log("  [等待] 还没有条目（发现任务是定时的）"); process.exit(0) }
const versions = (entry.versions ?? []).map((v) => v.version)
const mine = process.env.VERSION
console.log("  [完成] 已收录，最新 " + (versions[0] ?? "?") + (versions.includes(mine) ? "，含 " + mine : "，还没有 " + mine))
' 2>/dev/null || say "  [等待] 查询失败，稍后再试"

say ""
say "3) 官方市场索引（决定「官方」「适配 DSH Go」分区）"
node --input-type=module -e '
const name = process.env.PKG
const response = await fetch("https://go.dshtui.com/market/index.json")
if (!response.ok) { console.log("  无法读取索引：HTTP " + response.status); process.exit(0) }
const index = await response.json()
const list = index.plugins ?? index.entries ?? []
const entry = list.find((p) => p.name === name)
if (!entry) { console.log("  [等待] 还没有条目（PR 合并后等索引重建）"); process.exit(0) }
const versions = (entry.versions ?? []).map((v) => v.version)
const mine = process.env.VERSION
const engines = (entry.versions ?? [])[0]?.engines?.dsh ?? ""
console.log("  [完成] 已收录，最新 " + (versions[0] ?? "?") + (versions.includes(mine) ? "，含 " + mine : "，还没有 " + mine))
if (engines) console.log("     engines.dsh：" + engines)
' 2>/dev/null || say "  [等待] 查询失败，稍后再试"

say ""
say "4) App 里能不能装 —— 这一条只能你自己看"
say "   打开 DSH Go 的插件市场，搜 $PKG，核对版本、来源主机，装上后点侧栏那一行。"
say ""
say "跑完这一页，四件事就都落实了。"
