# Facilis Recording

HarmonyOS Stage ArkTS 本地录音应用。它实现了选择质量 → 开始 → 暂停/继续 → 保存或放弃 → 本地管理 → 播放/Seek 的完整闭环。

## 当前功能

- WAV：可选 44.1/48 kHz、16/24-bit、Mono。使用 `AudioCapturer` 捕获 PCM，并在应用侧写入标准 RIFF/WAV header。
- AAC/M4A：可选 44.1/48 kHz、Mono，提供 128/256 kbps 码率。使用 `AVRecorder` 完成系统编码与封装。
- 麦克风权限：首次点击开始录音时请求 `ohos.permission.MICROPHONE`。
- 录音状态机：`IDLE → RECORDING → PAUSED → RECORDING → STOPPED`。
- 存储：文件保存在应用私有目录 `files/recordings/`，以 `Recording_YYYYMMDD_HHMMSS.{wav|m4a}` 命名；同目录中的 `recordings.index` 保存时长和格式元数据。
- 播放：使用 `AVPlayer`，支持播放、暂停、当前进度、总时长和 Seek。
- 波形与大小：WAV 根据当前 16/24-bit PCM 数据计算滚动 RMS；M4A 使用 `AVRecorder.getAudioCapturerMaxAmplitude()` 获取真实录制振幅。两种格式均显示录制中的文件大小。
- 文件管理：支持重命名、最近删除、恢复、永久删除；WAV 可实际导出 raw PCM，原始录音和 PCM 可调用系统分享面板。
- 外观：橙色主色，支持应用内浅色/深色切换；切换时同步应用级 `setColorMode()`，系统菜单与弹窗跟随当前模式。
- 布局：使用 ArkUI 原生组件，支持 phone/tablet 的 600 vp 响应式布局。
- 音频输入：始终请求系统默认 MIC 输入。连接并由系统路由 DJI Mic 2 后，应用不会绑定或控制特定设备。

## 工程结构

```text
entry/src/main/ets/
├── components/   # 录制波形
├── models/       # RecordingConfig、RecordingInfo、状态和格式
├── pages/        # RecorderPage、RecordingsPage、PlayerPage、Index
├── repository/   # 私有目录、轻量索引、最近删除
├── services/     # 权限、录音、播放、导出、分享
└── utils/        # 时间、文件大小、响应式、WAV、波形
```

录音底层不会由页面直接调用：

```text
RecorderPage → RecordingService → AVRecorder (M4A)
                              └→ AudioCapturer + WAV header (WAV)

RecordingsPage → RecordingRepository → files/recordings/
PlayerPage → PlaybackService → AVPlayer
```

## 构建与运行

本目录是 DevEco 工程根目录。推荐使用 DevEco CLI：

```powershell
devecocli build
devecocli device list
devecocli run --module entry --device <serial>
```

测试模块可单独构建：

```powershell
devecocli build --modules entry@ohosTest
devecocli build --product default --build-mode release
```

其中覆盖计时格式、自动文件名、可选 WAV/AAC 配置、16/24-bit WAV PCM 头字段和时长、文件大小格式、PCM 波形 RMS 以及 M4A 振幅归一化。

本机若全局代理包含 `ALL_PROXY=socks5://...`，`ohpm` 可能无法安装依赖。可以只对当前 PowerShell 构建进程清除代理变量，不需要改动系统设置：

```powershell
$env:ALL_PROXY = $null
$env:HTTP_PROXY = $null
$env:HTTPS_PROXY = $null
$env:NO_PROXY = $null
devecocli build
```

若需要使用本地模拟器，许可接受必须由用户在交互式终端自行完成：

```powershell
devecocli emulator license accept
devecocli emulator start 'Pura 90'
```

公开仓库不包含签名材料。首次部署前，请在 DevEco Studio 中为自己的应用包名配置调试签名；正式发布则使用 AGC 云管理签名或自己的发布证书和 Release Profile。

## 验证状态

- `devecocli build`：通过。
- `devecocli build --modules entry@ohosTest`：通过；Pura 90 设备测试 19/19 通过。
- `devecocli build --product default --build-mode release`：通过，成功生成 Release APP。
- WAV、M4A、实时波形、保存、播放和文件管理均已由用户在模拟器中验收。
- Pura 90 与 MatePad Pro 13 均完成部署，未发现该应用的崩溃日志。

逐项需求对照与设备验收证据见 [ACCEPTANCE.md](ACCEPTANCE.md)。正式发布所需材料见 [AppGallery 发布清单](../docs/APPGALLERY_RELEASE.md)。

## 暂未实现

FLAC、DSP、设备选择、后台长时录音和通用 M4A/WAV 互转均保留给后续版本；当前不会通过仅改扩展名伪造音频转码。
