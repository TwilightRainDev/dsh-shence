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
say "4) 看账号的两步验证设置"
NPM_USER="$who"
export NPM_USER
tfa="$(npm profile get 2>/dev/null | sed -n 's/^two-factor auth: //p' | head -1)"
tfa="${tfa:-未知}"
say "   两步验证：$tfa"
if [ "$tfa" = "disabled" ] && [ -z "${NPM_OTP:-}" ]; then
  say ""
  say "   npm 现在不允许两步验证关闭的账号直接发布，发出去也会被 403 拦下。两条路："
  say "   1. 打开 https://www.npmjs.com/settings/$who/profile ，按页面提示开启两步验证（现在只能用安全密钥）。"
  say "      开好之后重跑这一步，发布时 npm 会让你用安全密钥确认一下。"
  say "   2. 或者建一个「绕过两步验证」的细粒度令牌，用 NPM_TOKEN 走（npm 正在收紧这条路）。"
  if ! dry; then
    die "两步验证还没开，先按上面任一条准备好，再重跑这一步。什么都没发布。"
  fi
fi
if [ -n "${NPM_OTP:-}" ]; then
  # 只有早先配过验证器应用（TOTP）的账号才有六位数字可填，新账号已经不给配了。
  # 把说明文字或空格粘进来时，npm 只回一句「不是合法的 HTTP 头」，看不懂问题在哪，所以先拦。
  case "$NPM_OTP" in
    *[!0-9]*|"")
      die "NPM_OTP 里不是验证码。只有配过验证器应用的账号才需要它（六到八位数字），你现在给的是：$NPM_OTP"
      ;;
  esac
  if [ "${#NPM_OTP}" -lt 6 ] || [ "${#NPM_OTP}" -gt 8 ]; then
    die "NPM_OTP 位数不对（六到八位数字），现在是 ${#NPM_OTP} 位"
  fi
  say "   会用你给的验证码一起发布"
elif [ "$tfa" = "auth-only" ]; then
  say "   两步验证只保护授权类操作，发布不会再要第二次确认，直接发就行。"
elif [ "$tfa" = "auth-and-writes" ]; then
  say "   两步验证连写入也要确认：发布时 npm 会让你用安全密钥在浏览器里点一下。"
  say "   它会把确认用的网址打在终端上，按提示打开就行（WSL 里打不开就复制到 Windows 浏览器）。"
elif [ "$tfa" != "disabled" ] && [ "$tfa" != "未知" ]; then
  say "   两步验证的当前模式是 $tfa，发布时按 npm 的提示走。"
fi

say ""
say "5) 发布"
confirm "要把 $PKG@$VERSION 公开发布到 npm 吗？这一步发出去就收不回。"
publish_args=(--access public --ignore-scripts)
if [ -n "${NPM_OTP:-}" ]; then
  publish_args+=(--otp "$NPM_OTP")
fi
if [ -n "$npmrc" ]; then
  publish_args+=(--userconfig "$npmrc")
fi

# WSL 里 xdg-open 装着但开不起来，npm 会把它当成失败，整条认证就断了。
# 让 npm 不去开浏览器、只把网址打出来，由人复制到 Windows 浏览器，是最稳的一条。
if [ -n "${WSL_DISTRO_NAME:-}" ]; then
  publish_args+=(--browser=false)
fi

if interactive_terminal; then
  say "   输出方式：直接接到终端，npm 的确认流程能走通"
else
  say "   输出方式：接了管道。npm 在这种环境里会跳过确认、直接判失败，"
  say "   要在真终端里单独跑这一步。"
fi

if [ -n "${WSL_DISTRO_NAME:-}" ]; then
  say "   在 WSL 里：npm 不会自己开浏览器，它会把确认网址打在终端上，"
  say "   复制到 Windows 浏览器打开、按提示确认，这边会自己继续。"
fi

if dry; then
  say "  [试跑] npm publish ${publish_args[*]}"
else
  publish_log="$(mktemp)"
  set +e
  if interactive_terminal; then
    # 不套管道，让 npm 拿到真的终端，认证流程才走得下去
    npm publish "${publish_args[@]}"
    status=$?
    log_for_check="$(ls -t "$HOME"/.npm/_logs/*-debug-0.log 2>/dev/null | head -1)"
    [ -n "$log_for_check" ] || log_for_check="$publish_log"
  else
    npm publish "${publish_args[@]}" 2>&1 | tee "$publish_log"
    status="${PIPESTATUS[0]}"
    log_for_check="$publish_log"
  fi
  set -e
  if [ "$status" -ne 0 ]; then
    explain_publish_failure "$log_for_check"
    rm -f "$publish_log"
    die "发布没成功，上面是 npm 的原始输出。"
  fi
  rm -f "$publish_log"
fi

say ""
say "6) 核对线上元数据"
if dry; then
  say "  [试跑] npm view $PKG name version license repository dist.integrity --json"
else
  npm view "$PKG" name version license repository dist.integrity --json
fi

say ""
say "下一步：bash scripts/release/3-submit-market.sh"
