# AppGallery 发布清单

本文依据 2026-09-04 可访问的华为官方资料整理，供 Facilis Recording 从开源 Demo 进入正式发布时使用。平台规则会更新，提交前应再次以 AppGallery Connect 页面和当期审核意见为准。

## 结论

本仓库可以交付完整源码、Release 构建产物、隐私政策草案和应用市场素材，但无法代替开发者本人完成实名账号、APP ID 注册、发布证书/Profile、版权证明、APP 备案及最终提交审核。因此，GitHub Release 中的 APP 是“待 AGC 签名或重签名的 Release 交付件”，不能表述为“已上架正式包”。

## 当前状态

2026-09-27 补记：v2 光感与连续波形以开发分支源码交付，尚未创建正式 v2 Release，应用版本号仍为下表的 v1 基线。v2 的构建、设备验证和待验收范围见 [v2 实施记录](V2_IMPLEMENTATION.md)；以下官方规则沿用 2026-09-04 调研，未在本次文档更新中重新核验。

| 项目 | 当前状态 | 正式发布前动作 |
| --- | --- | --- |
| 应用名称 | 已设置为 `Facilis Recording` | 在 AGC 配置同名本地化信息 |
| 应用版本 | `1.0.0` / `1000000` | 后续每次发布递增 `versionCode` |
| 设备类型 | Phone、Tablet | 在 AGC 选择一致的支持设备 |
| Release APP | 已由 `devecocli build --product default --build-mode release` 生成 | 使用 AGC 云管理签名或发布证书/Profile 完成正式签名 |
| 应用包名 | 当前为 `com.example.harmonyrecorder` | 在首次创建 AGC 应用前确认最终唯一包名；注册后不要随意更改 |
| 权限 | 仅 `ohos.permission.MICROPHONE`，使用时申请 | AGC 隐私政策中的权限和用途必须与包内声明一致 |
| 网络与 SDK | 无网络权限、无第三方运行时 SDK | 若以后新增，重新完成隐私和 SDK 声明 |
| 图标 | 已提供 1024×1024 前景/背景分层 PNG | 在真机桌面与 AGC 素材预览中复核裁切效果 |
| 截图 | v1 手机/平板：`data/ui-audit-2026-09-04/`；v2 手机亮暗：[截图索引](../data/v2-validation/README.md) | 正式上架前用最终版本重新采集匹配设备的截图 |
| 隐私政策 | 已提供草案 | 补全开发者名称、联系方式、生效日期，并在 AGC 托管或公开 URL 发布 |
| 内容分级 | 未提交 | 在 AGC 完成内容分级问卷 |
| 版权材料 | 仓库采用 MIT License | 若发布区域包含中国大陆，手机应用仍需按 AGC 要求提供应用版权证书或代理证书 |
| APP 备案 | 未办理 | 发布中国大陆前按 AGC“核准（备案）信息”流程完成并填写 |
| 审核联系信息 | 未填写 | 由开发者本人填写真实联系人、电话和邮箱 |

## 官方发布流程

1. 注册并实名验证华为开发者账号，在 AppGallery Connect 创建项目和 HarmonyOS 应用。
2. 确认应用名称、最终 Bundle Name、分类、默认语言、Phone/Tablet 支持范围。
3. 生成 Release 类型 `.app`。华为官方说明，上架包必须是 Release 类型；DevEco Studio 26.0.0 Beta1 及以上可在上传时使用 AGC 云管理证书重新签名，较早版本需要自行准备发布证书和 Release Profile。
4. 上传 APP，并确保包名、版本、设备范围与 AGC 中注册的信息一致。
5. 配置本地化信息：名称、图标、一句话简介、详细介绍、版本特性、截图/视频。
6. 完成内容分级、隐私说明、隐私政策、隐私标签、版权信息、核准（备案）信息、审核联系信息和上架时间。
7. 提交前完成漏洞、隐私、兼容性、稳定性与性能检查，然后提交审核。

## 本应用的隐私填写要点

- 麦克风用途：仅在用户主动开始录音时采集声音并生成本地音频文件。
- 数据保存：录音位于应用私有目录；关闭了应用备份恢复，不会由本应用主动上传。
- 分享：仅在用户主动选择分享时调用系统分享面板，由用户决定目标应用或设备。
- 删除：支持最近删除、恢复和永久删除。
- 账号、广告、分析、定位、通讯录：当前版本均不使用。
- AGC 中“设备权限调用”的麦克风说明必须与软件包实际权限一致，否则无法提交审核。

## 素材检查

- 鸿蒙应用图标应为 1024×1024、正方形、PNG、前景/背景双层；背景不得含透明像素，主要图形应留足安全边距。
- 应用市场只使用本项目界面截图。`data/motiv-audio-reference/` 是本地竞品研究材料，因第三方版权不进入仓库或发布素材。
- 当前商店文案草稿见 [STORE_LISTING_ZH.md](STORE_LISTING_ZH.md)。

## 正式签名前的安全要求

- `.p12`、`.cer`、`.p7b`、`.csr`、私钥和密码只存放在开发者控制的安全位置。
- 不把签名配置、本机绝对路径、调试日志、录音样本或源码上传到 AGC 的软件包上传区。
- GitHub 仓库中的 `build-profile.json5` 已移除本机调试签名信息；开发者需在自己的环境重新配置。
- 如果更换正式签名证书，应先确认后续升级路径；同一应用的更新必须保持签名体系一致。

## 官方资料

- [提交 HarmonyOS 应用](https://developer.huawei.com/consumer/cn/app/submit)
- [发布应用：AppGallery Connect 文档目录](https://developer.huawei.com/consumer/cn/doc/doccenter-submission/agc-help-release-0000002235870050)
- [配置隐私政策（HarmonyOS 应用）](https://developer.huawei.com/consumer/cn/doc/doccenter-submission/agc-help-privacy-policy-app-0000002282162168)
- [配置版权信息](https://developer.huawei.com/consumer/cn/doc/doccenter-submission/agc-help-release-app-copyright-0000002278981450)
- [HarmonyOS 应用图标规范](https://developer.huawei.com/consumer/cn/doc/doccenter-ux-design/application-icon-0000001953444009)
- [app.json5 配置文件](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/app-configuration-file)
- [应用隐私保护最佳实践](https://developer.huawei.com/consumer/cn/doc/doccenter-architecture/bpta-app-privacy-protection)
- [华为应用市场审核协议与准则](https://developer.huawei.com/consumer/cn/agreement/)
