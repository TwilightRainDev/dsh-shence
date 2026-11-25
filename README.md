# 沈策又过了一天 · DSH 插件

把这份单文件网页文字游戏装进 [DSH](https://github.com/deepseek-ai/deepseek-harness) 的界面里：
网页版侧栏多一个面板，DSH Go 里以网页岛打开。游戏本身一行没改，离线可玩。

| 装在哪 | 看到什么 |
|---|---|
| DSH 网页版（桌面 / 浏览器） | 侧栏与「全部功能 › 插件」里多一行「沈策又过了一天」 |
| DSH Go（手机） | 同一份网页界面，以网页岛打开；需要本机引擎那台主机 |

## 安装

App 内：插件市场搜 `@twilightrain/dsh-shence`，选目标主机安装。

命令行（在引擎所在的那台机器上执行）：

```sh
dsh plugin --profile <你的 profile> add @twilightrain/dsh-shence
```

本地目录也能装，改完立刻看得见：

```sh
dsh plugin --profile <你的 profile> add /绝对路径/dsh-shence
```

装好后打开 DSH 网页版，侧栏底部或「全部功能 › 插件」里点「沈策又过了一天」。

## 它是怎么接进界面的

- 宿主半侧（`lib/index.js`）什么都不做：这个插件没有工具、不碰文件、不发网络请求。
- 浏览器半侧（`lib/client.js`）向 DSH 网页版注册两处界面：`main` 槽的 `dsh-shence` 面板，和同名的 `sidebar.panellist` 侧栏条目。两边 id 相同，点条目就切到面板。
- 面板里是一个同源 iframe，`srcDoc` 就是 `assets/game.html` 那份网页（构建时以 base64 内联进 `lib/client.js`）。不新增路由，所以装到哪台主机都一样。

## 数据与隐私

- 不联网：网页里没有任何 `fetch` / `XMLHttpRequest` / 外部链接，测试会钉住这一条。
- 存档留在本机：只写游戏自己的 `localStorage` 键（`shen_zhe_day_v1`、`shen_zhe_day_v1_stats`、`story_ch`），不碰宿主的任何存储。
- 存档跟着网页版的来源走：手机本机引擎固定是 `http://127.0.0.1:3080`，重开 App 还能接着玩；换成远程主机、或者换个端口打开网页版，就是另一份存档。
- 想重来：游戏内弹窗里有「清空存档」。卸载插件不会替你删存档——它属于浏览器/WebView 里这个源，跟插件包无关。
- 不读剪贴板、不请求麦克风、摄像头、定位（iframe 上显式禁掉）。

## 兼容

- 需要 DSH `>=0.2.2-rc.1 <0.3.0-0`（`engines.dsh`），Node 20+。
- 手机上的网页岛要本机引擎、桥接占用表和资源预算都满足才会打开；不满足时 DSH 会退回「在网页版打开」，游戏照样能玩。
- 没有做原生（Flutter）界面：游戏是整页 DOM 与逐日文本流，原生面板那套有界视图装不下，所以按 DSH Go 文档里「已有网页界面」那条路走。

## 验证记录

这一版实际跑过的东西，不是推测：

| 查什么 | 怎么查 | 结果 |
|---|---|---|
| 内联的网页是不是原文件 | `npm test` | 4 项全过；`lib/client.js` 里的 base64 解回来与 `assets/game.html` 逐字节相同，sha256 对得上 |
| 官方检查器 | dsh-go 的 `sdk/plugin-kit/bin/check.mjs` | 无错误；只提示「没有 dshGo 清单」，网页界面插件本来就该如此 |
| 真装进 DSH | DSH 0.2.2-rc.5 网页版，profile 用本地目录安装 | 引导图里有 `@twilightrain/dsh-shence` 这一行；侧栏出现条目 |
| 面板能不能玩 | 点侧栏条目 | 面板里出 `about:srcdoc` 的 iframe，日期、五个按钮都在；点「过一天」正文从 67 字增到 388 字 |
| 存档 | 玩一天后刷新页面再进面板 | `localStorage` 里出现 `shen_zhe_day_v1`（314 字节），刷新后还在 |
| 控制台 | 全程收集 pageerror 与 console.error | 零条 |
| 下限版本能不能用 | 拉 `dsh-client-ui-layout` 与 `dsh-client-ui-sidebar` 的 0.2.2-rc.1 包看类型声明 | `main` 仍是 keyed、`sidebar.panellist` 仍是 list，两种槽的口径与 rc.5 一致 |
| 打包内容 | `npm pack --dry-run` | 7 个文件，压缩 56 KB，展开 141 KB |

没验的部分：没有 Android 真机或模拟器，DSH Go 里的网页岛是按文档推断的（本机引擎 + 桥接占用表 + 资源预算满足才会开，开不了会退回「在网页版打开」）。

## 开发

```sh
npm run build   # assets/game.html + src/client.js -> lib/client.js
npm test        # 离线自检：字节一致性、清单、注册的面板、无网络面
npm run check   # 语法检查
```

目录：

```
assets/game.html   游戏本体（自包含网页，构建时内联）
src/client.js      浏览器半侧的源模板，含唯一一处 base64 占位符
lib/index.js       宿主半侧入口
lib/client.js      构建产物，发布用，不要手改
scripts/build.mjs  构建脚本
test/              离线自检
screenshots/       上架用的界面截图
market/            上架申请材料（entry.json 与提交步骤，不随 npm 包发布）
```

改游戏内容的流程：换掉 `assets/game.html` → 改 `test/plugin.test.js` 里记的 sha256 → `npm run build` → `npm test`。

## 许可

插件代码以 MIT 许可发布，见 `LICENSE`。游戏文本与事件数据是二次创作的正文内容，版权归游戏作者，不随 MIT 授权。

本项目不是 DeepSeek 官方发布。
