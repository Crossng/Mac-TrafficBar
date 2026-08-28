<p align="center">
  <img src="Resources/TrafficBarIcon.png" width="132" height="132" alt="流量管家应用图标">
</p>

<h1 align="center">流量管家</h1>

<p align="center">清楚了解 Mac 的实时网速、流量去向和应用使用情况。</p>

<p align="center">
  <a href="https://github.com/Crossng/Mac-TrafficBar/releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/Crossng/Mac-TrafficBar?display_name=tag&amp;style=flat-square&amp;color=4aa3f0"></a>
  <img alt="macOS 13 或更高版本" src="https://img.shields.io/badge/macOS-13%2B-1d1d1f?style=flat-square&amp;logo=apple&amp;logoColor=white">
  <img alt="Apple Silicon" src="https://img.shields.io/badge/芯片-Apple%20Silicon-45cfa5?style=flat-square">
  <a href="https://github.com/Crossng/Mac-TrafficBar/actions/workflows/ci.yml"><img alt="构建状态" src="https://github.com/Crossng/Mac-TrafficBar/actions/workflows/ci.yml/badge.svg"></a>
  <a href="LICENSE"><img alt="MIT License" src="https://img.shields.io/github/license/Crossng/Mac-TrafficBar?style=flat-square"></a>
</p>

<p align="center">
  <strong><a href="https://github.com/Crossng/Mac-TrafficBar/releases/latest/download/TrafficBar-macos-arm64.dmg">下载最新版本</a></strong>
  ·
  <a href="https://github.com/Crossng/Mac-TrafficBar/releases">查看历史版本</a>
</p>

---

流量管家是一款原生 macOS 菜单栏工具。它将系统网络数据整理为直观的实时速度、时间段汇总和应用流量排行，无需打开复杂的网络工具。

## 主要功能

| 功能 | 说明 |
| --- | --- |
| 实时网速 | 在菜单栏面板中查看当前下载和上传速度 |
| 时间统计 | 按小时、今天、本周和本月查看累计流量 |
| 路径分类 | 区分代理、直连和本地流量 |
| 应用排行 | 查看各应用的下载、上传和流量构成 |
| 重复计费保护 | 对照物理网卡总量，避免代理核心与下载应用重复累计 |
| 本地存储 | 流量记录只保存在当前 Mac，不上传服务器 |
| 自动更新 | 可在应用内检查并安装由本项目发布的新版本 |

## 安装

1. 下载最新的 [`TrafficBar-macos-arm64.dmg`](https://github.com/Crossng/Mac-TrafficBar/releases/latest/download/TrafficBar-macos-arm64.dmg)。
2. 打开安装镜像，将“流量管家”拖入“应用程序”。
3. 启动应用，点击菜单栏中的上下箭头图标即可查看流量。

如果 macOS 阻止首次打开，请前往“系统设置 → 隐私与安全性”，在安全性区域选择“仍要打开”。

目前需要 macOS 13 或更高版本，发布包适用于 Apple 芯片 Mac。

## 使用

- 使用时间筛选器切换小时、今天、本周和本月数据。
- 使用类型筛选器查看全部、代理、直连或本地流量。
- 点击底部刷新按钮立即重新采样。
- 点击文件夹按钮打开本地数据目录。
- 点击下载按钮手动检查新版本。

## 数据与隐私

流量管家直接读取 macOS 提供的本机网络统计，不会上传流量记录，也不会安装系统扩展。应用会用物理网卡增量校准总量，无法准确归属到具体进程的协议开销显示为“其他网络流量”。由于统计口径不同，结果仍可能与运营商账单或路由器数据存在少量差异。

## 许可

项目使用 [MIT License](LICENSE)。第三方组件及许可说明见 [NOTICE.md](NOTICE.md) 和 [THIRD-PARTY-NOTICES](THIRD-PARTY-NOTICES)。
