# 侧伴 · Ceban

一个用 SwiftUI 和 AppKit 构建的原生 macOS 侧边工作台，把笔记、待办、番茄钟和录音放在屏幕边缘，方便随时记录、专注和整理。

由 TenLift.ai 开发。支持简体中文和 English，支持跟随系统、浅色与深色外观。

## 下载与官网

[下载 macOS 版（v1.0.1 Preview · DMG）](https://liftbot.tenlift.ai/downloads/LiftBot-1.0.1-preview-liftbot-id-universal.dmg) · [访问 LiftBot 官网](https://liftbot.tenlift.ai)

支持 macOS 14 及以上，兼容 Apple Silicon 和 Intel Mac。打开 DMG 后，将「侧伴」拖入 Applications（应用程序）文件夹。

当前下载为未经 Apple 公证的预览版。安装说明与后续版本请查看 [官网的下载区域](https://liftbot.tenlift.ai/#download)。

## 功能

- **边缘侧栏**：拖到屏幕左右边缘自动吸附和收起，点击展开；支持窗口置顶及悬浮快捷控制。
- **多页笔记**：彩色标签页、Markdown 编辑与预览，可拖入文件作为附件。
- **待办与提醒**：添加、编辑、完成待办，通过 macOS 本地通知接收提醒。
- **番茄钟**：自定义专注和休息时长，支持开始、暂停、重置与到时通知。
- **录音与转写**：录音、回放和本地语音识别，支持普通话与英语；音频与转写保存在对应笔记中。
- **Obsidian 导出**：手动导出 Markdown、待办与录音附件，可配置仓库及附件目录。
- **全局快捷键**：自定义显示侧栏、开始 / 暂停计时、开始 / 停止录音的组合键。
- **休息日日历**：内置 2026 年中国大陆节假日及调休数据，支持导入年度 JSON。

## 从源码运行

需要 macOS 14 或更高版本，以及包含项目所需 SDK 的 Xcode。语音转写使用了 macOS 26 的新 API，并保留旧系统的兼容路径；请使用包含这些 API 的 SDK 编译。

1. 下载或克隆整个仓库，保留目录结构。
2. 用 Xcode 打开 `侧伴/侧伴.xcodeproj`。
3. 选择 `侧伴` scheme 和本机 macOS 运行目标。
4. 在 Signing & Capabilities 中配置自己的开发团队与签名，然后运行。

`Packages/SidebarCore` 是本地 Swift Package，工程会通过相对路径引用。请勿只下载或移动 `侧伴` 子目录。项目未引入第三方包依赖。

仅检查编译时，可以在仓库根目录运行：

```sh
xcodebuild -project '侧伴/侧伴.xcodeproj' \
  -scheme '侧伴' -configuration Debug \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

未签名编译检查不能替代签名运行时的权限和设备验证。

## 使用与权限

首次录音需要麦克风权限，语音转写需要语音识别权限；提醒需要通知权限。全局快捷键不需要辅助功能权限。

笔记、待办和录音保存在本机。访问 Obsidian 仓库或自选附件目录时，通过系统文件夹选择器授权。转写使用系统提供的本地识别能力，受设备、系统版本和语言资源支持情况限制；首次准备语言模型时可能由系统下载资源。识别失败时保留录音，可手动重试。

默认快捷键：

| 动作 | 快捷键 |
| --- | --- |
| 开始 / 暂停专注 | Control + Option + P |
| 开始 / 停止录音 | Control + Option + R |
| 显示侧栏 | Control + Option + 空格 |

可以在设置中重新录入或清除快捷键。

## 目录结构

```text
侧伴/
  侧伴.xcodeproj/       Xcode 工程与共享 scheme
  侧伴/
    App/               应用入口与依赖组装
    Features/          笔记、待办、专注、录音、日历和设置
    Platform/          窗口、存储、音频、通知和快捷键
    Workspace/         共享状态与跨功能编排
    DesignSystem/      界面样式
    Resources/         本地化资源
    Assets.xcassets/    应用图标等资源
Packages/SidebarCore/   核心模型与窗口几何规则
Tests/                 回归检查与模拟后端
Examples/              年度节假日数据示例
Docs/                  架构与功能说明
.github/workflows/     macOS 自动检查
```

## 开发与验证

在仓库根目录运行回归检查：

```sh
bash Tests/run-workspace-checks.sh
```

检查使用隔离的偏好设置、临时目录与模拟后端，覆盖笔记迁移、附件归属、导出、通知生命周期、快捷键与日历等流程，不访问真实麦克风或个人 Obsidian 仓库。

在有桌面会话的 macOS 上，可额外检查原生快捷键：

```sh
RUN_NATIVE_SHORTCUT_CHECKS=1 bash Tests/run-workspace-checks.sh
```

麦克风、语音资源、通知横幅、多屏窗口和外部目录授权仍需在实际设备上验证。

详细信息见 [架构说明](Docs/ARCHITECTURE.md)、[功能细节与开发记录](Docs/FEATURE_DETAILS.md) 和 [贡献指南](CONTRIBUTING.md)。

## 当前限制

- Obsidian 使用手动快照导出，暂不支持自动或双向同步。
- Markdown 预览暂不支持表格与远程图片。
- 文件拖入暂不支持文件夹和符号链接。
- 番茄钟倒计时暂不跨应用重启恢复；系统已安排的通知可能仍会送达。
- 节假日规则适用于中国大陆标准工作周；缺失年度按双休估算并标注。
- 转写效果取决于系统识别能力与语言资源；长录音建议分段。

## 反馈与贡献

欢迎通过仓库 Issues 提交问题或建议，通过 Pull Request 参与改进。反馈时请说明 macOS 版本、复现步骤、预期与实际行为；分享截图或日志前请移除个人笔记、录音和路径信息。

提交代码前请阅读 [贡献指南](CONTRIBUTING.md)。

## 许可证

当前尚未附带开源许可证。公开源码不等于授予使用、修改或再分发许可；项目维护者应在正式开源发布前添加 `LICENSE`，并同步更新本节与贡献指南。
