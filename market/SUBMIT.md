# 上架申请材料

官方市场的规则以 [`ccch1mneyyy/dsh-go-market`](https://github.com/ccch1mneyyy/dsh-go-market) 仓库为准，
本文只是把这次的条目和步骤抄成一份清单。四个状态互相独立，一步一步核：

先 npm 已发布，再 dshfind 索引有条目，再官方市场索引有条目，最后 App 里能装。

**不想手动复制命令就走脚本**：`scripts/release/` 下四个脚本把下面第 1–4 节做完了，
用法见 `scripts/release/README.md`。想自己一步步来，就照着本文走。

## 0. 先确认的东西

| 项 | 这次的取值 |
|---|---|
| npm 包名 | `@twilightrain/dsh-shence` |
| 版本 | `0.1.0`（市场只接受精确版本，不接受 `latest`/范围/Git 地址） |
| 许可 | MIT（OSI 认可） |
| 包体 | 压缩 56 KB，展开 141 KB，远低于 50 MiB 上限 |
| 安装脚本 | 无（发布时带 `--ignore-scripts`） |
| 分类 | `other` |
| 仓库 | `https://github.com/TwilightRainDev/dsh-shence`（公开，带 `dsh-plugin` topic） |

## 1. 推仓库

仓库里要真有 `README.md`、`LICENSE`、`assets/game.html`、`lib/client.js`、`screenshots/`。
截图条目写的是 `raw.githubusercontent.com` 上的地址，仓库没推上去之前那三条链接是 404，
市场检查会因此失败。

推完给仓库加一个 topic：`dsh-plugin`。这是 dshfind 发现任务认领的记号。

## 2. 发布 npm 包

```sh
cd dsh-shence
npm run build                     # 重新生成 lib/client.js
npm test                          # 4 项离线自检应当全绿
npm pack --dry-run --ignore-scripts   # 确认只打 7 个文件
npm login                         # 用 twilightrain 账号
npm publish --access public --ignore-scripts
npm view @twilightrain/dsh-shence name version license repository dist.integrity --json
```

回链要指回公开仓库，否则索引不认。

## 3. 进 dshfind 发现索引（决定「全部」分区）

```sh
node --input-type=module <<'JS'
const response = await fetch('https://api.dshfind.com/market/dsh-index.json')
const index = await response.json()
console.log(index.plugins?.find((p) => p.name === '@twilightrain/dsh-shence') ?? 'not listed yet')
JS
```

发现任务是定时跑的，不承诺多久到账；过一天再查。

## 4. 上架官方市场（决定「官方」「适配 DSH Go」分区）

1. Fork `ccch1mneyyy/dsh-go-market`。
2. 把 `market/entry.json` 的内容原样存成 `plugins/@twilightrain__dsh-shence.json`
   （带 scope 的包名用 `@scope__name.json` 的写法）。
3. 一个 PR 只加这一个文件，向 `main` 提。

PR 标题：

```
Add @twilightrain/dsh-shence 0.1.0
```

PR 正文：

```
New entry: plugins/@twilightrain__dsh-shence.json

- npm: @twilightrain/dsh-shence@0.1.0 (MIT, published with --ignore-scripts)
- repo: https://github.com/TwilightRainDev/dsh-shence (topic: dsh-plugin)
- What it is: a self-contained HTML text game shown in a DSH web panel
  (main key `dsh-shence` + matching sidebar.panellist row). No host-side
  tools, no network, no files; saves live in the game's own localStorage keys.
- Verified with the dsh-go plugin checker (sdk/plugin-kit bin/check.mjs):
  no errors; it reports "no dshGo manifest" as expected for a web-UI-only plugin.
- Also verified in DSH 0.2.2-rc.5 web profile: panel opens, game plays,
  save survives a reload, no console errors.
```

市场会自己重新下载 tarball 校验 SHA-512、许可、归档结构、包身份与 DSH bundle patch，
然后跑 npm 公告查询；这些都过了会自动合并，不需要人工点头。

## 5. 提完之后核这些

| 状态 | 怎么确认 |
|---|---|
| npm 已发布 | `npm view @twilightrain/dsh-shence version` |
| dshfind 索引 | 上面第 3 步的查询脚本 |
| 官方市场索引 | `https://go.dshtui.com/market/index.json` 里按包名搜 |
| App 能装 | App 插件市场搜包名，选目标主机，装上后点侧栏那一行 |

## 会被标风险的地方

市场的静态扫描只看代码特征，不打分、不封禁。这个包预计会被标：

- 大型压缩或编码过的源码（`lib/client.js` 里那段 base64 的游戏网页），可能记为 medium。

安装时会先列出原因让用户确认。这一段是内联的游戏网页，不是混淆代码；
`src/client.js` 与 `scripts/build.mjs` 都在仓库里，构建过程可复现。

## 可选：第三方目录

`dsh.plus` 之类的人工目录是另一套申请入口（站点上的「申请收录」），
规则是「只收录与展示开源项目」，要求和官方市场不冲突，想要更多曝光再去填。
