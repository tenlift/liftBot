# 参与侧伴开发

需要 macOS、Xcode，以及所用源码 API 对应的 SDK。最低运行系统为 macOS 14。

1. 打开 `侧伴/侧伴.xcodeproj`，选择 `侧伴` scheme 和 macOS 目标。本地 SidebarCore 包自动解析，无远程包依赖。
2. 运行 `bash Tests/run-workspace-checks.sh`。
3. 运行未签名编译检查：

```sh
xcodebuild -project '侧伴/侧伴.xcodeproj' -scheme '侧伴' -configuration Debug -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
```

需要实际测试麦克风、通知和目录授权时，在 Xcode 中配置自己的签名团队。不要提交证书、描述文件、个人录音、笔记、仓库授权、API Key 或 xcuserdata。

修改前阅读 `Docs/ARCHITECTURE.md`。界面逻辑按 Features 分组，系统能力放 Platform；SidebarCore 不依赖应用层。修改持久化模型需验证旧数据兼容；涉及权限或系统 UI 的改动在 PR 中注明实机验证结果。

PR 说明问题、最终行为和验证结果。提交贡献即表示你同意以本项目的 [MIT License](LICENSE) 授权你的贡献，并确认有权提交相关内容。
