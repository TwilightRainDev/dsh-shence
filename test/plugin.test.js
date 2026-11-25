/**
 * 离线自检：不启主机、不联网，只证明三件事。
 *
 * 1. 打包进 lib/client.js 的网页与 assets/game.html 是同一份字节。
 * 2. 浏览器半侧确实会注册两处界面：main 面板与侧栏条目，id 对得上。
 * 3. 这份网页没有对外网络面（市场扫描会按源码特征打风险标记，这里先自己钉住）。
 *
 * 真正在 DSH 网页版里能不能画出游戏，属于另一层证据，见 README 的验证记录。
 */

import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { readFile } from 'node:fs/promises'
import { dirname, resolve } from 'node:path'
import { test } from 'node:test'
import { fileURLToPath } from 'node:url'

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const read = (path) => readFile(resolve(root, path))

const html = await read('assets/game.html')
const bundle = await read('lib/client.js')
const bundleText = bundle.toString('utf8')
const manifest = JSON.parse(await read('package.json'))

/** 取出内联的 base64，解回原始字节。 */
function embeddedHtml() {
  const match = bundleText.match(/const GAME_HTML_B64 = "([A-Za-z0-9+/=]+)";/)
  assert.ok(match, 'lib/client.js 里找不到内联的游戏网页')
  return Buffer.from(match[1], 'base64')
}

test('内联的网页与 assets/game.html 逐字节相同', () => {
  const sha256 = createHash('sha256').update(html).digest('hex')
  assert.equal(sha256, '09426518aa07d644fa536c71e6bd60d29ccd00f6bbeb358efbc8a29b0ae7e72f')
  assert.ok(
    bundleText.includes(`内联的游戏网页：${html.byteLength} 字节，sha256 ${sha256}`),
    'lib/client.js 的头部记录的字节数或 sha256 与 assets/game.html 不符，先跑 npm run build',
  )
  assert.deepEqual(embeddedHtml(), html)
  assert.ok(!bundleText.includes('__GAME_HTML_B64__'), '占位符没被替换，构建产物是旧的')
})

test('清单能被 DSH 当插件装载', async () => {
  assert.equal(manifest.name, '@twilightrain/dsh-shence')
  assert.equal(manifest.license, 'MIT')
  assert.equal(manifest.type, 'module')
  assert.ok(manifest.engines?.dsh, 'engines.dsh 必须写明支持的 DSH 版本范围')
  assert.equal(manifest.dsh?.bundle?.patch, './cordis.patch.yml')
  assert.equal(manifest.dsh?.client?.platform, 'web')
  assert.equal(manifest.exports?.['./client'], './lib/client.js')
  for (const file of ['lib', 'cordis.patch.yml', 'README.md', 'LICENSE']) {
    assert.ok(manifest.files.includes(file), `files 里应当发布 ${file}`)
  }

  const patch = (await read('cordis.patch.yml')).toString('utf8')
  assert.ok(patch.includes(`name: "${manifest.name}"`), 'cordis.patch.yml 的 name 与包名不一致')

  const host = await read('lib/index.js')
  assert.ok(host.byteLength > 0, '宿主半侧入口不能是空文件')
})

test('浏览器半侧注册了 main 面板与同名侧栏条目', async () => {
  const registrations = []
  const injections = []
  const loaded = []
  const fakeReact = {
    createElement: (type, props, ...children) => ({ type, props: props ?? {}, children }),
    useMemo: (factory) => factory(),
  }

  globalThis.window = {
    __ModuleLoader__: {
      load: (module) => {
        loaded.push(module)
        const exported = module.factory((id) => {
          assert.equal(id, 'react', '浏览器半侧只应当取用 react')
          return fakeReact
        })
        registrations.push(exported)
      },
    },
  }
  globalThis.atob = (value) => Buffer.from(value, 'base64').toString('latin1')

  await import(resolve(root, 'lib/client.js'))

  assert.equal(loaded.length, 1)
  assert.equal(loaded[0].id, manifest.name, '模块 id 必须等于包名')
  const plugin = registrations[0]
  assert.equal(plugin.name, 'dsh-shence')
  assert.deepEqual(plugin.inject, ['slots'])

  plugin.apply({
    slots: {
      inject: (name, register) => {
        injections.push(name)
        register()
      },
      register: (options, component) => {
        registrations.push({ options, component })
      },
    },
  })

  assert.deepEqual(injections, ['main', 'sidebar.panellist'])
  const panel = registrations.find((entry) => entry?.options?.name === 'main')
  const row = registrations.find((entry) => entry?.options?.name === 'sidebar.panellist')
  assert.equal(panel.options.key, 'dsh-shence')
  assert.equal(row.options.id, 'dsh-shence', '侧栏条目的 id 必须与 main 的 key 相同')
  assert.equal(row.options.label(), '沈策又过了一天')

  const tree = panel.component({})
  assert.equal(tree.props['data-dsh-shence'], 'panel')
  const frame = tree.children[0]
  assert.equal(frame.type, 'iframe')
  assert.equal(frame.props.srcDoc, html.toString('utf8'))

  const icon = row.component({ size: 20, active: true })
  assert.equal(icon.type, 'svg')
  assert.equal(icon.props.width, 20)
})

test('游戏网页没有任何对外网络面', () => {
  const text = html.toString('utf8')
  for (const pattern of [
    /https?:\/\//i,
    /fetch\s*\(/i,
    /XMLHttpRequest/,
    /WebSocket/,
    /sendBeacon/,
    /importScripts/,
    /<link\b[^>]*\bhref=/i,
    /@import/i,
  ]) {
    assert.ok(!pattern.test(text), `游戏网页里出现了不该有的外部引用：${pattern}`)
  }
  assert.ok(text.includes("const KEY='shen_zhe_day_v1'"), '存档键没变过：本插件的存档只落在游戏自己的键上')
})
