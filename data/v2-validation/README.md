# v2 手机外观检查（API 24，开发中）

这些是 Pura 90 模拟器的真实截图，原始尺寸 1320×2856。不是 API 26 效果或最终验收结论。

## 2026-09-23 当前版本

| 场景 | 文件 |
| --- | --- |
| 亮色录音空闲 | [当前截图](api24-light-wave-final-2026-09-23.png) |
| 暗色录音空闲 | [当前截图](api24-dark-wave-final-2026-09-23.png) |
| 亮色质量 Sheet | [截图](api24-quality-light-2026-09-23.png) |
| 暗色质量 Sheet | [截图](api24-quality-dark-2026-09-23.png) |
| 暗色格式 Select | [截图](api24-select-dark-2026-09-23.png) |

设备未报告 HDS 高级材质支持，本轮为系统模糊与轻量光感。曲线模型已通过本机与设备单元测试，录音过程由用户手动验收。`api24-light-wave-2026-09-23.png` 是修复按钮圆形裁切与透明渐变之前的过程截图。

## 2026-09-05 历史检查

| 场景 | 文件 | 状态 |
| --- | --- | --- |
| 亮色录音空闲 | api24-phone-recorder-light.png | 暖橙舞台材质，未录音 |
| 暗色录音空闲 | api24-phone-recorder-dark-r2.png | 色调及系统栏已跟随主题 |
| 亮色音质 Sheet | api24-phone-quality-light.png | 三段音质设置 |
| 暗色音质 Sheet | api24-phone-quality-dark-r2.png | 未出现白色 Sheet |
| 暗色格式下拉 | api24-phone-select-dark.png | 未出现白色 Select 菜单 |
| 初轮设置暗色 | api24-phone-settings-dark.png | 外观分组与浮动底栏 |

`api24-phone-current.png` 是最初偏实白的舞台；`api24-phone-quality-check.png` 记录光效覆盖层阻断格式入口时的界面。保留用于回归对照，不代表当前最终设计。

M4A 选择后的 UI 树同时包含 `M4A · 128 kbps`、`M4A`、`码率`、`128 kbps`，已确认主页面和 Sheet 显示同步。

录制进行/暂停、资料库普通/选择、播放器，以及平板/API 26 完整截图矩阵尚未完成。
