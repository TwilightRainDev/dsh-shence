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
  local token="${GITHUB_TOKEN:-}"
  if [ -z "$token" ]; then
    cat >&2 <<'MSG'
停：没有拿到 GITHUB_TOKEN。

怎么建：
  1. 浏览器打开 GitHub，右上角头像，Settings
  2. 左侧最下面 Developer settings
  3. Personal access tokens，选 Tokens (classic)
  4. Generate new token (classic)，Note 随便写，Expiration 选个日子，勾上 repo
  5. 生成后复制那一串，以 ghp_ 开头

然后在这个终端里：
  export GITHUB_TOKEN=粘贴真令牌
（只放环境变量里，别写进文件，也别粘进聊天）
MSG
    exit 1
  fi
  case "$token" in
    *...*|*…*|*'<'*|*令牌*|*你的*)
      die "GITHUB_TOKEN 里是说明文字，不是真令牌（看着有省略号或中文）。换成 ghp_ 开头的那一串，长度约四十位。"
      ;;
  esac
  case "$token" in
    ghp_*|github_pat_*|gho_*|ghu_*) ;;
    *) die "GITHUB_TOKEN 开头不对：应当以 ghp_ 或 github_pat_ 开头，你现在这串是 ${#token} 位，开头是 ${token:0:3}" ;;
  esac
  if [ "${#token}" -lt 20 ]; then
    die "GITHUB_TOKEN 太短（${#token} 位），像是没复制全"
  fi
}

# 令牌形状对了不代表能用：先去问一次 GitHub 这串是谁的。
verify_github_token() {
  local who
  who="$(api GET /user | read_json login || true)"
  if [ -z "$who" ]; then
    die "GitHub 没认这串令牌（可能过期、复制多了空格，或者没勾 repo 权限）"
  fi
  say "   令牌属于 GitHub 账号：$who"
  if [ "$who" != "$OWNER" ]; then
    say "   提醒：下面按 $OWNER 操作，但令牌属于 $who。两者不一致时，建仓库和提 PR 会失败。"
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

# npm 只有在标准输入和标准输出都是终端时，才会自己弹出「用浏览器确认」那一步；
# 输出一旦接了管道（tee、重定向），它就判定不是交互环境，直接报 EOTP 退出。
# 所以发布这一步要按这个判断决定要不要套管道。
interactive_terminal() { [ -t 0 ] && [ -t 1 ]; }

# 直接从注册表读，不用 npm view：包刚发布时 npm view 会抛一堆 404 噪音。
registry_has_version() {
  node --input-type=module -e '
const [pkg, version] = process.argv.slice(1)
try {
  const response = await fetch("https://registry.npmjs.org/" + encodeURIComponent(pkg))
  if (!response.ok) process.exit(1)
  const data = await response.json()
  process.exit(data.versions && data.versions[version] ? 0 : 1)
} catch {
  process.exit(1)
}
' "$1" "$2"
}

# 发布之后注册表要过一会儿才认，等一等再下结论。
wait_for_registry() {
  local pkg="$1" version="$2" seconds="${3:-180}" waited=0
  while [ "$waited" -lt "$seconds" ]; do
    if registry_has_version "$pkg" "$version"; then
      return 0
    fi
    sleep 10
    waited=$((waited + 10))
    say "   还在等 npm 生效（已等 ${waited} 秒）"
  done
  registry_has_version "$pkg" "$version"
}

# npm 发布失败时把日志里的关键字翻成人话。只解释这一个常见原因，
# 其余情况把 npm 的原始输出留给使用者。
explain_publish_failure() {
  local log="$1"
  if grep -qiE "EOTP|auth/cli|doneUrl|authId" "$log"; then
    say ""
    say "npm 要你用浏览器确认一次（账号开的两步验证是安全密钥）。"
    say "在真终端里重跑，它会把确认网址打出来，复制到 Windows 浏览器打开并确认，"
    say "npm 会自己接着发布（网址大约五分钟内有效）。"
    say "如果这一步是被管道掐断的，会看到「不是交互终端」那个判断，重跑一次就行。"
    return 0
  fi
  if grep -qiE "two-factor|one-time password|bypass 2fa" "$log"; then
    say ""
    say "npm 拦下来的原因是「发布要求两步验证」，不是包本身的问题。两条路："
    say "  1. 打开 https://www.npmjs.com/settings/${NPM_USER:-你的用户名}/profile ，"
    say "     按页面提示开启两步验证（npm 现在只提供安全密钥，不再支持新增验证器应用），"
    say "     然后重跑这一步：发布时 npm 会让你在浏览器里用安全密钥确认一下。"
    say "  2. 或者建一个绕过两步验证的细粒度令牌（Granular Access Token），"
    say "     范围勾上这个包的 scope 的读写，再用 NPM_TOKEN 走。"
    say "     npm 正在收紧这种令牌，能走第 1 条就走第 1 条。"
  fi
}

run() {
  if dry; then printf '  [试跑] %s\n' "$*"; else "$@"; fi
}
