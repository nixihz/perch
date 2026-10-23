# 栖集 0.0.1 (9) 发布准备记录

状态：源码、标签和已签名通用 App 已准备，尚未公证或发布。线上仍为 build 8，平台 release ID 为 `c46352b8-933c-44b7-a648-ad00417aab37`。2026-10-23 18:14 匿名下载的 appcast 与发布前逐字节一致，仍引用 build 8。

源码提交：`599117ba8f81ef4915c4bae25fac39316c7bac75`。已推送 annotated tag `perch-v0.0.1-build.9`，解引用提交与源码一致；标签注明原生验收、公证和 Sparkle 发布尚未完成。后续若修改产品代码，必须重建并使用新构建号，不移动此标签或重发不同内容。

本轮统一页面操作标题、单行侧栏和可滚动项目列表，新增技能重名、同内容、状态及来源筛选，规则片段使用自然排序。技能正文、插件详情、片段引用、全局配置、MCP 和 AI 接入改为后台读取；全局配置核验失败提供具体原因和路径。

审查修复了两处高优先级问题：后台切换全局宿主时，排队读取前的空草稿可能覆盖已有选择；CRLF 规则恢复使用字符偏移时，可能改到受管块外正文。另修复同项读取失败或取消后丢失结果、过期请求回写、项目切换残留 MCP 范围、AI 接入程序消失后保留旧计划、非法规则标记丢失路径诊断，以及空指纹误判同内容。回归覆盖真实失败、重试、撤销和块外编辑保留。

验证结果：153 项 Swift Testing、11 项核心 XCTest、136 项应用 XCTest 通过；Python 31 项、Node 5 项、12 个 skill 结构检查、catalog 指纹与 diff 检查通过。核心全局专项 19 项通过，两个缺陷保留修复前失败证据。完整 Swift 命令退出 1：BDD target 共 406 项，其中 21 项均因原生侧栏等待超时失败，151 个后续步骤跳过，234 项通过，不能宣称完整回归通过。

系统明确返回 `CGSSessionScreenIsLocked=Yes`，CUA 对隔离测试应用返回 `cgWindowNotFound`。测试辅助代码还存在独立问题：仅沿 `AXChildren` 查找窗口，未处理窗口只出现在 `AXWindows` 的情况，也未去重重复边；现已使用显式窗口根和按 AX 身份去重，保留菜单及弹出控件覆盖。修复后测试能正常超时结束，真实交互仍须解锁后复验。十页 NSHostingView 缓存截图与布局检查已完成；顶部材质遮挡是否仅为缓存截图现象，以及窄窗口英文按钮截断，仍待真实窗口复核。

Release App、内置 CLI 和独立 CLI 均为 arm64 / x86_64。Developer ID `Developer ID Application: zhixin xie (77TN4427T5)`、hardened runtime、严格递归验签通过；包内与独立 CLI 在仓库外完成 MCP 握手，各发现 17 个工具。沿用 Bundle ID `com.xiezhixin.perch`、原 Sparkle 公钥与 `https://app.u1.fan/x/perch/updates/macos/appcast.xml`，最低 macOS 14。产品代码在构建前已冻结，后续仅调整测试夹具和测试辅助代码。

已有 `APP-Notary-2026` 在 build 7、8 中成功使用。本轮 history 与 submit 在当前命令行上下文返回 profile lookup failure（退出 69）；已核对用户、默认登录钥匙串、解锁状态及精确 profile 查询，未确认原因，不能据此断言 profile 缺失。Mac 同时处于锁屏状态，是否与公证读取失败有关须解锁后验证。未导出密码、重建凭据或修改访问控制；空的 `app-notary.json` 不代表公证成功。

尚未生成正式 DMG、签名 appcast 或平台发布包。下一步由用户本机解锁后，重跑原生验收并重试公证 history；通过后完成 App 公证与装订、DMG 签名公证与装订、官方 Sparkle 签名、平台来源字节核对、隔离预览、发布及匿名公网下载验签。真实 build 8 → 9 的安装、重启与数据保留仍需独立 macOS 图形用户或 VM 验收。

产物、日志、截图、机器可读报告和续发命令保存在 `dist/release-v0.0.1-9/`。干净源码 checkout 为 `/tmp/perch-build9-source`。首次外部审查误中断及后续 AX 遍历中断日志单独保留，均不计为通过。
