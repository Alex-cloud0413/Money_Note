# 轻账记 · MoneyNote

用简约的纸质界面，分别记好生活和事业。原生 iPhone / iPad 记账应用，使用 SwiftUI、SwiftData 和 CloudKit。

当前开发版本：**1.2（构建 5）**。本仓库保存源码和开发历史，App Store 发布状态独立于代码提交。

## 本次更新

构建 5 根据完整设计审核更新交互、数据保护与适配，延续纯黑、暖白和纸质纹理。

- 记账：金额→常用/全部分类→账户→账本→日期、备注与分期；完成持续可用，支持未完成草稿恢复与保存后定位。
- 账本与月份贯通各页；统计支持大类→子类→具体账目，比例与趋势均提供明确文字。
- 普通账目可撤销删除并从最近删除恢复；账户、分类支持归档；订阅停止与永久删除分开。
- 分类改名同步维护历史引用，图标选择实际生效；历史未知子类可保留。
- 当前账面余额排除未来计划；预算默认仅修改所选月份，重复规则单独管理。
- 大字号自适应、iPad 双栏、手机横屏记账；统一纸面组件与三种外观的记账图标。
- 显式准备 CSV、同步事件与保存反馈、存储打开失败保留原文件并提供重试。

## 开发

使用 Xcode 打开 `MoneyNote.xcodeproj`，运行 `MoneyNote` scheme。最低 iOS 17，当前验证环境为 Xcode 26.6 / iOS 26.5 Simulator；构建 4 已在 iPhone 17 / iOS 27.0 测试版上完成覆盖升级、启动及旧数据保留核验。

```sh
xcodebuild -project MoneyNote.xcodeproj -scheme MoneyNote \
  -configuration Debug -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/MoneyNoteBuild CODE_SIGNING_ALLOWED=NO build
```

真机运行需要开发者自己的签名配置和相应的 CloudKit 容器权限。仓库不包含签名私钥、描述文件、真实账目或本机 Xcode 用户状态。

Debug 运行参数 `--preview-data` 启用隔离的内存示例数据，不打开用户的持久化数据库或连接 CloudKit。普通启动仍使用原数据库。

## 数据兼容与验证

旧版模型保存在 `Tests/LegacyModels`，来源于改版前源码提交 `a022417`。执行以下命令会创建独立临时数据库，先用原模型写入，再用新模型迁移、验证并重开。

```sh
./Tests/run-checks.sh
```

覆盖旧数据与关系、账本/月度筛选、子类占比、分期边界、分类改名与延迟导入、归档、删除恢复、未来余额、按月预算、订阅精度与幂等、CSV 和进程重启持久化。

旧账目的新增字段 `bookID` 为可空值；空值统一解释为生活账本，兼容尚未升级设备通过 CloudKit 导入的历史记录。预算和订阅采用相同规则，原有账户关系不变。

本地数据迁移及一次真机旧数据升级核验已通过；CloudKit 生产验证仍待完成。发布前需验证多设备 iCloud 同步，并部署新增字段和账本模型对应的生产 Schema。详见 [1.2 验证记录](Docs/verification-1.2.md)及 [1.1 历史记录](Docs/verification-1.1.md)。

## 历史

- `a022417`：完整保留本地 1.0（构建 2）源码。
- `77c3f6a`：与原 GitHub 仓库历史合并，保留原隐私政策网页 `index.html`。
- 1.2：设计审核 D01–D18 修复、数据保护与跨尺寸适配。
- 1.1：账本维度、记账流程、子类统计及纸质界面改版。

[设计素材](Docs/design-assets.md) · [隐私政策](index.html)
