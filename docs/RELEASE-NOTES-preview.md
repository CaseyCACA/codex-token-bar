# v0.1.0-preview.1 — 未公证测试版（草稿，未发布）

这是非公证预览版，仅采用 ad-hoc 签名，未经过苹果公证。
首次打开可能被 macOS 拦截。面向愿意反馈问题的测试用户。

## 本版变化

- 准备 Universal ZIP，包含 Apple Silicon / Intel 应用；使用者无需安装编译工具。
- 打包流程增加测试、架构、签名、压缩往返和 SHA-256 校验。
- 补充安装、系统安全提示与发布检查清单。核心监控逻辑未变。

## 下载与使用

发布批准后才会附带 `Codex-Token-Bar-0.1.0-preview-universal-macos.zip`、
SHA256SUMS、BUILD-INFO.txt。解压后拖入应用程序；查看 [安装说明](INSTALL.md)。
源码 ZIP 不是安装包。需 macOS 13+，并安装和登录 Codex；
兼容性取决于 Codex 内部日志与 App Server 接口。

## 发布前必须填写

- 目标提交 / CI 运行链接：待验证
- 最终 ZIP SHA-256：待构建和验收
- 实测架构、macOS、Codex 版本：待验证
- 首次浏览器下载与 Gatekeeper 行为：待验证
- 菜单栏、额度读取、宠物权限与跟随：待验证
- 许可证：Owner 待选择
- Owner 发布批准：待确认

以上未完成时不得把本草稿作为正式发布声明。
