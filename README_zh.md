# EggplantShot

原生 **macOS 15+** 菜单栏截图工具 — Snipaste 风格：框选、标注、钉图、贴图。

[English](./README.md)

![EggplantShot 精修工具栏与标注示意](./docs/screenshot.png)

## 功能

- **截取** — 冻结画面，单击窗口或拖拽框选，精修与标注后钉住 / 复制 / 保存
- **截取并复制** — 选区锁定后立刻复制到剪贴板（无工具栏）
- **标注** — 形状、箭头、铅笔、马克笔、马赛克、文字、步骤序号、放大镜、橡皮；支持撤销 / 重做
- **OCR** — 从选区识别**二维码或文字** → 写入剪贴板
- **粘贴（贴图）** — 把剪贴板变成浮动钉图（图片、色卡或文字便签）
- **钉图** — 置顶、拖动、滚轮缩放、一键隐藏 / 显示全部

## 快捷键（默认）

| 操作 | 快捷键 |
|------|--------|
| 截取 | `F1` |
| 截取并复制 | `⌘F1` |
| 粘贴（剪贴板 → 钉图） | `F3` |
| 隐藏 / 显示全部钉图 | `⇧F3` |

可在偏好设置里改快捷键。菜单栏 → **Disable hotkeys** 可全局暂停。

## 权限

| 权限 | 用途 |
|------|------|
| **辅助功能（Accessibility）** | 全局快捷键 |
| **屏幕录制（Screen Recording）** | 截取画面 |

## 编译运行

需要 macOS 15+ 与 Xcode 16+。

```bash
killall EggplantShot 2>/dev/null
xcodebuild -project EggplantShot.xcodeproj -scheme EggplantShot \
  -configuration Debug -derivedDataPath build build
open build/Build/Products/Debug/EggplantShot.app
```

或：`open EggplantShot.xcodeproj`

务必使用 `-derivedDataPath build`，并先结束已在运行的实例，否则可能打开旧二进制。

## 文档

- [使用指南](./docs/user-guide_zh.md)
- [AGENTS.md](./AGENTS.md) — 架构与贡献 / Agent 说明（英文）
