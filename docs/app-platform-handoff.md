# app.u1.fan 应用发布交接

请在平台仓库 `/opt/case/u1.fan/app-like-action` 处理以下问题。本次只迁移了 Perch，未修改平台程序；以后还会发布多个同类应用，需要由平台统一支持。

## 当前事实

- 平台：`https://app.u1.fan`；线上版本 `0.1.3`，程序发布编号 `20261022T060923Z`。
- 线上已设置 `APPS_APP_BASE_URL=https://u1.fan`。应用标准公开地址为 `<name>.u1.fan`；`/x/<name>/...` 会 308 跳转到独立域名，路径与查询参数保留。
- DNS 已能解析 `perch.u1.fan` 至目标服务器；服务器已有有效的 `*.u1.fan` 通配证书，路径 `/etc/letsencrypt/live/wildcard.u1.fan/`，到期日 2027-01-20。现有续期使用手工 DNS-01，不因 Certbot timer 处于 active 就能推定自动续期成功。
- 发布 Perch 后，平台返回成功和独立公开地址，但 Nginx 没有 Perch 入口。此时 `/x/perch/` 跳转后的 TLS hostname 校验失败，官网、下载包和 Sparkle 清单均不可用。
- 已为 Perch 单独新增 `/etc/nginx/conf.d/perch.u1.fan.conf`，复用已有通配证书和后端 `127.0.0.1:4183`；清单精确路径 `/updates/macos/appcast.xml` 返回 `Cache-Control: no-cache`。这是本次临时运维补齐，后续不应每个应用重复配置。
- 平台、Capslock Bye 及同机两个既有站点的首页摘要在此次变更前后一致；平台应用根域、既有站点配置及证书均未修改。

## 优先处理：统一应用域名托管

先读取平台 `AGENTS.md`、`DESIGN.md` 与 `.agents/skills/deploy/SKILL.md`，按目标 `u1-fan` 的专项流程处理 Nginx。只操作本目标，保留数据、证书和其他站点。

1. 核对实际 DNS、证书 SAN、Nginx server_name 及平台应用根域配置，形成一致的托管方案。优先考虑通用应用子域入口，精确的管理台域名仍使用管理台配置；不要依赖逐应用手工添加 server block。
2. 将应用 Host 原样传给平台，由平台解析应用名、执行访问策略并托管文件。未知子域必须拒绝，不能意外落到管理台或其他站点。保留受保护应用的登录跳转、单应用会话和 Origin 校验。
3. 已有 Perch 和 Capslock Bye 精确配置迁移到通用方案时，先验证等价行为、保存恢复依据，再切换；不要简单删除旧配置或改全局应用根域。
4. 发布结果区分“应用已安装”和“公网入口已验证”。若配置了独立根域但 DNS/TLS/反代尚未就绪，应提供明确、可操作的诊断。不要以成功上传或服务器自身请求成功代替用户侧 HTTPS 验收。
5. 固定名称的 Sparkle 清单需要及时重新验证。为应用提供受控的缓存策略或统一支持 `appcast.xml`，使 GET/HEAD 返回 `no-cache`；唯一命名安装包仍可长期缓存。避免对全部 XML 或全部资源无差别禁用缓存。
6. 明确通配证书续期责任、验证方法与到期提醒；没有 DNS-01 授权时不要声称已自动化，不要重签现有证书或更改系统代理来掩盖问题。

验收至少覆盖：两个现有应用和一个无需新增 Nginx 配置的应用子域、可信 HTTPS、未知域名拒绝、公开访问、受保护访问及会话隔离、管理台仍可访问、路径/查询跳转、清单缓存、完整安装包 SHA-256，以及同机站点回归。涉及平台 UI 时同步维护 `DESIGN.md`。

## 第二项：CLI 登录状态不应随工作目录变化

当前 CLI `--data` 默认为相对路径 `data`。用户在家目录登录后，从另一个项目运行 `whoami` 就显示未登录；此前因此重复触发授权。用户原有登录实际有效且具有管理员权限，复用同一目录即恢复。

建议将 CLI 客户端凭据与服务端运行数据库分离：客户端使用稳定的用户级目录，并按规范化 server URL 保存会话；明确 `--data` 的兼容行为与迁移策略，保留旧数据，不静默丢失或导出凭据。未登录诊断应说明读取的目录与目标服务，输出须脱敏。

验收：在目录 A 登录、目录 B 查询和发布，身份保持一致；不同 server 的凭据不能混用；旧目录、显式覆盖、失效会话和权限不足分别有可观察结果。不要把浏览器已登录等同于 CLI 已拿到会话。

## 第三项：桌面安装包分发

- 当前上传 ZIP 限制 25 MiB，解压上限 100 MiB；Nginx 也限制请求体大小。
- CLI 打包会排除 `.zip` 文件。把 macOS ZIP 放进静态站目录时，命令成功但文件缺失，网页可能仍保留无效下载入口；只验证归档已有条目无法发现遗漏。
- 本次 Perch 的 DMG 与 ZIP 合包超限，因此新站只提供 DMG，Sparkle 与手动下载共用。ZIP 仅本地保留；没有改后缀绕过排除或提高线上限制。

建议明确区分构建产物、部署包和应用分发附件：打包输出应说明排除原因、缺失的预期文件及大小；支持有意发布的 ZIP 附件，并保留秘密、运行数据、软链接和路径穿越防护。较大、不可变、已签名安装包可考虑独立附件/对象存储渠道，避免每次站点更新重复上传、受到静态应用包限制或随版本清理失效。不要仅提高一个限制而忽略代理、解压和存储生命周期。

验收来自实际用户行为：DMG/ZIP 下载链接可达且字节正确，缺失文件不能被 HTML fallback 的 200 掩盖；被清单引用的历史包保留，失败发布仍能使用旧版本，签名后的文件不得被平台重新压缩或修改；HEAD 和 Range 行为应明确。目前 Range 返回完整文件 200，不能声称支持续传。

## Perch 发布结果与回归依据

- 应用 `perch`，内部挂载路由 `/x/perch`，访问模式 `public`，桌面 `0.0.1 (4)`。
- 平台 release ID：`407bf84e-1cfc-4d5e-b5da-83b46d84de57`。
- 官网入口：`https://app.u1.fan/x/perch/`，最终地址 `https://perch.u1.fan/`。
- 客户端内置 feed：`https://app.u1.fan/x/perch/updates/macos/appcast.xml`。
- 已签名 enclosure：`https://app.u1.fan/x/perch/updates/macos/Perch-0.0.1-4-universal.dmg`。
- 两个更新地址会跳转到相应 Perch 子域路径；已验证 TLS、匿名完整下载与 Sparkle 验签。保持现有 URL 可用，无需为修复平台重签同一 build。
- DMG：25,210,037 字节，SHA-256 `e4b2f26e190f8ee89173f17e4a90a67e2e809607dfc9a64d89185506a30843e0`。
- appcast：835 字节，SHA-256 `8a066165f4bdbed3bc3ed149be09be664a53a7c63dd7e868872546f5ecea6ea3`。
- 配置副本：本仓 `website/perch/perch.u1.fan.nginx.conf`。服务器维护记录：`/root/deploy-backups/perch-hosting-build4-20261022T0655Z/`。
- 本地报告：`dist/release-v0.0.1-4/release-verification.json` 与 `public-platform-verification.json`。完整发布目录：`dist/perch-app-platform-v0.0.1-4/`。
- 本轮浏览器工具超时，未做最终视觉复核；公网 HTTP/文件验收已完成。跨版本下载、安装、重启和数据保留仍未实测。
- Perch 不再向 keli.tech 发布更新。旧 feed 不修改，旧客户端需要手动安装一次迁移版；不要把平台修复扩展为旧站迁移操作。

## 相关实现入口与文档建议

平台 `src/hosting.rs` 负责路由解析与跳转，`src/apps.rs` 生成独立公开地址，`src/cli.rs` 保存/读取 CLI 会话，`src/archive.rs` 负责打包排除及大小限制。部署约定见平台 `deploy/README.md` 及 deploy skill。

完成平台改进后，同步内置和分发的 `app-platform-dev` 指引：明确标准公开地址与内部挂载路由的区别、DNS/TLS 前置条件、稳定的 CLI 登录目录、完整打包文件集合验证以及桌面附件限制。不要只修应用而让下一次发布再次踩同样的问题。
