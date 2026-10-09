# 02: 自动吸附窗口截图保留透明圆角

Status: implemented
Blocked by: None

## 目标与范围

自动吸附并点击锁定 macOS 窗口时，将窗口圆角外的桌面背景变成透明，保存为 PNG 后保留透明边缘。依据窗口真实轮廓，不给所有窗口套固定圆角；手动框选继续输出矩形截图。

截图内容仍来自快捷键按下时的冻结画面，包含指针的设置保持有效。透明像素随截图底图进入贴图、复制、标注合成和历史记录，保证再次编辑、保存时不会丢失透明。选区被手动移动、扩大或缩小后恢复普通区域裁剪，避免原窗口轮廓误裁新选区。

## 依赖与实现上下文

- macOS 15+ 的 ScreenCaptureKit；沿用现有屏幕录制权限。
- [冻结与裁剪](../../../EggplantShot/Capture/ScreenCapturer.swift)
- [窗口命中](../../../EggplantShot/Capture/WindowHitTester.swift)
- [选区控制器](../../../EggplantShot/Controllers/SelectionOverlayController.swift)
- [合成器](../../../EggplantShot/Annotation/AnnotationCompositor.swift)
- [图像保存](../../../EggplantShot/Capture/ImageFileSaver.swift)
- [透明轮廓处理](../../../EggplantShot/Capture/WindowCornerTransparency.swift)
- [PNG/JPEG 编码](../../../EggplantShot/Capture/ScreenshotImageEncoder.swift)
- [截图文档架构与实现规则](../../../docs/snip-document-architecture.md#window-corner-transparency)
- [选区规则](../../../docs/selection-refine.md#window-corners)
- [中文使用说明](../../../docs/user-guide_zh.md#截取) / [English user guide](../../../docs/user-guide.md#capture)

## 验收标准

- [x] 自动吸附标准圆角窗口，PNG 的圆角外像素透明，窗口内部内容与冻结画面一致。
- [x] 方角窗口不被额外裁成圆角，手动框选不被处理为窗口轮廓。
- [x] 移动、扩大或缩小窗口选区后不沿用原窗口轮廓。
- [x] 标注、贴图再保存和历史回放保持底图透明；PNG 保留原始像素分辨率。
- [x] 无法获取窗口轮廓时仍能正常截图；JPEG 正常保存为不透明图像。
- [x] 必要的图像处理检查通过，Release 构建成功，启动本次构建供用户验收。

## 实现说明

窗口锁定保留窗口 ID；确认时从 ScreenCaptureKit 的透明、无阴影窗口捕获中提取圆角轮廓，只调整冻结底图的角部 alpha。手动调整选区清除窗口关联。窗口移动、消失、跨显示器裁剪或无法读取轮廓时回退普通矩形截图。PNG 保留 alpha；JPEG 明确铺白底。

验证：`bash scripts/test-window-transparency.sh` 覆盖轮廓、方角、错位、抗锯齿、冻结像素、Retina PNG/JPEG、标注合成和历史磁盘重载；原生 macOS 窗口检查四角 alpha 均为 0；Release 构建通过。最终交互验收由用户进行。
