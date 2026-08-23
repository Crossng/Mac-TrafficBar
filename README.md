# 流量管家（TrafficBar）

这是一个独立的 macOS 菜单栏流量监控项目，显示每个应用的下载、上传、实时速率，以及代理、直连和本地流量分类。

当前项目已经与原始 NetBar 项目拆开：使用自己的 Swift Package 名称、Bundle ID、数据目录和打包配置，不会默认连接原作者的 GitHub 更新地址。

## Features

- 菜单栏常驻，不显示 Dock 图标。
- 按小时、今天、本周和本月查看流量。
- 按应用排行，显示下载、上传、总流量和实时速率。
- 区分代理、直连、本地和未知流量。
- 使用 macOS `nettop` 采样，不需要 Network Extension 或 System Extension。
- 数据按天保存，并自动清理过期记录。

## 本地运行

```bash
swift build
open /path/to/TrafficBar.app
```

如果只是开发调试，也可以直接运行：

```bash
swift run TrafficBar
```

## 打包

打包脚本需要在 Git 仓库中运行。首次使用时：

```bash
git init
git add .
git commit -m "Initial TrafficBar project"
scripts/package-release.sh
```

脚本会生成 `dist/TrafficBar.app` 及压缩包。默认只生成本地版本，不配置任何上游更新地址。

如果以后建立了自己的 GitHub 仓库，再设置以下变量启用 Sparkle 更新：

```bash
TRAFFICBAR_GITHUB_REPOSITORY="你的用户名/TrafficBar" \\
SPARKLE_PUBLIC_ED_KEY="你的公钥" \\
scripts/package-release.sh
```

## 数据位置

流量数据保存在：

`~/Library/Application Support/TrafficBar/`
