# 轻账记 · MoneyNote

用简约的纸质界面，分别记好生活和事业。原生 iPhone / iPad 记账应用，使用 SwiftUI、SwiftData 和 CloudKit。

当前开发版本：**1.1（构建 4）**。本仓库保存源码和开发历史，App Store 发布状态独立于代码提交。

## 本次更新

构建 4 将墨绿色主色和图标调整为纯黑；暖白纸底与原有纸纹保留。深色模式使用反转的黑白灰，以保证按钮和文字可读。

- 记账页顶部「完成」始终可见；金额键盘的「下一步」收起键盘，继续选择分类、账户、账本、日期、备注和分期。保存后显示这笔账所属账本。
- 生活账本、事业账本及自定义账本；首页明细、统计、预算、关注分类和订阅按当前账本展示。账户独立记录资金来源，可以跨账本使用。
- 统计支持进入一级分类查看子类金额、占本类比例、占本月比例及趋势；未指定子类的账目计入「未分子类」。
- 暖白纸纹、墨色文字、纯黑主色与中性灰、统一线性分类图标及新 App 图标。适配深色外观与增强对比度。
- CSV 导出增加账本列，保留全部账目。
- 分期按整数分分配，避免小额分期出现零数、负数或金额总和不一致。

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

覆盖旧数据与账户关系保留、账本/月度/收支筛选、子分类占比、订阅账本继承与幂等性、分期边界以及进程重启后的保存结果。

旧账目的新增字段 `bookID` 为可空值；空值统一解释为生活账本，兼容尚未升级设备通过 CloudKit 导入的历史记录。预算和订阅采用相同规则，原有账户关系不变。

本地数据迁移及一次真机旧数据升级核验已通过；CloudKit 生产验证仍待完成。发布前需验证多设备 iCloud 同步，并部署新增字段和账本模型对应的生产 Schema。详见 [验证记录](Docs/verification-1.1.md)。

## 历史

- `a022417`：完整保留本地 1.0（构建 2）源码。
- `77c3f6a`：与原 GitHub 仓库历史合并，保留原隐私政策网页 `index.html`。
- 1.1：账本维度、记账流程、子类统计及纸质界面改版。

[设计素材](Docs/design-assets.md) · [隐私政策](index.html)
