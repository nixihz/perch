# 栖集 0.0.1 (10) 发布准备记录

状态：代码已完成审查与修复，正在准备签名通用 App。尚未完成 Apple 公证、Sparkle 清单发布或本机安装；线上仍为 build 8。保留已有 build 9 标签，新产物使用 build 10。

本版包含私有技能库存、来源批量导入、原生 Markdown 预览、配置资源统一入口与已选技能区、来源筛选和界面文案整理。技能库存改为 `~/.perch/skills/library/`；自建实体在 `sources/custom/`，即使缺少库存软链仍可发现。旧 `~/.agents/skills` 中指向栖集目录的软链一次性复制进库存，原安装入口保留，后续不再回扫。

审查修复了批量复制覆盖已有来源软链、批量导入遮住无库存入口的自建技能、损坏元数据被空记录覆盖、无效正文入库、失败留下半成品，以及旧目录读取失败仍标记迁移完成的问题。新增六项回归验证内容保留、失败重试和不覆盖边界。

验证：184 项 Swift Testing、177 项 XCTest、Python 50 项和 Node 5 项通过；12 个 skill 结构检查、catalog 指纹及 diff 检查通过。原生 UI 交互尚未通过：系统仍明确报告 `CGSSessionScreenIsLocked=Yes`，不将排除 BDD 的测试结果表述为完整回归。

发布机可读取 Developer ID 证书、栖集 Sparkle 公钥及 app.u1.fan 管理员登录。`notarytool history` 通过默认与显式登录钥匙串均报告无法找到 `APP-Notary-2026`；原因尚未确认。须恢复凭据访问并完成公证，才能生成正式签名 appcast、发布官网并宣称在线更新可用。现有 Bundle ID、feed 和 Sparkle 公钥保持不变。

日志和产物目录：`dist/release-v0.0.1-10/`。仓库协作规则和新增外部 skill 软链不纳入本次产品提交。
