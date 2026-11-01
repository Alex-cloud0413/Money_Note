# iPhone Duo 适配记录 · 1.4.2（构建 14）

日期：2026-11-01。Xcode 27.2 / iOS 27.2 SDK；最低 iOS 17 不变。数据模型、账目计算及 CloudKit 容器不变。

## 依据与实现

- 按 Apple 导出的 `app-resizability` skill 检查屏幕尺寸、方向、设备类型、场景生命周期及安全区域。源码未发现用于布局的 UIScreen、方向或设备型号判断；保留现有 SwiftUI App / WindowGroup。
- 最终分发包包含启动屏幕、iPad 四个方向，无 `UIRequiresFullScreen`。
- 弹窗的取消、完成、保存和删除操作提供标题与图标，使用系统语义 toolbar placement，支持竖向工具栏。
- 金额页基于当前可用宽高布局；空间足够才用双栏，移除固定 320pt 最小宽。窄矮窗口及辅助字号使用整体滚动，键盘直接参与内容布局，避免同轴嵌套滚动。宽屏只滚动数字键区域，使「下一步」保持可达；输入、分类和步骤继续由父编辑器持有。
- 保存提示放入各 tab 的安全区域布局，移除固定 68pt 的底栏避让值。

## 已验证

- 原工程 Release 归档和 App Store 分发导出成功；签名校验通过。分发包为 1.4.2（14），正式 CloudKit、正式 APNs，未开启 get-task-allow，包含隐私清单。
- iOS 27.1 Duo 闭合外屏实际运行：466×678pt / 1398×2034px。四个 tab 切换、设置完成按钮退出及记账入口经过原生交互检查；首页、统计、预算截图未见裁切或导航遮挡。
- 三张 Duo 外屏素材为内存示例账目的真实运行截图，保存在 `AppStore/Screenshots/iPhoneDuo/`，已上传并保存至版本草稿；原 iPhone / iPad 素材保留。
- iPhone 17 / iOS 26.5 的四项最终 XCUITest 全部通过：金额输入、横屏后保留输入、分类与详情返回、完成记账和关闭保存提示；四个 tab 及月份一致；导出月份的单步、连续和边缘点击；设置保持打开时浅色、深色与跟随系统的即时变化。测试断言前台和控件可点击，不用失败后重试来取得通过。
- 独立源码复核与 `git diff --check` 通过。测试、构建和截图均未访问用户真实账目。

## 验证限制与发布状态

- 早期自动化首次点击失败通过明确激活前台解决；之后发现并修复了横屏金额页的嵌套滚动缺陷。最终四项回归为 4/4、0失败，前期失败不计作通过。
- 构建14在 Duo 外屏通过原生 Device Hub / AX 单击验证：输入25、无需滚动点击下一步、餐饮与不分子类、详情返回后保留金额和分类、再次进入详情并保存。虚构示例支出从36变为61，新增25的账目可见。已核验已安装测试二进制与最终构建14测试包哈希一致。
- Duo 保存提示出现并自动消失，手动关闭时工具定位过期，未计作手动关闭通过；该操作在普通iPhone四项回归中已验证。
- Duo 的 XCTest 未产出有效用例结果，运行日志包含系统构建版本解析问题；已停止该次无结果运行，不把它记作通过。
- Duo 内屏、半折、任意窗口拖拽及物理 Duo 未验收。黑图、姿态控制数值和普通旋转不能替代这些检查。
- 本文件不代表 App Store 审核通过。最终构建1.4.2（14）已正式提交审核；2026-11-01 23:37（GMT+8）回读为「等待审核」，构建链接为14，草稿篮为0，提交成功回执为1 Item Submitted。保持免费，审核通过后立即自动向所有用户发布；尚未宣称审核通过或公开发布。

## 官方资料

- [准备适配 iPhone Duo](https://developer.apple.com/iphone-duo/prepare/)
- [布局、竖向工具栏和保留区域](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)
- [截图规范](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications)：从 2027 年 4 月开始，使用 iOS 27.1 或更新 SDK 的 App 需要提供 Duo 截图。
