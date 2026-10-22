# 栖集 / Perch 介绍网站

公开地址：https://perch.keli.tech/

部署标识：`perch`，路由 `/x/perch`，访问模式 `public`。

页面位于 `dist/index.html`；品牌图片与已公证安装包随静态站点部署，不发布技能库存。设计约定见 `DESIGN.md`。Google Analytics 使用平台要求的 `G-WJEFXV72R3`，下载点击记录版本与文件格式。

更新版本时，同步 `config/updates.json`、页面文案、下载文件与 `apps.yaml`。签名、公证与装订完成后再复制分发包。

Sparkle 清单位于 `https://perch.keli.tech/updates/macos/appcast.xml`，更新包以包含版本和构建号的唯一 DMG 文件名保存在同一目录。使用 `script/prepare_sparkle_update.py` 生成并校验签名清单。先部署更新包并核对公网字节，再部署清单；保留既有安装包，不覆盖已公开的构建。客户端公钥与发布机 Keychain account 见 [在线更新说明](../../docs/sparkle-updates.md)。

```sh
keli-cli whoami
keli-cli package website/perch --output dist/perch-website.zip
keli-cli publish website/perch --update --output dist/perch-website-published.zip
```

以上整站发布仅适用于安装包较少时；平台单次上传上限为 25 MiB。历史包与新包累计超限时，使用发布机已有的 SSH 通道向既有站点 `dist/` 增量传输静态资源：先上传临时文件，在服务器核对 SHA-256，再将唯一命名包发布到最终路径；更新清单和首页使用同目录临时文件原子替换。先备份旧清单与首页，不清空部署目录，不删除历史包，也不改平台上传上限。

始终将生成的发布 ZIP 放在站点目录外，避免下次打包包含旧安装包。平台 CLI 整站更新会替换部署目录，后续使用 CLI 时必须包含需要保留的历史包，不能用仅含网页的小包覆盖已发布下载目录。

平台 CLI 会排除 `.zip` 文件，因此 ZIP 下载资源以 `.download` 后缀托管，链接通过 HTML `download` 属性指定原始 `.zip` 文件名；文件字节与已公证产物一致。
