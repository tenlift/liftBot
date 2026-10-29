# 侧伴架构

侧伴是 TenLift.ai 的原生 macOS 侧边工具，最低支持 macOS 14。

## 依赖方向

App / Features / Workspace / Platform → SidebarCore → Foundation / CoreGraphics。

- `Packages/SidebarCore`：本地 Swift Package。包含笔记、附件、待办的数据模型及纯窗口几何规则，不访问磁盘、网络、权限或 SwiftUI。
- `侧伴/侧伴/App`：应用入口与依赖组装。
- `Features`：Notes、Tasks、Focus、Recording、Calendar、Settings。界面状态通过 Observation 更新；NoteColor 的 SwiftUI 配色在界面层实现。
- `Platform`：窗口、文件授权、音频、转写和通知的 macOS 实现。
- `Workspace`：跨功能编排；WorkspaceStore 管理共享状态，Files 和 Export 扩展分别处理文件导入和快照导出。

目前 Platform 和 Features 是应用内目录，并非独立编译模块。核心模型与几何规则已通过真实 Package 边界隔离；继续提取包应以独立测试或复用需求为依据。

## 状态与兼容

重构保留 Codable 字段、UserDefaults 键、Application Support 路径、仓库导出路径与 Bundle ID；旧数据迁移继续由现有回归验证。Xcode 工程、Target、共享 Scheme 和应用产物统一为「侧伴」；Bundle ID 固定为原有 `devplaceholder.N4RARZAG.Untitled-Project`，不再由产品名推导，避免重命名改变应用身份。Swift 模块名为 SidebarApp。

WorkspaceStore 仍承担笔记状态与转写队列编排，尚未拆成多个独立 Store，以保持跨标签页录音归属和持久化行为稳定。

## AI 扩展

未来 AI 功能使用单独的服务协议与实现，通过应用入口注入；核心模型不依赖模型供应商 SDK。现有 TranscriptionProviding 可作为注入方式的参考。本次未增加 AI 请求、API Key 或联网权限。

## 验证

`bash Tests/run-workspace-checks.sh` 先构建真实 SidebarCore 包，再链接应用服务执行回归，不将包源码重复编入测试。应用编译与签名运行分别验证；麦克风、通知横幅、多屏和系统授权仍需实机验收。

## 界面本地化

`Platform/Localization/L10n.swift` 集中维护中英文文案，插值使用 `{0}`、`{1}` 等占位符；替换只作用于模板，不解释用户内容中的占位符。`AppLanguage` 读取独立的 `interfaceLanguage` 偏好，支持 system、zh-Hans 和 en。SwiftUI 界面通过 AppStorage 更新，应用注入日期控件使用的 locale；不以重建视图身份的方式刷新，保留编辑、录音和计时状态。

原生窗口控制器在语言变更时刷新边缘标签与菜单；通知服务重新安排当前进程管理的通知，保持 ID、截止时间及待办原文。InfoPlist 权限说明提供 en / zh-Hans 资源，实际系统弹窗语言由 macOS 控制。新增界面文案应加入 L10n 中英文表；自定义节假日名称和已有笔记内容不作为翻译资源存储。

## 全局快捷键

SidebarCore 定义 ShortcutAction、ShortcutModifiers 和 KeyboardShortcutBinding；键码与修饰键决定冲突和匹配，显示字符不参与比较。ShortcutManager 持有配置和注册生命周期，由 App 注入界面并在应用入口组装计时、录音和窗口恢复动作。ShortcutSettingsSection 使用原生按键录入按钮，不提供预设选项列表。

CarbonHotKeyBackend 只注册已配置组合；应用内定向按键提供本地回退，与原生热键共用按下状态避免重复。录入期间注销所有组合，取消或保存后恢复；注册失败不覆盖原有配置。全局快捷键不需要辅助功能权限，录音仍走原有麦克风授权。窗口关闭后 ShortcutManager 由 App 保持存活，显示动作使用 openWindow 恢复场景，再由窗口控制器展开。

## 附件笔记去向

SidebarCore.NoteDestination 表达 currentNote / newNote，WorkspaceStore 分别持久化 recordingNoteDestination 与 fileDropNoteDestination。SettingsView 使用 WorkspaceStore 的可观察属性绑定，测试可注入独立 UserDefaults。

录音完成回调先解析目标页，再插入附件并启动既有的按页转写队列。拖放入口在接收时捕获 NoteInsertionTarget（固定页 ID 或新建意图），先异步解析文件 URL，再一次性解析该批文件的目标页。后续复制仅使用固定页 ID；原目标在 URL 解析期间被删除时新建页，不改写当前的其他页面。显式 importFilesAsNewNote 保留强制新建语义，实际拖放统一走 importDroppedFiles。
