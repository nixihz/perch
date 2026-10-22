# 栖集 / Perch 介绍网站

发布平台：`https://app.u1.fan`。公开地址：`https://perch.u1.fan/`。平台挂载入口 `https://app.u1.fan/x/perch/` 会以 308 跳转到该地址，HTTPS 校验已通过。

部署标识为 `perch`，路由 `/x/perch`，访问模式 `public`。从桌面 build 4 起，官网、下载包与 Sparkle 清单均使用新平台；不再向 keli.tech 发布更新。旧客户端内置旧清单地址，须从新官网手动安装一次迁移版，后续在应用内检查更新。

页面位于 `dist/index.html`，品牌图片与已公证安装包随静态应用包发布；不包含技能库存、凭据或本机数据。设计约定见 `DESIGN.md`。静态资源和下载链接使用相对路径，支持 `/x/perch/` 挂载。

Sparkle 清单为 `https://app.u1.fan/x/perch/updates/macos/appcast.xml`，唯一命名的 DMG 位于同一目录；新平台单次发布包上限为 25 MiB，因此官网与 Sparkle 共用同一 DMG；ZIP 仅作为本地离线产物保留，不在新站提供 ZIP 下载。使用 `script/prepare_sparkle_update.py` 生成并验证签名清单，下载 URL 与客户端内置地址必须一致。客户端公钥与发布机 Keychain account 见[在线更新说明](../../docs/sparkle-updates.md)。更换托管地址保留原公钥和 Bundle ID，递增桌面构建号并重新签名、公证。

## 打包与发布

遵循 `app-platform-dev` skill，显式指定平台，不能沿用 keli-cli 或旧平台 SSH 发布路径：

```sh
# 使用之前成功登录时的目录；本机本次为 ~/data。
PLATFORM_CLI_DATA="$HOME/data"
app-platform --data "$PLATFORM_CLI_DATA" --server https://app.u1.fan whoami
app-platform --data "$PLATFORM_CLI_DATA" package <发布目录> --output dist/perch-app-platform.zip
# app.u1.fan 首次安装 perch
app-platform --data "$PLATFORM_CLI_DATA" --server https://app.u1.fan publish <发布目录>
# 后续更新
app-platform --data "$PLATFORM_CLI_DATA" --server https://app.u1.fan publish <发布目录> --update
```

CLI 的 `--data` 默认为当前目录下的 `data`；不同工作目录会读取不同登录状态。先用已登录时的同一目录运行 `whoami`，确认具有管理员权限。本机本次复用了 `~/data`，无需重复登录。

平台已设置应用根域 `https://u1.fan`，会将 `/x/perch/` 跳转到 `perch.u1.fan`。已新增本站专用 [Nginx 配置](perch.u1.fan.nginx.conf)，复用服务器已有 `*.u1.fan` 证书和平台反代；固定清单路径返回 `Cache-Control: no-cache`。此配置由服务器运维安装，不放入应用包。通配证书沿用平台现有 DNS-01 续期安排，本次未签发或修改证书。

发布目录只包含一份 `apps.yaml`、页面、品牌素材、正式分发包与签名清单。输出 ZIP 保存在发布目录之外，避免递归打包。官网页面、清单、下载包在同一平台发布版本中交付；不要直接修改平台发布目录。只保留该平台仍被清单或网页引用的历史文件，移除当前包中的历史版本前先核对引用。旧 keli.tech 站点保持原样，不依靠修改旧清单迁移客户端。

发布后通过实际挂载 URL 验证首页、图片、公开访问、完整下载 SHA-256、长度、HEAD/Range、appcast XML、版本、公钥签名及缓存行为；不能仅凭 200 判断成功。CLI 会排除 `.zip` 文件，且 DMG 与 ZIP 合包超过平台 25 MiB 上限；不要改后缀绕过排除后直接发布超限包。打包核验须比较完整预期文件清单，不能只检查 ZIP 内已有条目。发布回滚恢复平台上一版本的文件，不更改用户本机数据。

2026-10-22 已发布 build 4，平台 release ID 为 `407bf84e-1cfc-4d5e-b5da-83b46d84de57`。首页、图片、appcast 与 DMG 匿名 HTTPS 完整下载均与发布目录逐字节一致；公网 DMG 的 Sparkle 验签通过。HEAD 返回 200 和正确长度；Range 返回完整文件（200）。旧站未修改，跨版本安装尚未验收。

平台通用托管、CLI 登录目录与桌面附件分发问题见[平台交接](../../docs/app-platform-handoff.md)。

2026-10-22 再次更新至 `0.0.1 (5)`，release ID 为 `4b4ee2af-fd9c-4ced-8cf0-78f6ff30fbbe`；唯一命名 DMG、官网与签名清单同批发布，匿名公网字节及 Sparkle 验签通过。最新发布目录为 `dist/perch-app-platform-v0.0.1-5/`，本地验收报告见 `dist/release-v0.0.1-5/`。
