# 安装说明（预览版准备中）

当前没有已验证的 Release。以下步骤供未来正式批准的预览包使用。

1. 仅从本仓库 Releases 下载 `Codex-Token-Bar-<版本>-preview-universal-macos.zip`。
   GitHub 自动生成的 Source code ZIP 是源码，不是应用。
2. 需要 macOS 13+；Universal 包包含 Apple Silicon 和 Intel 两种架构。
   最低系统版本是构建目标，实际测试过的系统以该 Release 说明为准。
3. 解压，将 `Token Bar.app` 拖进“应用程序”，再打开。无需 Xcode 或编译。
4. 应用只出现在菜单栏，没有普通主窗口。点击菜单栏圆环打开面板。
5. 需要已安装并登录 Codex。当前仅自动查找：
   `/Applications/ChatGPT.app/Contents/Resources/codex`、
   `/Applications/Codex.app/Contents/Resources/codex`、
   `/opt/homebrew/bin/codex`、`/usr/local/bin/codex`。
   其他安装位置可能出现“找不到 Codex App Server”。

## 未公证预览版的安全提示

预览包仅采用 ad-hoc 签名，不能验证开发者身份，没有经过苹果公证。
macOS 可能阻止首次打开；这不是安装成功或安全性保证。
只有你确认来源可信并愿意承担测试风险时，才按 Apple 官方说明，在尝试打开后
进入“系统设置 → 隐私与安全”，核对应用名称后选择“仍要打开”。
组织管理的 Mac 可能禁止例外；此时应等待公证版或联系管理员。
若提示恶意软件、损坏或校验不符，停止安装并反馈，不要强行绕过。
本项目不要求关闭 Gatekeeper、SIP，也不要求执行递归删除 quarantine 的命令。

可选完整性校验：把 ZIP 与同一 Release 的 SHA256SUMS 放在同一目录，在终端运行
`shasum -a 256 -c SHA256SUMS`。哈希只能发现文件不一致，不能证明开发者身份或无恶意代码。

## 权限与故障

- 应用读取 `~/.codex/sessions`，并启动本机 Codex App Server 查询账户额度。
  “本地运行”不表示 Codex App Server 查询账户时绝不会联网。
- 宠物跟随功能使用窗口图像检测，可能受屏幕录制权限和系统版本影响。
  请先验证菜单栏监控，再单独测试浮标；无需为安装而预先授予完全磁盘访问权限。
- 首次无会话、未登录、Codex 更新或内部接口变化均可能导致无数据。
  `--` 或读取失败不等于额度为零。
- 升级：退出旧版，替换“应用程序”中的同名应用。卸载：退出后删除该应用；
  不要删除 Codex 会话目录。卸载应用不会自动清除其偏好设置。

Apple 官方说明：https://support.apple.com/102445
