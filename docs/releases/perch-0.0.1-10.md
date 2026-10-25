# 栖集 0.0.1 (10) 发布准备记录

状态：源码与标签已推送，Developer ID 签名通用 App 已安装到本机。Apple 公证和 Sparkle 清单尚未发布；线上仍为 build 8。保留已有 build 9 标签，新产物使用 build 10。

本版包含私有技能库存、来源批量导入、原生 Markdown 预览、配置资源统一入口与已选技能区、来源筛选和界面文案整理。技能库存改为 `~/.perch/skills/library/`；自建实体在 `sources/custom/`，即使缺少库存软链仍可发现。旧 `~/.agents/skills` 中指向栖集目录的软链一次性复制进库存，原安装入口保留，后续不再回扫。

审查修复了批量复制覆盖已有来源软链、批量导入遮住无库存入口的自建技能、损坏元数据被空记录覆盖、无效正文入库、失败留下半成品，以及旧目录读取失败仍标记迁移完成的问题。新增六项回归验证内容保留、失败重试和不覆盖边界。

验证：184 项 Swift Testing、177 项 XCTest、Python 50 项和 Node 5 项通过；12 个 skill 结构检查、catalog 指纹及 diff 检查通过。原生 UI 交互尚未通过：系统仍明确报告 `CGSSessionScreenIsLocked=Yes`，不将排除 BDD 的测试结果表述为完整回归。

发布机可读取 Developer ID 证书、栖集 Sparkle 公钥及 app.u1.fan 管理员登录。`notarytool history` 通过默认与显式登录钥匙串均报告无法找到 `APP-Notary-2026`；原因尚未确认。须恢复凭据访问并完成公证，才能生成正式签名 appcast、发布官网并宣称在线更新可用。现有 Bundle ID、feed 和 Sparkle 公钥保持不变。

日志和产物目录：`dist/release-v0.0.1-10/`。仓库协作规则和新增外部 skill 软链不纳入本次产品提交。

源码提交：`f142c81dc8abb3c178f816346481040b934c8ec5`；annotated tag `perch-v0.0.1-build.10` 与远端解引用提交一致。安装和验收记录的后续文档提交不改变产物源码。

App、内置 CLI 和独立 CLI 均已构建为 arm64 / x86_64。Developer ID `zhixin xie (77TN4427T5)`、hardened runtime、时间戳及严格递归验签通过；包内与独立 CLI 分别通过仓库外 MCP 握手和安装审批链路验证，各发现 59 个工具。正式 ZIP 公证提交退出 69，stderr 明确为无法读取 `APP-Notary-2026`；空的 JSON 不作为成功证据。没有生成或发布未经公证的 appcast。

已安装 `/Applications/栖集.app`，版本 `0.0.1 (10)`，启动后确认进程存在；旧版保存在 `/Applications/栖集.app.previous-20261026-001312-build9`。安装版 CLI 读到 101 个技能，库存软链全部有效；项目登记、项目草稿、预设、片段和技能元数据安装前后 SHA-256 一致。当前安装包已签名但尚未公证，锁屏时未完成真实窗口交互验收。

匿名下载确认线上仍为 build 8、RSS XML 和 `Cache-Control: no-cache`；平台 release ID 仍为 `c46352b8-933c-44b7-a648-ad00417aab37`，`visibility` 与 `access` 均为 `public`。解锁后需恢复公证凭据访问、重跑原生验收，再完成 App 与 DMG 公证装订、Sparkle 签名、平台隔离预览、发布及匿名下载验签。本地安装不等同于已完成 Sparkle 跨版本安装验收。

机器可读证据：`dist/release-v0.0.1-10/bundle-verification.json`、`installation-verification.json`、`state-before-install.json`。构建、公证失败、测试和公网上一版清单均保留在同目录。
