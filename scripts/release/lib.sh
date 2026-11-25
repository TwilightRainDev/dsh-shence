#!/usr/bin/env bash
# 发布脚本共用的几件小事：读令牌、调 GitHub API、问一句再动手。
# 令牌只从环境变量读，不写进任何文件；失败信息说人话，不打印令牌本身。

set -euo pipefail

OWNER="${GITHUB_OWNER:-TwilightRainDev}"
REPO="${GITHUB_REPO:-dsh-shence}"
UPSTREAM="ccch1mneyyy/dsh-go-market"
# 默认取 package.json；DSH_PKG_OVERRIDE / DSH_VERSION_OVERRIDE 只用来排练脚本，
# 比如拿一个确实在 npm 上的包把后面的流程跑一遍，别在真发布时设它。
PKG="${DSH_PKG_OVERRIDE:-$(
  node -e 'const p=require("./package.json");process.stdout.write(p.name)' 2>/dev/null \
    || python3 -c 'import json;print(json.load(open("package.json"))["name"])'
)}"
VERSION="${DSH_VERSION_OVERRIDE:-$(
  node -e 'const p=require("./package.json");process.stdout.write(p.version)' 2>/dev/null \
    || python3 -c 'import json;print(json.load(open("package.json"))["version"])'
)}"
if [ -n "${DSH_PKG_OVERRIDE:-}" ] || [ -n "${DSH_VERSION_OVERRIDE:-}" ]; then
  printf '注意：正在用排练用的包名/版本 %s@%s，不是 package.json 里的\n' "$PKG" "$VERSION" >&2
fi

export PKG VERSION OWNER REPO UPSTREAM

say() { printf '%s\n' "$*"; }
die() { printf '\n停：%s\n' "$*" >&2; exit 1; }

# 有令牌就校验形状，没有令牌的步骤（npm 发布）不强制。
require_github_token() {
  if [ -z "${GITHUB_TOKEN:-}" ]; then
    die "没有 GITHUB_TOKEN。去 GitHub 设置里建一个带 repo 权限的令牌，然后：
    export GITHUB_TOKEN=...（不要写进任何文件，也不要粘进聊天）"
  fi
  case "$GITHUB_TOKEN" in
    ghp_*|github_pat_*|gho_*|ghu_*) ;;
    *) die "GITHUB_TOKEN 看着不像 GitHub 的令牌（应以 ghp_ 或 github_pat_ 开头）" ;;
  esac
  if [ "${#GITHUB_TOKEN}" -lt 20 ]; then
    die "GITHUB_TOKEN 太短，像是没复制全"
  fi
}

api() {
  # api <METHOD> <path> [body-file]
  local method="$1" path="$2" body="${3:-}"
  if [ -n "$body" ]; then
    curl -sS -X "$method" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      -H "Content-Type: application/json" \
      --data-binary "@$body" \
      "https://api.github.com$path"
  else
    curl -sS -X "$method" \
      -H "Authorization: Bearer $GITHUB_TOKEN" \
      -H "Accept: application/vnd.github+json" \
      -H "X-GitHub-Api-Version: 2022-11-28" \
      "https://api.github.com$path"
  fi
}

# 从 JSON 里取一个字段：read_json <点号路径>
read_json() {
  python3 -c '
import json,sys
data=json.load(sys.stdin)
node=data
for part in sys.argv[1].split("."):
    if isinstance(node,list):
        node=node[int(part)]
    elif isinstance(node,dict):
        node=node.get(part)
        if node is None:
            print("");raise SystemExit
    else:
        print("");raise SystemExit
print(node if isinstance(node,(str,int,float,bool)) else json.dumps(node,ensure_ascii=False))
' "$1"
}

confirm() {
  if [ "${ASSUME_YES:-0}" = "1" ] || [ "${DRY_RUN:-0}" = "1" ]; then return 0; fi
  if [ ! -t 0 ]; then
    die "这不是交互终端。确认没问题就加 ASSUME_YES=1 重跑，或者先 DRY_RUN=1 看一遍。"
  fi
  printf '\n%s\n继续吗？输入 y 或 yes 回车：' "$1"
  local answer=""
  read -r answer
  case "$(printf '%s' "$answer" | tr -d '[:space:]')" in
    y|Y|yes|YES|Yes|是|好) ;;
    *) die "已取消，什么都没改。" ;;
  esac
}

dry() { [ "${DRY_RUN:-0}" = "1" ]; }

# npm 发布失败时把日志里的关键字翻成人话。只解释这一个常见原因，
# 其余情况把 npm 的原始输出留给使用者。
explain_publish_failure() {
  local log="$1"
  if grep -qiE "two-factor|one-time password|bypass 2fa|EOTP" "$log"; then
    say ""
    say "npm 拦下来的原因是「发布要求两步验证」，不是包本身的问题。两条路："
    say "  1. 打开 https://www.npmjs.com/settings/${NPM_USER:-你的用户名}/profile ，"
    say "     把两步验证设成「授权与写入」，然后重跑这一步；"
    say "     发布时 npm 会当场问你要六位数字，照着验证器敲。"
    say "  2. 或者建一个绕过两步验证的细粒度令牌（Granular Access Token），"
    say "     范围勾上这个包的 scope 的读写，再用 NPM_TOKEN 走。"
    say "     npm 正在收紧这种令牌，能走第 1 条就走第 1 条。"
  fi
}

run() {
  if dry; then printf '  [试跑] %s\n' "$*"; else "$@"; fi
}
