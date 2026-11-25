/**
 * 把网页游戏打进客户端模块。
 *
 * 输入：assets/game.html（自包含单文件网页）、src/client.js（带一处占位符的模板）。
 * 输出：lib/client.js（可直接装载的浏览器半侧，base64 已内联）。
 *
 * 为什么内联而不是走路由：游戏只有一份静态页面，内联之后插件在引擎侧没有任何
 * 网络面、不依赖 webServer 路由，装到哪台主机都对。代价是 lib/client.js 约 100 KiB。
 *
 * 产物开头写死源文件的字节数与 sha256，测试会拿它对回 assets/game.html，
 * 网页改了却忘记重新构建时，测试会直接失败。
 */

import { createHash } from 'node:crypto'
import { readFile, writeFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const PLACEHOLDER = '__GAME_HTML_B64__'
const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const sourcePath = resolve(root, 'assets/game.html')
const templatePath = resolve(root, 'src/client.js')
const targetPath = resolve(root, 'lib/client.js')

const html = await readFile(sourcePath)
const sha256 = createHash('sha256').update(html).digest('hex')
const template = await readFile(templatePath, 'utf8')

const hits = template.split(PLACEHOLDER).length - 1
if (hits !== 1) throw new Error(`src/client.js 应当恰好有一处占位符 ${PLACEHOLDER}，实际 ${hits} 处`)

const banner = [
  '// 由 scripts/build.mjs 生成，不要手改；改 src/client.js 后重新跑 npm run build。',
  `// 内联的游戏网页：${html.byteLength} 字节，sha256 ${sha256}`,
  '',
].join('\n')

await writeFile(targetPath, banner + template.replace(PLACEHOLDER, html.toString('base64')))
console.log(`lib/client.js 已生成：游戏 ${html.byteLength} 字节（sha256 ${sha256}）`)
