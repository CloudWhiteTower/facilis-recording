# 项目文档

当前版本为 **v2.0.0**，保持 HarmonyOS SDK **6.1.1（API 24）**。GitHub 附件未签名，安装前需开发者签名；本次发布不代表 AppGallery 上架。

| 文档 | 内容 |
| --- | --- |
| [录音、文件与转换链路](AUDIO_PIPELINE.md) | 播放修复、真实文件校验、保存到文件、应用内转换与验证边界 |
| [v2.0.0 发布附件](../release/v2.0.0/README.md) | 未签名 HAP、APP、源码归档和校验文件 |
| [音频功能验证](../data/audio-functional-validation/README.md) | Host 166、设备 67、独立解码、播放和系统保存证据 |
| [录音与交互增强](RECORDING_ENHANCEMENTS.md) | 按压光感、删除一致性、最近删除多选、平板、FLAC 与长录音验证 |
| [动画与交互优化](MOTION_IMPLEMENTATION.md) | 显示同步波形、状态转场、减弱动效与本轮验证 |
| [v2 实施与验证](V2_IMPLEMENTATION.md) | 光感、连续曲线、兼容路径、验证结果与待验收项 |
| [界面截图](../data/v2-validation/README.md) | API 24 手机亮暗页面与质量菜单 |
| [工程说明](../HarmonyRecorder/README.md) | 录音链路、文件管理、构建与测试 |
| [AppGallery 发布清单](APPGALLERY_RELEASE.md) | 正式上架准备与当前交付状态 |
| [隐私政策草案](PRIVACY_POLICY_DRAFT.md) | 权限、数据保存、分享与删除 |
| [应用市场文案](STORE_LISTING_ZH.md) | 产品说明与功能文案 |
| [品牌与图标](BRANDING.md) | 应用名称和图标资源 |

以 [v2.0.0 标签](https://github.com/CloudWhiteTower/facilis-recording/releases/tag/v2.0.0)作为本次交付入口。功能回归在 2026-09-27 完成，版本更新后的 Release 构建在 2026-09-28 完成；更早的文档保留各阶段验证记录，不应把早期测试数量视为当前总数。设备验证均在模拟器完成，API 26、实体设备听感、锁屏和功耗仍待验证。
