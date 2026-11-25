/**
 * 浏览器半侧：DSH 网页版（以及 DSH Go 里以网页岛打开的那一份）加载的模块。
 *
 * 结构照 DSH 的客户端模块约定来：window.__ModuleLoader__.load 注册一个 id 等于
 * 包名的模块，factory 拿到的 require 只能取平台提供的模块（这里只要 react）。
 *
 * 面板本身很薄：把打包进本文件的游戏网页（base64）解出来，塞进一个同源 iframe。
 * 游戏是自包含的单文件网页，不需要额外路由、不需要联网、不和宿主共享 DOM。
 * iframe 同源，所以游戏自己的 localStorage 存档照常工作。
 *
 * 字符串常量里的占位符由 scripts/build.mjs 用 assets/game.html 的 base64 填上，
 * 不要手改 lib/client.js。
 */

window.__ModuleLoader__.load({
  id: "@twilightrain/dsh-shence",
  factory: (require) => {
    const React = require("react");
    const h = React.createElement;

    const GAME_HTML_B64 = "__GAME_HTML_B64__";

    const PANEL_ID = "dsh-shence";
    const PANEL_LABEL = "沈策又过了一天";

    let decoded = null;

    /** 解一次就够：同一个面板重复渲染不重复解码。 */
    function gameHtml() {
      if (decoded === null) {
        const binary = atob(GAME_HTML_B64);
        const bytes = new Uint8Array(binary.length);
        for (let index = 0; index < binary.length; index += 1) {
          bytes[index] = binary.charCodeAt(index);
        }
        decoded = new TextDecoder("utf-8").decode(bytes);
      }
      return decoded;
    }

    function GamePanel() {
      const srcDoc = React.useMemo(gameHtml, []);
      return h(
        "div",
        {
          "data-dsh-shence": "panel",
          style: {
            position: "relative",
            width: "100%",
            height: "100%",
            minHeight: 0,
            overflow: "hidden",
          },
        },
        h("iframe", {
          title: PANEL_LABEL,
          srcDoc,
          referrerPolicy: "no-referrer",
          allow: "camera 'none'; microphone 'none'; geolocation 'none'",
          style: {
            position: "absolute",
            inset: 0,
            width: "100%",
            height: "100%",
            border: 0,
            display: "block",
            background: "#f6efe2",
          },
        }),
      );
    }

    /** 侧栏行图标：一枚方印里三行字。尺寸与颜色都跟宿主走。 */
    function PanelIcon(props) {
      const size = typeof props.size === "number" ? props.size : 20;
      return h(
        "svg",
        {
          width: size,
          height: size,
          viewBox: "0 0 24 24",
          "aria-hidden": "true",
          focusable: "false",
          style: { display: "block", opacity: props.active ? 1 : 0.82 },
        },
        h("rect", {
          x: 3.6,
          y: 3.6,
          width: 16.8,
          height: 16.8,
          rx: 3.2,
          fill: "none",
          stroke: "currentColor",
          strokeWidth: 1.5,
        }),
        h("path", {
          d: "M7.6 9.2h8.8M7.6 12.4h8.8M10 15.6h3.4",
          fill: "none",
          stroke: "currentColor",
          strokeWidth: 1.5,
          strokeLinecap: "round",
        }),
      );
    }

    return {
      name: PANEL_ID,
      inject: ["slots"],
      apply(ctx) {
        // main 是 keyed 槽：一个 key 就是一页，和侧栏条目的 id 同名才对得上。
        ctx.slots.inject("main", () =>
          ctx.slots.register({ name: "main", key: PANEL_ID }, GamePanel),
        );
        ctx.slots.inject("sidebar.panellist", () =>
          ctx.slots.register(
            { name: "sidebar.panellist", id: PANEL_ID, order: 500, label: () => PANEL_LABEL },
            PanelIcon,
          ),
        );
      },
    };
  },
});
