# 栖集 0.0.1 (10) 发布记录

状态：已发布并安装到本机。官网与 Sparkle 清单均为 build 10，平台 release ID：`c8c17552-c8b4-4232-8b61-9409af5689eb`。旧版保留在平台发布历史中。

本版包含全部待发布产品功能：私有技能库存、来源批量导入、原生 Markdown 预览、全局／项目／预设的配置资源入口与已选技能区、来源筛选和界面文案整理。技能库存改为 `~/.perch/skills/library/`；自建实体在 `sources/custom/`，即使缺少库存软链仍可发现。旧 `~/.agents/skills` 中指向栖集目录的软链一次性复制进库存，原安装入口保留，后续不再回扫。

审查修复了批量复制覆盖已有来源软链、批量导入遮住无库存入口的自建技能、损坏元数据被空记录覆盖、无效正文入库、失败留下半成品，以及旧目录读取失败仍标记迁移完成的问题。新增六项回归验证内容保留、失败重试和不覆盖边界。

产品源码提交：`f142c81dc8abb3c178f816346481040b934c8ec5`；annotated tag `perch-v0.0.1-build.10` 已推送，远端解引用与产物源码一致。构建后修正旧原生验收的入口和文案，测试提交为 `985f393`；未修改已签名的产品代码或移动标签。协作规则和新增外部 skill 软链未纳入产品提交。

解锁后，既有 `APP-Notary-2026` 的 history 与 submit 恢复可用，没有重建凭据或调整钥匙串授权。首次原生回归发现六处旧流程测试失败，已按 MCP 新标题、项目详情入口、保存按钮及插件资源页重写路径，继续保留风险确认、凭据拒绝、取消不写入与原文件保留的验证。此前失败日志保留，不计入通过结果。

最终 `swift test` 完整通过：184 项 Swift Testing、11 项核心 XCTest、177 项应用 XCTest、403 项 BDD XCTest（396 项 Gherkin 测试和 7 项原生工作流），零失败、零跳过。Python 50 项、Node 5 项、12 个 skill 结构检查、catalog 指纹和 diff 检查均通过。完整日志为 `dist/release-v0.0.1-10/swift-tests-final.log`。

App、内置 CLI 和独立 CLI 均为 arm64 / x86_64。Developer ID `zhixin xie (77TN4427T5)`、hardened runtime、签名时间戳及严格递归验签通过；包内与独立 CLI 分别通过仓库外 MCP 握手和安装审批链路验证，各发现 59 个工具。保留 Bundle ID、Sparkle 公钥与 feed，最低 macOS 14。

App 公证 ID：`f20af5a2-8a11-4c2d-b5c0-035495dba82f`；DMG 公证 ID：`90187b1e-697d-4915-a2dd-cb9eb9622ef6`，均为 `Accepted`。App 和 DMG 已装订并通过验证，应用 Gatekeeper 返回 `Notarized Developer ID`。此前退出 69 的公证日志与空 JSON 保留为失败证据。

正式 DMG `Perch-0.0.1-10-universal.dmg` 为 26,889,095 字节，SHA-256：`b54d7b133fd3a51a2fc6026a93faece60e022ebeba431b77e5ef6a00fc2f2a5a`。appcast 为 837 字节，SHA-256：`c8b39a677e55d8c81dcfec5ef42ef996a2d79f60965c23d3775d60e609d89059`。本地与公网完整 DMG 均通过官方 Sparkle 验签。从已装订 App 生成的 ZIP 仅保留为本地离线产物。

平台 ZIP 为 24,450,946 字节，低于 25 MiB 上限，SHA-256：`ff7f36d2ee733906b194356345308c26cdcecfc31e1b357d74ae8ec60156a1b4`。由 build 10 标签对应的干净检出组装，验证该提交属于 main 历史；来源元数据如实记录 detached HEAD、精确提交、remote 与 `dirty=false`。包内为五个来源文件及唯一生成元数据，无额外内容。隔离预览逐文件核验通过，退出后临时服务已清理。

使用既有管理员登录执行平台 `publish --update`；`manifest.access` 与实例 `visibility` 均为 `public`。匿名公网首页、品牌图、RSS XML 和完整 DMG 均与来源逐字节一致；HEAD 长度正确，appcast 返回 `Cache-Control: no-cache`。Range 仍返回完整 200，不提供分段 206。未修改平台基础设施或旧 keli.tech 站点。

本机已安装并运行 `/Applications/栖集.app`，设置页确认 `0.0.1 (10)`，公证装订与 Gatekeeper 检查通过。技能库显示 101 个技能、0 个不可用；项目登记、草稿、预设、片段和技能元数据的安装前后 SHA-256 一致。旧应用保留在 `/Applications/栖集.app.previous-20261026-001312-build9`。发布后在真实应用中手动检查更新，Sparkle 显示当前为最新版。

产物和机器可读证据保存在 `dist/release-v0.0.1-10/`、`dist/sparkle-release-0.0.1-10/` 与 `dist/perch-app-platform-v0.0.1-10/`。本次已完成本机安装、真实更新检查和公网签名核验；独立用户或 VM 中的旧正式版经 Sparkle 下载、安装、重启的跨版本链路未另行验收。
