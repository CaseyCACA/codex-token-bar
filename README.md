# Codex Token Bar

macOS menu bar monitor for Codex quota and token usage. Local-first, no API key.

一个完全本地运行的原生 macOS 菜单栏应用：在菜单栏显示 Codex 主额度剩余比例，并在 Codex 桌面宠物旁显示一个会跟随移动的余额浮标。

这是一个独立的 macOS 应用项目，而不是 Codex Skill。它需要长期运行、创建透明浮层窗口、读取本机 Codex 会话日志，并调用 Codex App Server；这些都超出了 Skill 作为“给模型的工作说明”的合适边界。

## 功能

- 菜单栏显示 Codex 主额度的环形进度与剩余百分比。
- 展开面板显示重置时间、本任务 Token、最近一次调用、缓存复用与上下文占用。
- 宠物余额浮标默认出现在 Codex 宠物上方，并随宠物移动；可拖到合适位置，偏移量会被记住。
- 每 3 秒读取最新本地任务信息；每 15 秒刷新账户额度。
- 多额度池同时存在时，固定优先使用 `limit_id = codex` 的主额度，避免模型专属额度误覆盖主进度。

## Screenshots

### macOS menu bar monitor

<img width="1602" height="268" alt="Codex Token Bar in the macOS menu bar" src="https://github.com/user-attachments/assets/aeb7d685-f8fd-4c6b-adf0-d00cf13cd811" />

### Expanded usage dashboard

<img width="868" height="892" alt="Codex Token Bar expanded token usage dashboard" src="https://github.com/user-attachments/assets/d90d833d-4ed7-4814-a8d1-489e7d20d052" />

### Floating pet quota badge

<img width="342" height="464" alt="Codex desktop pet with floating token quota badge" src="https://github.com/user-attachments/assets/2c2a278c-0fd7-45b2-adce-926f1a7614d7" />

余额浮标会随着宠物拖动而跟随移动。

## 系统要求

- macOS 13 或更高版本
- 仅从源码构建时需要 Xcode Command Line Tools（提供 `xcrun clang`）
- 已安装并登录 Codex 桌面应用或 Codex CLI

应用仅读取本机 `~/.codex/sessions` 中的会话日志，并通过本机的 Codex App Server 查询额度；不需要 API Key，也不会发送或上传日志内容。

## 下载与安装

当前尚无已验证的可下载 Release。打包流程正在准备中，请勿把仓库的
“Source code (zip)”当成安装包，也不要把 CI 通过理解为已完成苹果公证。

未来测试版将提供包含 `Token Bar.app` 的 Universal ZIP（Apple Silicon + Intel），
解压后拖入“应用程序”即可安装，无需自行编译。未公证测试版首次打开可能被
Gatekeeper 拦截，详情见 [安装说明](docs/INSTALL.md)。

## 构建与运行

```bash
make test
make app
open "dist/Token Bar.app"
```

或者直接执行：

```bash
make run
```

构建结果位于 `dist/Token Bar.app`。首次运行后，点击菜单栏圆环可打开面板；面板底部的爪印按钮可显示或隐藏宠物浮标。

## 数据含义与限制

- “处理 Token”包含被重复带入的缓存上下文，不能等同于账户额度扣减；额度以 Codex 返回的 `usedPercent` 为准。
- 会话日志与 App Server 协议属于 Codex 的内部接口；若版本升级导致字段变动，应用会显示读取失败，而不会把缺失数据误显示为 `0%`。
- 宠物浮标与菜单栏使用同一份 `remainingPercent`，两处会同步。

## 项目结构

```text
Sources/TokenBar/     原生 macOS UI、会话日志和额度读取器
Tests/                JSONL 日志与额度选择测试
Packaging/            macOS 应用包的 Info.plist
Makefile              构建、测试、签名和运行命令
```

## 发布说明

`make app` 生成当前架构的 ad-hoc 签名应用。`make package-preview` 在 macOS 上
运行测试，生成并校验 Universal ZIP 和 SHA-256；它不会上传或发布安装包。
这不是 Developer ID 签名，也没有苹果公证。面向普通用户的正式分发建议完成
Developer ID 签名、公证和票据装订；未公证预览版须明确标记并完成真人试装。

维护者请参阅 [发布检查清单](docs/RELEASING.md) 和 [预览版说明草稿](docs/RELEASE-NOTES-preview.md)。

## 许可证

本项目作者拥有的代码和文档采用 [MIT License](LICENSE)：
允许使用、修改、再分发和商用；分发软件或其实质部分时，须保留版权声明及完整许可声明。
软件按“原样”提供，不附带担保。

版权署名为 `Copyright (c) 2026 CaseyCACA`。第三方软件、商标以及截图中可能出现的
第三方界面或素材不因此被重新授权；具体边界见 [第三方说明](THIRD_PARTY_NOTICES.md)。
本项目是独立工具，不代表 OpenAI、Apple 或 GitHub 官方产品。
