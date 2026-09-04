# Facilis Recording 验收说明

本文件按 `../data/HarmonyOS 简易录音软件 Demo 需求文档.md` 核对当前 Demo。状态分为：

- **已实现并构建**：已有对应 ArkTS 实现，且已通过 HAP 构建。
- **已在模拟器验证**：在已授权的 Pura 90 模拟器完成了对应端到端操作。
- **后续硬件回归**：不影响本次 Demo 验收，但需要真实外接设备时再执行。

| 需求 | 当前实现 | 证据与状态 |
| --- | --- | --- |
| 麦克风权限 | `module.json5` 声明 `ohos.permission.MICROPHONE`；首次点击录音由 `PermissionService` 请求 | 已在模拟器验证：系统授权弹窗出现，用户已手动允许 |
| 开始、暂停、继续、停止与计时 | `RecordingService` 维护 `IDLE → RECORDING → PAUSED → RECORDING → STOPPED`；`RecorderPage` 每 250 ms 更新时长 | 已在模拟器验证：WAV 显示 `Recording`、`Paused`、恢复后的递增计时与 `已保存` |
| WAV | `AudioCapturer` 采集可选 44.1/48 kHz、16/24-bit、Mono PCM，`WaveFileUtils` 写入并回填 44 字节 RIFF/WAV header | 48 kHz / 16-bit 已在模拟器完成录音与回放验收；新增组合已通过配置、WAV header、时长和 24-bit RMS 测试代码覆盖，等待用户在界面逐项抽查 |
| AAC / M4A | `AVRecorder` 使用 AAC-LC / M4A，采样率可选 44.1/48 kHz，码率可选 128/256 kbps | 48 kHz 下的格式切换、录制、停止保存、列表与回放已验证；新增 44.1 kHz 入口等待用户抽查 |
| M4A 实时波形 | `AVRecorder.getAudioCapturerMaxAmplitude()` 每 120 ms 读取上一采样区间的真实最大振幅，归一化后复用录制波形组件；暂停、停止和释放前均停止轮询 | 已由用户完成录制、波形与回放验收 |
| WAV 实时波形与文件大小 | `AudioCapturer.readData` 按当前 16/24-bit PCM 格式计算 RMS；有界异步写入队列统计已写字节数 | 16-bit 已在模拟器观察波形和实时大小，且保存后的文件可回放；24-bit 波形计算已通过设备单元测试 |
| 文件管理与分享 | `RecordingRepository` 实现重命名、最近删除、恢复、永久删除；`ShareService` 使用系统 Share Kit；WAV 可导出 raw PCM | 已实现并构建；用户已完成相关手工功能验收 |
| 深浅色与系统弹层 | 自定义橙色配色与应用级 `setColorMode()` 同步；录音质量使用原生 `Select` 并显式设置菜单背景、文字和选中态 | 用户已完成第一阶段最终验收 |
| 自动命名与本地保存 | `RecordingRepository` 保存到 `files/recordings/`，按 `Recording_YYYYMMDD_HHMMSS` 命名，并避免同秒冲突 | 已在模拟器验证 WAV 文件命名、保存及列表显示 |
| 重启后的录音列表 | `recordings.index` 持久化格式和时长；启动列表时扫描目录补全索引 | 已在模拟器重新拉起应用后验证历史录音仍显示 |
| 播放、暂停、Seek、时间显示 | `PlaybackService` 通过 `AVPlayer` 的 `stateChange`、`timeUpdate`、`durationUpdate` 管理播放；`PlayerPage` 提供 Slider | 已在模拟器验证 WAV 播放、暂停和进度；最终保存文件的实际声音回放已由用户确认 |
| 外接 DJI Mic 2 | 两种录制路径都请求系统 MIC 输入；应用不选择或控制具体硬件 | 代码符合系统路由设计；未连接实体 DJI Mic 2，保留为后续真机回归项 |
| 非目标功能 | 未加入 FLAC、DSP、设备控制、后台长时录音或通用 M4A/WAV 互转 | 符合当前范围 |

## 已完成的构建与部署验证

- 2026-09-03 `devecocli build`：成功；构建流程执行了 `SignHap`，生成已签名主应用 HAP。
- 2026-09-03 `devecocli build --modules entry@ohosTest`：成功；测试 HAP 也完成签名打包。唯一警告是测试资源与主资源均声明 `start_window_background`，不影响构建成功。
- 2026-09-03 `devecocli run --module entry --device 127.0.0.1:5555 --skip-build`：新版成功安装并启动于 Pura 90（phone）。
- 2026-09-03 `devecocli run --module entry --device 127.0.0.1:5557 --skip-build`：新版成功安装并启动于 MatePad Pro 13（tablet）。
- 两台模拟器均未发现 `com.example.harmonyrecorder` 的崩溃日志或最近 10 分钟 E 级日志。
- 2026-09-04 在 Pura 90 执行 `OpenHarmonyTestRunner`：共 19 项，`Pass: 19, Failure: 0, Error: 0`。覆盖可选采样率/位深、16/24-bit WAV header 与时长、16/24-bit 波形 RMS、文件大小、主题及其他纯逻辑。
- M4A 波形新增 `WaveformUtils.normalizeAmplitude()` 测试，兼容 `[0, 1]` 与常见 PCM 振幅量级的返回值。
- 2026-09-04 `devecocli build --product default --build-mode release` 成功生成 Release APP。

## 最终验收与后续硬件回归

`Pura 90` phone 模拟器在线，序列号为 `127.0.0.1:5555`。麦克风权限已由用户在系统弹窗中手动授予。本机调试签名仅用于验收，签名配置和材料不进入公开仓库；本文不记录任何密钥、证书、Profile 或密码内容。

2026-09-03，用户完成最终手工验收并确认 Demo 可行、制作成功：电脑本地麦克风经模拟器传入应用，保存后的录音能够回放出实际声音。运行日志同时证明 `AudioCapturer` 已按 48 kHz / 单声道 / 16-bit PCM 成功启动，且采集流出现非静音帧。

2026-09-04，用户确认第一阶段验收合格。本次核心 Demo 验收至此完成。若后续接入 DJI Mic 2，只需在真机上将其设为系统当前输入，然后分别以 WAV 和 M4A 录制、保存和播放一次；应用无需新增配对、增益或设备控制逻辑。
