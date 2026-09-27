# AppGallery 发布清单

文档更新：2026-09-28，适用于 Facilis Recording v2.0.0。平台流程依据 2026-09-04 查阅的华为官方资料整理，本次没有重新核验审核规则；提交前应以 AppGallery Connect 当前页面和审核意见为准。

## 结论

v2.0.0 在 GitHub 交付源码、未签名 Release HAP、ZIP 封装的未签名 Release APP 和 SHA-256 校验文件，见[附件说明](../release/v2.0.0/README.md)。HAP 需开发者签名后安装；本次未完成 AppGallery 上架。开发者仍需完成账号、应用身份、发布签名、隐私及所需资质材料和审核提交。

## 当前状态

当前功能、API 24 模拟器验证与实体设备待验收范围见 [v2 实施记录](V2_IMPLEMENTATION.md)。GitHub 发布与应用市场审核是独立流程。

| 项目 | 当前状态 | 正式发布前动作 |
| --- | --- | --- |
| 应用名称 | 已设置为 `Facilis Recording` | 在 AGC 配置同名本地化信息 |
| 应用版本 | `2.0.0` / `2000000` | 后续每次发布递增 `versionCode` |
| SDK | 最低兼容和目标均为 `6.1.1(24)` | 按 API 24 支持范围准备设备验证，不宣称 API 26 已适配 |
| 设备类型 | Phone、Tablet | 在 AGC 选择一致的支持设备 |
| Release APP / HAP | 已完成 v2.0.0 Release 构建，公开附件未签名 | 按 AGC 当前流程完成发布签名；安装 HAP 前必须先签名 |
| 应用包名 | 当前为 `com.example.harmonyrecorder` | 在首次创建 AGC 应用前确认最终唯一包名；注册后不要随意更改 |
| 权限 | `ohos.permission.MICROPHONE`，使用时申请；`ohos.permission.KEEP_BACKGROUND_RUNNING` 用于用户启动的持续录音 | AGC 隐私政策中的权限和用途必须与包内声明一致 |
| 网络与 SDK | 无网络权限、无第三方运行时 SDK | 若以后新增，重新完成隐私和 SDK 声明 |
| 图标 | 已提供 1024×1024 前景/背景分层 PNG | 在真机桌面与 AGC 素材预览中复核裁切效果 |
| 截图 | v2 [手机亮暗](../data/v2-validation/README.md)、[平板增强](RECORDING_ENHANCEMENTS.md)、[播放/转换/保存](../data/audio-functional-validation/README.md) | 正式上架前以最终版本采集符合市场要求的截图 |
| 隐私政策 | 已提供草案 | 补全开发者名称、联系方式、生效日期，并在 AGC 托管或公开 URL 发布 |
| 内容分级 | 未提交 | 在 AGC 完成内容分级问卷 |
| 版权材料 | 仓库采用 MIT License | 若发布区域包含中国大陆，手机应用仍需按 AGC 要求提供应用版权证书或代理证书 |
| APP 备案 | 未办理 | 发布中国大陆前按 AGC“核准（备案）信息”流程完成并填写 |
| 审核联系信息 | 未填写 | 由开发者本人填写真实联系人、电话和邮箱 |

## 官方发布流程

1. 注册并实名验证华为开发者账号，在 AppGallery Connect 创建项目和 HarmonyOS 应用。
2. 确认应用名称、最终 Bundle Name、分类、默认语言、Phone/Tablet 支持范围。
3. 生成 Release 类型 `.app`，按当前工具链与 AGC 要求配置发布签名；本项目保持 API 24，GitHub 未签名附件不能替代此步骤。
4. 上传 APP，并确保包名、版本、设备范围与 AGC 中注册的信息一致。
5. 配置本地化信息：名称、图标、一句话简介、详细介绍、版本特性、截图/视频。
6. 完成内容分级、隐私说明、隐私政策、隐私标签、版权信息、核准（备案）信息、审核联系信息和上架时间。
7. 提交前完成漏洞、隐私、兼容性、稳定性与性能检查，然后提交审核。

## 本应用的隐私填写要点

- 麦克风用途：仅在用户主动开始录音时采集声音并生成本地音频文件。
- 数据保存：录音位于应用私有目录；关闭了应用备份恢复，不会由本应用主动上传。
- 分享：仅在用户主动选择分享时调用系统分享面板，由用户决定目标应用或设备。
- 保存与转换：系统文件选择器只在用户操作时保存副本；格式转换在本地完成并保留原件。删除应用内录音不会自动清理外部副本。
- 删除：支持最近删除、恢复和永久删除。
- 账号、广告、分析、定位、通讯录：当前版本均不使用。
- AGC 中“设备权限调用”的麦克风说明必须与软件包实际权限一致，否则无法提交审核。

## 素材检查

- 鸿蒙应用图标应为 1024×1024、正方形、PNG、前景/背景双层；背景不得含透明像素，主要图形应留足安全边距。
- 应用市场只使用本项目界面截图；本地第三方参考图片不随发行版分发。
- 当前商店文案草稿见 [STORE_LISTING_ZH.md](STORE_LISTING_ZH.md)。

## 正式签名前的安全要求

- `.p12`、`.cer`、`.p7b`、`.csr`、私钥和密码只存放在开发者控制的安全位置。
- 不把签名配置、本机绝对路径、调试日志、录音样本或源码上传到 AGC 的软件包上传区。
- 公开工程不包含本机调试签名材料；开发者需在自己的环境配置签名，上传前核对归档和包内容。
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
