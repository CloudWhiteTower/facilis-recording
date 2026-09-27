# Facilis Recording 2.0.0

此版本更新鸿蒙原生交互、录音文件管理和音频转换。最低兼容 API 24，支持手机与平板；提供 arm64-v8a 和 x86_64 原生库。

## 本次更新

- 统一弹簧动效、按压光感和显示同步波形，适配减弱动效设置与平板布局。
- 修复删除操作、文件索引与动画状态的一致性；最近删除支持多选恢复和永久删除。
- 新增 FLAC 录音；加固 WAV 流式写入、后台录音和异常停止处理。
- 修复播放状态、文件描述符生命周期、连续跳转与错误提示，使用实际文件参数显示录音信息。
- 新增系统“保存到文件”，保留原件；无效文件保留并标记，便于备份和处理。
- 支持应用内 WAV、FLAC、M4A 转换，提供进度和取消，成功后生成新录音。

## 下载和安装

[GitHub Release](https://github.com/CloudWhiteTower/facilis-recording/releases/tag/v2.0.0) 提供以下附件：

| 附件 | 用途 |
| --- | --- |
| `facilis-recording-v2.0.0-release-unsigned.hap` | Release 模式的未签名鸿蒙应用模块；使用开发者自己的证书及 Profile 签名后安装 |
| `facilis-recording-v2.0.0-release-unsigned-app.zip` | 内含完整未签名 `.app` 分发包，用于开发者后续签名和发布流程 |
| `facilis-recording-v2.0.0-source.zip` | 与发布标签一致的源码，含测试、文档及公开验证结果 |
| `SHA256SUMS.txt` | 上述三个附件的 SHA-256 校验值 |

本版本不分发本地调试证书、Profile、设备授权列表或带这些配置的调试签名包。未签名 HAP 不能直接点击安装；开发者也可下载源码，用匹配 API 24 的 DevEco Studio 配置自己的签名后部署。APP 压缩包解压后得到 `.app`，不应通过修改扩展名将其当作 HAP 安装。

GitHub 发布不代表已上架 AppGallery。包名仍为 `com.example.harmonyrecorder`，版本号为 `2.0.0 / 2000000`；覆盖升级需要兼容的签名，升级前应导出重要录音，不要通过卸载旧应用解决签名冲突。

## 验证与范围

- 本轮版本号更新后的 Release 产品构建通过；前一轮 Debug 和测试 HAP 构建通过。
- Host 自动化 166 项、API 24 平板主测试集 67 项通过。
- WAV、FLAC、M4A 的头/中/尾播放，以及 FLAC 实际界面播放检查通过。
- 系统文件选择器保存后的 FLAC 副本与原件 SHA-256 一致。
- 15 个转换相关文件（11 输出、4 输入）独立完整解码成功；5 组无损 PCM 对比逐样点一致。
- 既有 30:57.62 WAV 实录样本复检通过；本次发布准备没有重新进行长录音。

当前转换范围为 44.1/48 kHz、单声道；FLAC 输出支持 16 bit，24 bit 输入不会被静默降为 16 bit。AAC 是有损编码，转成 WAV/FLAC 无法恢复此前损失的信息，编码帧也可能带来末尾填充。

API 26 原生材质、实体设备扬声器/耳机听感、锁屏和功耗尚未完成验收。详见 [音频链路](../../docs/AUDIO_PIPELINE.md)、[录音与交互增强](../../docs/RECORDING_ENHANCEMENTS.md)及[发布前准备](../../docs/APPGALLERY_RELEASE.md)。
