# 03: 发布 EggplantShot 0.5.1

Status: implemented
Blocked by: None

## 目标与范围

将 Debug / Release 的版本号更新为 0.5.1、构建号更新为 6。按 v0.5.0 的中文分组格式编写发布说明，说明窗口截图的透明圆角、PNG/JPEG 保存行为，以及 README 的权限重置说明和菜单截图。

将上述版本变更、发布说明、工作流，以及本对话已完成的 README 和图片改动一起提交到 main，创建 v0.5.1 标签，通过现有 GitHub Actions 流程构建 DMG 并发布正式 GitHub Release。

## 依赖与实现上下文

- [发布说明](../../../docs/releases/v0.5.1.md)
- [版本设置](../../../EggplantShot.xcodeproj/project.pbxproj)
- [发布工作流](../../../.github/workflows/release.yml)
- [README](../../../README.md) / [English README](../../../README_en.md)
- [窗口透明圆角 Ticket #02](../../window-corner-transparency/issues/02-window-corner-transparency.md)
- [参考 v0.5.0](https://github.com/uniquejava/EggplantShot/releases/tag/v0.5.0)

## 验收标准

- [x] 本地 Release 构建成功，应用元数据为 0.5.1 / 6。
- [x] Release notes 按此前格式编写，工作流使用仓库内的版本说明。
- [x] README、菜单截图和版本变更一起提交到 main，并推送 v0.5.1 标签。
- [x] GitHub Release 为正式发布，DMG 资产上传完成，说明与仓库文件一致。

## 发布结果

正式发布：[EggplantShot v0.5.1](https://github.com/uniquejava/EggplantShot/releases/tag/v0.5.1)。DMG 已上传，线上发布说明与仓库文件一致。
