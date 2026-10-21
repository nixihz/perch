# 栖集 / Perch 品牌资产

## 文件

- `perch-primary.png`：确认采用的透明背景主标，保留纸艺层次、羽毛阴影和文件夹细节。
- `perch-appicon-1024.png`：从主标缩放得到的 App Icon 主图。
- `perch-appicon.svg`：App Icon 的排版源文件；圆角底和边框是矢量，猫头鹰仍使用原 PNG，不做伪矢量化。
- `Perch.appiconset/`：由 App Icon 主图导出的 macOS 图标资源。

重新生成图标：

```bash
./script/render_perch_icons.sh
```

## 视觉约束

- 主色：陶土红 `#C86446`、浅陶土 `#DC896B`、深砖棕阴影、纸白 `#F2EBDD`、琥珀金眼睛与爪部。与应用的 Samantha 陶土红主题一致。
- 主标是保留纹理和体积感的 PNG，不追踪成会丢失层次的伪矢量化文件。
- App Icon 只裁掉透明边距并重新居中，不改动猫头鹰、羽毛阴影和档案夹的内容。
- 16px 和 32px 使用同一主图的缩放版本；极小尺寸只保证整体轮廓和配色，不保证羽毛细节可辨。
- 图标资产本身不叠加文字、额外阴影、渐变或装饰性星星。
- 界面在侧栏顶部使用 48pt Logo，旁边显示“栖集 Perch”和“Skill Set 工作台”；Logo 保持原色，不套用 template tint，不加入重复的无障碍朗读。
- 生成脚本同时更新 `Perch.appiconset/` 与应用资源 `PerchLogo.imageset/`，Dock 和界面使用同一来源。

## 陶土红版本

使用内置 `image_gen` 编辑既有主标。编辑要求为：只将绿色羽毛与档案夹改为陶土红、浅陶土与砖棕阴影；保留猫头鹰姿态、纸艺纹理、层次、纸白脸部和琥珀眼睛／喙／爪，保留透明背景，不新增文字或形状。生成结果保存为 `perch-primary.png` 后，通过既有脚本裁边、排版并导出全部尺寸。
