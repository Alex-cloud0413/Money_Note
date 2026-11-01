# iPhone Duo 适配记录 · 1.4.2（构建 13）

日期：2026-11-01。Xcode 27.2 / iOS 27.2 SDK；最低 iOS 17 不变。数据模型、账目计算及 CloudKit 容器不变。

## 依据与实现

- 按 Apple 导出的 `app-resizability` skill 检查屏幕尺寸、方向、设备类型、场景生命周期及安全区域。源码未发现用于布局的 UIScreen、方向或设备型号判断；保留现有 SwiftUI App / WindowGroup。
- 最终分发包包含启动屏幕、iPad 四个方向，无 `UIRequiresFullScreen`。
- 弹窗的取消、完成、保存和删除操作提供标题与图标，使用系统语义 toolbar placement，支持竖向工具栏。
- 金额页基于当前可用宽高布局；空间足够才用双栏，移除固定 320pt 最小宽。窄矮窗口及辅助字号使用整体滚动，输入、分类和步骤继续由父编辑器持有。
- 保存提示放入各 tab 的安全区域布局，移除固定 68pt 的底栏避让值。

## 已验证

- 原工程 Release 归档和 App Store 分发导出成功；签名校验通过。分发包为 1.4.2（13），正式 CloudKit、正式 APNs，未开启 get-task-allow，包含隐私清单。
- iOS 27.1 Duo 闭合外屏实际运行：466×678pt / 1398×2034px。四个 tab 切换、设置完成按钮退出及记账入口经过原生交互检查；首页、统计、预算截图未见裁切或导航遮挡。
- 三张 Duo 外屏素材为内存示例账目的真实运行截图，保存在 `AppStore/Screenshots/iPhoneDuo/`，已上传并保存至版本草稿；原 iPhone / iPad 素材保留。
- 普通 iPhone 模拟器的导出月份 XCUITest 通过。
- 独立源码复核与 `git diff --check` 通过。测试、构建和截图均未访问用户真实账目。

## 验证限制与发布状态

- 首轮四项 XCUITest 为一项通过、三项失败，失败集中在首次点击未产生预期变化。录像显示统计页能切换；独立原生单次点击设置可打开、关闭，不能将其认定为已证实的全局 hit-test 缺陷。已为自动化补充明确的前台激活、可点击及动作后置条件，复测结果需另行记录。
- 金额完整流程、返回和保存提示正在继续核验；不能将源码审查或入口可打开写作完整流程通过。
- Duo 内屏、半折、任意窗口拖拽及物理 Duo 未验收。黑图、姿态控制数值和普通旋转不能替代这些检查。
- 本文件不代表 App Store 审核通过。构建已上传、处理并关联至 1.4.2 草稿；正式提交应以 App Store Connect 回读为准。

## 官方资料

- [准备适配 iPhone Duo](https://developer.apple.com/iphone-duo/prepare/)
- [布局、竖向工具栏和保留区域](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)
- [截图规范](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)：从 2027 年 4 月开始，使用 iOS 27.1 或更新 SDK 的 App 需要提供 Duo 截图。
