# 发布与上架脚本

这四步按顺序跑，每一步默认**试跑**（只打印要做什么，不发请求、不推送、不发布），
看清楚再加 `DRY_RUN=0` 真跑。

```sh
export GITHUB_TOKEN=...            # 只放在环境变量里，别写进文件、别粘进聊天

bash scripts/release/1-push-repo.sh            # 看一遍要建什么仓库、推哪个分支
DRY_RUN=0 bash scripts/release/1-push-repo.sh  # 真推（会问一次 yes）

bash scripts/release/2-publish-npm.sh           # 本地重跑构建+自检，再报要发什么
DRY_RUN=0 bash scripts/release/2-publish-npm.sh # 真发（会问一次 yes）

bash scripts/release/3-submit-market.sh            # 报要写哪个条目、开什么 PR
DRY_RUN=0 bash scripts/release/3-submit-market.sh  # 真提（会问一次 yes）

bash scripts/release/4-verify.sh                # 只读，随时可跑
```

## 前置

| 需要 | 怎么来 |
|---|---|
| `GITHUB_TOKEN` | 打开 GitHub 的 Settings，进 Developer settings，选 Tokens (classic)，勾上 `repo`。第 1 步要建仓库，细粒度令牌要多配几项权限，classic 省事 |
| npm 登录 | `npm login`（交互）；有令牌就 `export NPM_TOKEN=...`，脚本会用一个临时 `.npmrc`，用完删掉。账号开了两步验证的话，发布时 npm 会让你在浏览器里用安全密钥确认，不用提前准备验证码 |
| 顺序 | 必须按 1、2、3 的顺序跑。市场只收 npm 上已经存在的精确版本，截图链接也要仓库推上去之后才不是 404 |

## 脚本都做了什么

| 脚本 | 动作 | 可逆吗 |
|---|---|---|
| `1-push-repo.sh` | 仓库不存在就建公开仓库，用临时 askpass 推 `main`，再补 `dsh-plugin` 等 topic | 推送可撤回；**建公开仓库不可逆**，所以会先问 |
| `2-publish-npm.sh` | 重跑构建与 4 项自检，检查 tarball 只有该有的 7 个文件，确认线上没有同名版本，再跑 `npm publish --access public --ignore-scripts`，最后用 `npm view` 核对 | **不可逆**，npm 不允许覆盖已发布版本 |
| `3-submit-market.sh` | fork `ccch1mneyyy/dsh-go-market`，在 fork 的 main 上写 `plugins/<条目>.json`，再对上游 `main` 开 PR | PR 可以关；合并由市场自动检查决定 |
| `4-verify.sh` | 只读：npm、dshfind 索引、官方市场索引各查一遍 | 改不了任何东西 |

## 令牌怎么用才不会漏

脚本只用两种方式带上令牌，都不落盘：

- GitHub API：`curl -H "Authorization: Bearer $GITHUB_TOKEN"`。
- git 推送：临时生成一个 700 权限的 askpass 脚本，`GIT_ASKPASS` 指过去，退出时 `trap` 删掉；
  同时 `-c credential.helper=` 关掉凭据缓存，令牌不会写进 `.git/config`。

`lib.sh` 还会先看令牌的形状（以 `ghp_` / `github_pat_` 开头、长度够），不对就直接停。

## 排练

不想拿真包试流程，可以用 `DSH_PKG_OVERRIDE` / `DSH_VERSION_OVERRIDE` 换成一个确实在 npm 上的包名，

```sh
GITHUB_TOKEN=... DSH_PKG_OVERRIDE=dsh-context DSH_VERSION_OVERRIDE=0.78.2 \
  bash scripts/release/3-submit-market.sh        # 试跑，不写不提交
```

脚本会在开头说明「正在用排练用的包名/版本」。真发布时不要设这两个变量。

## 出问题先看这里

| 现象 | 先核对 |
|---|---|
| 第 1 步：`401` / `404` 但仓库明明在 | 令牌没 `repo` 权限，或者 `GITHUB_OWNER` 写错了（默认 `TwilightRainDev`） |
| 第 1 步：推送被拒 `non-fast-forward` | 远端已有提交，先 `git pull --rebase origin main` 再跑 |
| 第 2 步：发布被拒 `403 scope` | 登录账号没有 `@twilightrain` 这个 scope 的发布权 |
| 第 2 步：`E409 version exists` | 同名版本已存在，改 `package.json` 的 `version`，不要覆盖 |
| 第 2 步：`E403` 提到 two-factor | npm 要求先开两步验证。npm 现在只提供安全密钥（WebAuthn），不再支持新增验证器应用；开好之后重跑，发布时在浏览器里确认一下 |
| 第 2 步：问「验证码怎么填」 | 新账号没有验证码这一步，`NPM_OTP` 只对早先配过验证器应用的账号有用 |
| 第 3 步：`npm 上没有 ...` | 第 2 步没成功，市场只收精确版本 |
| 第 3 步：PR 打不开、返回 422 | fork 里已经有开着的 PR，去 GitHub 上看一眼 |
| 第 4 步：索引显示「[等待]」 | 正常。发现任务与索引重建都是定时的，过几小时再跑 |
| App 里搜不到 | 确认在「全部」分区搜、包名完整、以及插件是否已合并进市场索引 |
