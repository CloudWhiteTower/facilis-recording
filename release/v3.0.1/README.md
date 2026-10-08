# Facilis Recording 3.0.1

v3.0.1 是文档与代码维护版本，沿用 v3.0.0 的录音、转换和播放行为。版本号为 `3.0.1 / 3000001`，最低兼容与目标 SDK 仍为 API 24，支持手机和平板，提供 ARM64 与 x86_64 原生库。包名保持 `com.example.harmonyrecorder`，录音目录不变。

## 更新内容

- 更新根目录和工程 README，说明官方采集、编解码和播放接口与应用代码的分工。
- 使用 v3 真机录音页截图，更新当前下载入口和文档索引。
- 明确默认 MIC 采集、44.1/48 kHz 单声道、WAV 16/24 bit 和 FLAC 16 bit 等当前范围。
- 把纯净录音、设备能力探测和声学/性能对比列为后续计划，不将其描述为已实现或已验证音质提升。
- 将转码中的 AAC-LC 帧大小、解封装缓冲大小和 PCM 进度上限统一为命名常量；数值与算法保持原状。
- 发布打包同时核对源码与 Release HAP 的版本名称、版本号和包名，避免混用构建产物。
- 更新应用版本号，保留 v3.0.0 的发布附件与真机记录。

## 验证

2026-10-08 复验完成：

| 检查 | 结果 |
| --- | --- |
| Host 回归 | 185/185，覆盖模型、录音、文件仓库、页面操作、播放和转换服务 |
| 构建 | Debug、Release、ohosTest 均通过，包内版本为 3.0.1 / 3000001，Release 为 debug=false |
| 真实 MatePad Air（API 24） | 覆盖安装并启动成功；66/66，含 57 项单元、6 项转换和 3 项流式/取消检查 |
| 独立解码 | 本次转换用例的 51 个输入/输出文件完整解码成功；5 组无损比较和 15 组 AAC 尾部/延迟检查通过 |
| 原生库一致性 | ARM64 与 x86_64 的原生音频库 SHA-256 均与 v3.0.0 相同，固定参数命名整理未改变这些编译产物 |
| 发布准备 | 当前 README 与文档索引的本地链接核对通过；未发现应用崩溃日志 |

本次参数、信号统计和校验摘要见 [v3.0.1 验证记录](../../data/v3.0.1-validation/README.md)，不包含音频文件或设备标识。

v3.0.0 的真机 80/80、十分钟 WAV 实录、66 个文件独立解码及无损/AAC 边界检查仍保留在 [v3 验证记录](../../docs/V3_OPTIMIZATION.md)。这些是先前版本的结果，不计作 v3.0.1 新增长录音或麦克风质量测试。本次没有新增纯净采集、降噪、立体声、24-bit FLAC 或设备最大能力自动选择。

## 附件

附件见 [GitHub v3.0.1 发行版](https://github.com/CloudWhiteTower/facilis-recording/releases/tag/v3.0.1)，代码变更见 [PR #2](https://github.com/CloudWhiteTower/facilis-recording/pull/2)。

| 附件 | 用途 |
| --- | --- |
| `facilis-recording-v3.0.1-release-unsigned.hap` | 未签名 Release 模块，需要开发者自己的证书与 Profile 签名后安装 |
| `facilis-recording-v3.0.1-release-unsigned-app.zip` | 内含完整未签名 `.app`，供后续签名、分发使用 |
| `facilis-recording-v3.0.1-source.zip` | 与发布提交一致的源码、测试和文档 |
| `SHA256SUMS.txt` | 上述三个附件的 SHA-256 校验值 |

公开包不包含本地调试证书、设备 Profile 或用户录音。未签名 HAP 不能直接点击安装；GitHub 发布不代表已经上架 AppGallery。覆盖升级需兼容签名，应先导出重要录音，勿以卸载旧应用解决签名冲突。
