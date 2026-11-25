#!/usr/bin/env bash
# 第一步：把仓库推上 GitHub，并加上 dsh-plugin topic。
#
# 仓库不存在就建一个公开仓库（建公开仓库是不可逆的，脚本会先问），
# 然后用令牌走 HTTPS 推 main，最后把 topic 补上。
#
# 用法：
#   export GITHUB_TOKEN=...
#   bash scripts/release/1-push-repo.sh             # 会先试跑一遍给你看
#   DRY_RUN=0 bash scripts/release/1-push-repo.sh    # 真推
#
# 可选：GITHUB_OWNER=TwilightRainDev GITHUB_REPO=dsh-shence

set -euo pipefail
cd "$(dirname "$0")/../.."
. scripts/release/lib.sh

DRY_RUN="${DRY_RUN:-1}"
export DRY_RUN
require_github_token
verify_github_token

say "仓库：$OWNER/$REPO"
say "分支：$(git rev-parse --abbrev-ref HEAD)"
say "提交：$(git log -1 --format='%h %s')"
say "模式：$([ "$DRY_RUN" = "1" ] && echo '试跑（只看不做）' || echo '真跑')"

say ""
say "1) 确认远端仓库"
existing="$(api GET "/repos/$OWNER/$REPO")"
if printf '%s' "$existing" | grep -q '"full_name"'; then
  say "   已存在：https://github.com/$OWNER/$REPO"
else
  say "   不存在，需要新建一个公开仓库"
  confirm "要在 $OWNER 名下建公开仓库 $REPO 吗？建了就公开可搜。"
  if dry; then
    say "   [试跑] POST /user/repos {name:$REPO, private:false}"
  else
    payload="$(mktemp)"
    python3 -c '
import json,sys
json.dump({
  "name": sys.argv[1],
  "private": False,
  "description": "沈策又过了一天：DSH / DSH Go 插件版（自包含网页文字游戏）",
  "homepage": "https://github.com/%s/%s" % (sys.argv[2], sys.argv[1]),
  "has_issues": True,
  "has_wiki": False,
  "has_projects": False,
}, open(sys.argv[3], "w"), ensure_ascii=False)
' "$REPO" "$OWNER" "$payload"
    created="$(api POST /user/repos "$payload")"
    rm -f "$payload"
    printf '%s' "$created" | grep -q '"full_name"' || die "建仓库失败：$created"
    say "   建好了：https://github.com/$OWNER/$REPO"
  fi
fi

say ""
say "2) 推送 main"
if git remote get-url origin >/dev/null 2>&1; then
  run git remote set-url origin "https://github.com/$OWNER/$REPO.git"
else
  run git remote add origin "https://github.com/$OWNER/$REPO.git"
fi
if dry; then
  say "  [试跑] 会用临时 askpass 推 main（令牌不写进 .git/config）"
else
  askpass="$(mktemp)"
  chmod 700 "$askpass"
  trap 'rm -f "$askpass"' EXIT
  printf '#!/bin/sh\ncase "$1" in *[Uu]sername*) echo "x-access-token";; *) printf "%%s\\n" "%s";; esac\n' "$GITHUB_TOKEN" > "$askpass"
  GIT_ASKPASS="$askpass" GIT_TERMINAL_PROMPT=0 \
    git -c credential.helper= push -u origin "$(git rev-parse --abbrev-ref HEAD)"
  say "   推送完成"
fi

say ""
say "3) 补 dsh-plugin topic（dshfind 靠它认领）"
topics_json="$(api GET "/repos/$OWNER/$REPO/topics")"
merged="$(
  printf '%s' "$topics_json" | python3 -c '
import json,sys
try:
    names=json.load(sys.stdin).get("names",[])
except Exception:
    names=[]
for extra in ("dsh-plugin","dsh-bundle","deepseek-harness"):
    if extra not in names:
        names.append(extra)
print(json.dumps({"names":names}))
'
)"
if dry; then
  say "  [试跑] PUT /repos/$OWNER/$REPO/topics $merged"
else
  payload="$(mktemp)"
  printf '%s' "$merged" > "$payload"
  api PUT "/repos/$OWNER/$REPO/topics" "$payload" >/dev/null
  rm -f "$payload"
  say "   topic 已写：$merged"
fi

say ""
say "下一步：bash scripts/release/2-publish-npm.sh"
