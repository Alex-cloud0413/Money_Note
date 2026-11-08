# 轻账记 · MoneyNote

用简约的纸质界面，分别记好生活和事业。原生 iPhone / iPad 记账应用，使用 SwiftUI、SwiftData 和 CloudKit。

当前开发版本：**1.5（构建 17）**。本仓库保存源码和开发历史，App Store 发布状态独立于代码提交。

## 本次更新

- 分期和订阅可选按月或按天平摊。按天使用周期内实际天数，分摊合计与原金额一致。
- 记账与订阅支持 15 种币种。外币账目保留原币、采用的汇率和折合人民币金额。
- CSV 支持自选起止日期，保留账本和收支筛选。
- 明细、账本、统计和预算删减说明文案和装饰线。「今日支出」可左滑删除并撤销，展开收起时只动画显示箭头转动。

## 1.4 的主要功能

- 明细页移除冗余计划账目提示、分隔线和当月结余，突出支出、收入与流水。
- 新增「今日支出」，当天账目可以直接查看和编辑。
- 「关注分类」改为居中入口与独立弹窗，减少首页展开后的视觉拥挤。
- CSV 可按月份、账本以及支出或收入筛选后导出。
- 明细、统计与预算共用相同的账本和月份顶部栏，位置、字号、间距一致，滚动时固定在顶部。
- 记账三步流程、分类选择、底部返回和右滑返回进一步优化触感与层级。
- 全局改为纯白微皱纸张底、纯黑主色和更少的卡片容器。
- App 图标使用纯白底，记账本图形约占画布 61%，并同步适配浅色、深色与系统着色外观。

## 开发

使用 Xcode 打开 `MoneyNote.xcodeproj`，运行 `MoneyNote` scheme。最低 iOS 17，当前使用 Xcode 27.2。1.4.2 构建 12 已在 iPhone 17 上完成覆盖升级、旧数据保留及正式 CloudKit 同步核验；构建 14 的 Duo 验证范围见 [适配记录](Docs/verification-iphone-duo.md)。

```sh
xcodebuild -project MoneyNote.xcodeproj -scheme MoneyNote \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/MoneyNoteBuild CODE_SIGNING_ALLOWED=NO build
```

真机运行需要开发者自己的签名配置和相应的 CloudKit 容器权限。仓库不包含签名私钥、描述文件、真实账目或本机 Xcode 用户状态。

`Release` 使用 `MoneyNote.Release.entitlements`，将 CloudKit 环境明确设为 `Production`；直接安装真机时也应核验最终签名的环境，避免与商店版使用不同的数据环境。App Store 导出由 Xcode 按分发签名重签名。

Debug 运行参数 `--preview-data` 启用隔离的内存示例数据，不打开用户的持久化数据库或连接 CloudKit。普通启动仍使用原数据库。

安装 XcodeGen 后，可运行 `./Tests/run-ui-checks.sh <模拟器 UUID>`。UI 回归使用独立应用标识和内存示例账目，覆盖金额流程、返回、旋转、保存提示、四个标签页、日期范围导出、「今日支出」左滑和即时外观切换。结果保存在临时目录，不进入仓库。

## 数据兼容与验证

旧版模型保存在 `Tests/LegacyModels`，来源于改版前源码提交 `a022417`。执行以下命令会创建独立临时数据库，先用原模型写入，再用新模型迁移、验证并重开。

```sh
./Tests/run-checks.sh
```

覆盖旧数据与关系、账本/月度筛选、子类占比、分期边界、分类改名与延迟导入、归档、删除恢复、独立月度预算、订阅精度与幂等、CSV 和进程重启持久化。

旧账目的 `bookID` 为空时仍解释为生活账本。旧账户模型仅作为不可见的迁移兼容结构保留，防止已有本地数据库或 CloudKit 记录因直接删字段而无法打开；新版本不再创建、展示或写入账户信息。旧版固定预算在升级时只归入升级当月，之后每个月独立设置。

本地数据迁移及真机旧数据升级核验持续覆盖；1.4.2 已核验正式 CloudKit 导入与导出成功。详见 [1.4.2 验证记录](Docs/verification-1.4.2.md)、[1.4 历史记录](Docs/verification-1.4.md)、[1.3 历史记录](Docs/verification-1.3.md)、[1.2 历史记录](Docs/verification-1.2.md)及 [1.1 历史记录](Docs/verification-1.1.md)。

## 历史

- `a022417`：完整保留本地 1.0（构建 2）源码。
- `77c3f6a`：与原 GitHub 仓库历史合并，保留原隐私政策网页 `index.html`。
- 1.5：按天平摊、多币种、日期范围导出和四页视觉精简。
- 1.4.2：修复导出月份按钮、设置页实时外观切换，并明确 Release 的正式 iCloud 环境。
- 1.4.1：更新 App Store 截图。
- 1.4：明细页与 CSV 导出增强、纯白纸纹视觉和新版图标。
- 1.3：移除账户产品概念、三步弹窗记账、每月独立预算。
- 1.2：设计审核 D01–D18 修复、数据保护与跨尺寸适配。
- 1.1：账本维度、记账流程、子类统计及纸质界面改版。

[设计素材](Docs/design-assets.md) · [隐私政策](index.html)
