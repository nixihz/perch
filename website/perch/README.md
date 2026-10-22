# 栖集 / Perch 介绍网站

公开地址：https://perch.keli.tech/

部署标识：`perch`，路由 `/x/perch`，访问模式 `public`。

页面位于 `dist/index.html`；品牌图片与已公证安装包随静态站点部署，不发布技能库存。设计约定见 `DESIGN.md`。Google Analytics 使用平台要求的 `G-WJEFXV72R3`，下载点击记录版本与文件格式。

更新版本时，同步 `config/updates.json`、页面文案、下载文件与 `apps.yaml`。签名、公证与装订完成后再复制分发包。

```sh
keli-cli whoami
keli-cli package website/perch --output dist/perch-website.zip
keli-cli publish website/perch --update --output dist/perch-website-published.zip
```

始终将生成的发布 ZIP 放在站点目录外，避免下次打包包含旧安装包。

平台 CLI 会排除 `.zip` 文件，因此 ZIP 下载资源以 `.download` 后缀托管，链接通过 HTML `download` 属性指定原始 `.zip` 文件名；文件字节与已公证产物一致。
