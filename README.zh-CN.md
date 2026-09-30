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

沿用原项目的部分：你打开的服务商在本机读取额度；用量页汇总本机 Codex 和 Claude Code 的会话日志。

本版本的改动：

- 用量页计入 Cursor。数据来自已登录的 Cursor 账号，并缓存在这台 Mac 上。
- Codex 和 Claude 的设置里可以填写中转站地址和密钥。QuotaBar 向该站点查询账户余额，不切换 CLI 正在使用的账号。
- 菜单栏图标一直都在。只有打开主窗口（设置、分享卡片）时，Dock 里才会出现图标。
- 本版本不包含 Quota Run、iPhone 同步、反馈和软件内更新。

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
