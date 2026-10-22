# 最小发布方案与检查清单

## 当前准备方案（发布路径待 Owner 确认）

仅准备 `v0.1.0-preview.1` 非公证预览版，bundle 版本保持现有 0.1.0 / 1。
只生成 Universal `.app` ZIP、SHA256SUMS、BUILD-INFO；不增加 DMG 或安装器。
不自动打 tag、不创建 Release、不合并 PR。
Owner 已批准在公开 GitHub Actions 保存测试候选；这不代表批准正式 Release。
CI 在临时 macOS runner 上验证。仅本仓库 release/prepare-preview 分支的 push，
在两个架构校验都通过后，另由 macos-15 重建并验证一个 canonical Universal 候选。
只保存候选 ZIP、BUILD-INFO 和 SHA256SUMS，保留 7 天；任意 PR 或其他分支不会上传。
候选明确标记未公证、真实 Mac 验收待完成；正式发布仍须真人试装和 Owner 授权。
准备预览包的脚本不代表 Owner 已选择非公证分发，也不代表已获发布批准。

现有应用无第三方链接库配置，使用 Cocoa/CoreGraphics/QuartzCore/Foundation。
源码发现 App Server clientInfo 自报 0.2.0，而 bundle 为 0.1.0；这是已有差异，
不能把它当作已发布的 0.2.0。本次不改协议行为。

## 两条路径

| 路径 | 条件 | 安装体验 | 限制 |
| --- | --- | --- | --- |
| ad-hoc 非公证预览 | macOS + Command Line Tools；无需开发者证书 | 下载、解压、拖入应用程序；首次可能要手动允许 | 无苹果开发者身份验证或公证；受管设备可能禁止；仅适合愿意测试的用户 |
| Developer ID + 公证 | 开发者会员、Developer ID Application 私钥/证书、公证凭据、macOS 工具链 | 下载、解压、拖入应用程序；系统仍可能显示下载确认 | 必须验证硬化运行时、公证 Accepted、staple 与 Gatekeeper；公证不是完整安全审计 |

公开仓库使用标准 GitHub-hosted macOS runners 可免构建分钟费用，仍受 GitHub 使用政策约束。
Apple Developer Program 通常为 99 USD/年或当地货币价格；已有会员不必重复购买。
预览路线可以先验证需求，但正式面向普通用户推广建议走公证路线。

## 自动检查

在干净且已提交的 checkout 执行 `make package-preview`。
脚本会删除忽略的 `.build/` 和 `dist/`，运行现有 parser 测试、编译 Universal、
校验 Info.plist / 两种架构 / ad-hoc 签名 / 系统动态库依赖，压缩后解压再次验签，
生成并核对 SHA-256。CI 分别在 arm64、Intel 上运行原生 parser 测试。

它不验证登录账户、UI、屏幕权限、最低系统版本或浏览器下载隔离行为。
当前 Linux 执行环境无法完成这些 macOS 检查。不得把未执行的测试标为通过。

## 人工发布门槛（全部完成后再请求发布授权）

- [ ] 最终目标提交的 push 与 PR 两轮 CI 均成功（每轮两个架构），保存提交 SHA 和运行链接。
- [ ] Owner 明确选择非公证预览或签名公证路线；按所选路线完成对应安全验证。
- [x] Owner 已选择 MIT，根目录 LICENSE 已添加，版权署名为 CaseyCACA。
- [ ] 发布前确认源码及展示素材的权利；第三方内容不得因本项目 MIT 声明而被重新授权。
- [ ] 确认版本、Release tag、目标提交一致；从干净提交构建最终包。
- [ ] 在无编译工具的 Mac 测试解压、拖入应用程序、首次打开、退出、重开和替换升级。
- [ ] 使用浏览器下载隔离的实际 ZIP 测试 Gatekeeper 提示，不以本机直接启动替代。
- [ ] 实测 Apple Silicon 和 Intel；若某架构未实测，发布说明明确限制或缩小支持范围。
- [ ] 记录实际测试的 macOS 版本；未测 macOS 13 不可声称已经覆盖最低系统。
- [ ] 按 [首次测试与反馈说明](INSTALL.md#首次测试先确认能用再确认浮标) 记录实际结果。
- [ ] 测试 Codex 已登录/未登录/无日志；主额度、重置时间和读数与 Codex 对照。
- [ ] 宠物浮标权限拒绝/允许、移动和隐藏测试；核查系统 API 兼容性。
- [ ] 最终 ZIP 解压验签及哈希通过，记录最终 SHA256，之后不得修改包。
- [ ] 把 RELEASE-NOTES 草稿中的待验证项替换为实际结果。
- [ ] Owner 明确批准公开发布该版本、提交与哈希。

批准后由维护者手动创建 GitHub **Pre-release**，附 ZIP、SHA256SUMS、BUILD-INFO，
标题和首段注明“未公证测试版”。不要设为稳定最新版，不要关闭 #1，直到交付真正完成。
Actions 的公开测试 artifact 仅供验证，不能把其存在或自动检查通过当成安装验收。
必须记录精确 run、artifact ID、来源提交及内层应用 ZIP SHA-256；不同 runner 的哈希不可混用。

## 后续正式签名公证

由 Owner 确认会员及签名身份，私钥只保存在本机钥匙串或受保护的 CI secret 中，
不要提交仓库或粘贴到 Issue/聊天。先在可信 Mac 完成一次手动链路：

1. 从批准的干净提交构建；使用 Developer ID Application 签名，启用 hardened runtime 和安全时间戳。
2. 使用 `xcrun notarytool submit ... --keychain-profile ... --wait` 提交 ZIP；查看结果和日志，必须为 Accepted。
3. 对 `.app` 执行 `xcrun stapler staple` 和 `xcrun stapler validate`。
4. 运行 `codesign --verify --deep --strict` 及 `spctl --assess --type execute --verbose=4`。
5. 重新用 ditto 压缩已装订的应用，重新计算哈希，再做浏览器下载试装。

本次没有实现或执行签名公证自动化，避免凭据条件未确认时误发布。

## Owner 决策与仓库简介

- 是否先发布非公证预览版，还是等公证后再提供下载？建议先小范围预览。
- 是否已有 Apple Developer Program、Developer ID Application 和可测试的 Mac？
- 许可证已由 Owner 选择 MIT；保留版权和许可声明。第三方素材的权利核验仍独立进行。
- 建议 About 简介：`macOS 菜单栏显示 Codex 剩余额度与 Token 用量，本地运行，无需 API Key。`
  当前连接器没有仓库描述更新工具；维护者可在仓库 About 齿轮中替换。

参考：
- https://docs.github.com/actions/using-jobs/choosing-the-runner-for-a-job
- https://developer.apple.com/help/account/membership/program-enrollment
- https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
- https://support.apple.com/102445
