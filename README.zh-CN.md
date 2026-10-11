<div align="center">

<img src="Assets/icon.png" alt="QuotaBar" width="112" height="112">

# QuotaBar_vibe

**基于 [QuotaBar](https://github.com/QuotaBar/QuotaBar) 的二次开发，由 bobo 维护。**

本仓库是 [cbyan1003/QuotaBar_vibe](https://github.com/cbyan1003/QuotaBar_vibe)。
它不是上游原项目，不是 quota.bar，也不通过原作者的 Homebrew tap 分发。

[![License](https://img.shields.io/badge/license-MIT-black)](LICENSE)

[English](README.md) · [简体中文](README.zh-CN.md)

</div>

---

## 这是什么

[QuotaBar](https://github.com/QuotaBar/QuotaBar)（版权 GiantAccel, LLC，MIT）是一款 macOS 菜单栏应用，用来查看 AI 编码服务的额度。本仓库从那份源码出发，由 bobo 继续开发。

菜单栏图标一直都在，点开就是额度面板。只有打开主窗口（设置、分享卡片）时，Dock 里才会出现图标。Command-Q 退出应用，Command-W 关闭当前窗口。再次打开时会回到已经在运行的那一份，不会再启动一个。

## 面板上有什么

面板列出你打开的服务商。每张卡片显示套餐、剩余额度和重置时间。Codex 卡片还会列出在 QuotaBar 里保存的每个账号。一行的顺序是：多久重置、还剩多少额度、还剩几次 banked reset。切换账号会改写 Codex CLI 的登录。已经在运行的会话要重启后才会用新账号。

Codex 和 Claude 的设置里可以分别填写中转站地址和密钥。QuotaBar 向该站点查询剩余余额，并显示在卡片上。它不会改 CLI 正在使用的账号。

## 用量

设置里的「用量统计」读取本机会话日志，画成全年热力图。来源是 Codex、Claude Code 和 Cursor。Cursor 来自这台 Mac 上已登录的账号，并缓存在本地。

在热力图上点某一天，下面的模型列表会改成按这一天的用量从高到低排。再点一次同一天，列表回到全年。点某一行模型，热力图只显示这个模型。

## 设置

这个版本的侧边栏是：

- **服务商。** 要跟踪哪些服务、如何登录，以及 Codex 和 Claude 的中转站地址和密钥。保存的 Codex 登录信息只存在这台 Mac 的钥匙串里。
- **用量统计。** 全年热力图，以及热力图背后的合计。
- **项目。** token 用在了哪个仓库、哪个工具。
- **服务状态。** 各服务商公开状态页此刻的读数。
- **外观。** 菜单栏图标长什么样、数的是什么。
- **展示方式。** 除了菜单栏，数字还显示在哪里。菜单栏弹出页使用液态玻璃，底下有一层深色，保证数字能看清。
- **提醒。** 什么时候提醒额度快用完了。
- **通用。** 语言、刷新频率和已记录的历史。
- **关于。** 版本、QuotaBar 原项目致谢，以及这份副本如何处理数据。

本版本不包含 Quota Run、iPhone 同步、反馈和软件内更新。

密钥和已保存的登录信息不在这个仓库里，只留在创建它们的那台 Mac 的钥匙串中。这个构建第一次读取某一项时，macOS 可能会询问一次。同一次启动里，之后的刷新沿用这次的结果。

## 编译

需要 macOS 14 或更高版本。这份副本在 Apple 芯片上编译和使用。需要完整的 Xcode，或者带 macOS 26 SDK 的命令行工具（26.2 可以编译）。更早的命令行工具只到 macOS 15 SDK，编不过 Liquid Glass。

```bash
git clone https://github.com/cbyan1003/QuotaBar_vibe.git
cd QuotaBar_vibe
UNIVERSAL=0 ./Scripts/package_app.sh
open QuotaBar.app
```

`UNIVERSAL=0` 只编当前这台 Mac。去掉它会同时编 Intel 版本。没有 Developer ID 证书时，脚本使用本机临时签名，应用只能在这台 Mac 上运行。

这个仓库没有发布安装包，也没有 Homebrew 配方。克隆后自行编译。

## 许可

MIT。原版权属于 GiantAccel, LLC，见 [LICENSE](LICENSE)。
二次开发不替换这份声明。
