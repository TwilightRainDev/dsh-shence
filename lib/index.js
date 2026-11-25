/**
 * 宿主半侧：这个插件不在引擎里做任何事。
 *
 * 全部内容都在浏览器半侧（lib/client.js）—— 它往 DSH 网页版的界面里挂一个
 * 面板，面板里用 iframe 装进 assets/game.html 那份自包含的网页游戏。
 * 所以这里只需要一个合法的插件入口，让安装层能把这一行挂进插件树。
 */

export const name = 'dsh-shence'

export function apply() {}
