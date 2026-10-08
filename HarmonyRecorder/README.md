# Facilis Recording

HarmonyOS Stage ArkTS 本地录音应用，当前版本为 **3.0.1 / 3000001**，最低兼容与目标 SDK 均为 **6.1.1（API 24）**。它支持选择质量、录制、暂停/继续、本地保存、管理、播放与格式转换。

v3.0.1 整理 README、官方音频接口分工和转码固定参数名称，录音参数、编解码器、缓冲大小与调度行为沿用 v3.0.0。此次复验见 [v3.0.1 发布说明](../release/v3.0.1/README.md)。

## 当前功能

- WAV：可选 44.1/48 kHz、16/24-bit、Mono。使用 `AudioCapturer` 捕获 PCM，并在应用侧写入标准 RIFF/WAV header。
- AAC/M4A：可选 44.1/48 kHz、Mono，提供 128/256 kbps 码率。使用 `AVRecorder` 完成系统编码与封装。
- FLAC：可选 44.1/48 kHz、16-bit、Mono。复用 PCM 采集，交由系统 Native AVCodec 与 AVMuxer 编码、封装，通过异步 N-API 桥接。
- 麦克风权限：首次点击开始录音时请求 `ohos.permission.MICROPHONE`。
- 录音状态机：`IDLE → RECORDING → PAUSED → RECORDING → STOPPED`。
- 存储：文件保存在应用私有目录 `files/recordings/`，按时间命名，冲突时增加后缀；同一时刻的新录音也不会覆盖前一段。`recordings.index` 保存相对文件名和必要元数据，运行时按当前沙箱重建路径，并以真实容器参数校准信息。
- 播放：使用 `AVPlayer`，支持播放、暂停、当前进度、总时长和 Seek。
- 波形与大小：WAV/FLAC 根据 PCM 数据计算滚动 RMS；M4A 使用 `AVRecorder.getAudioCapturerMaxAmplitude()` 获取真实录制振幅。Canvas 将振幅包络绘为连续曲线，单调三次插值保留采样极值；暂停冻结，停止清空。三种格式均显示录制中的文件大小。
- 后台任务：声明 `ohos.permission.KEEP_BACKGROUND_RUNNING` 与 `audioRecording` 模式。开始/继续采集时申请长时任务；暂停、保存、放弃及异常收尾时释放。系统取消任务后停止采集并尝试保存。
- 文件管理：支持搜索、多选、重命名、最近删除及批量恢复/永久删除；文件与索引更新包含事务恢复。WAV 可导出真实 data chunk 的 raw PCM，原始录音和 PCM 可调用系统分享面板。
- 本地保存：通过系统文件选择器保存原件到指定位置；内部路径校验、原子索引和真实容器参数检查共同维护资料库，损坏文件可备份和手动清理。
- 应用内转换：更多菜单支持 WAV/FLAC/M4A 转换、进度和取消，保留原件；范围为 44.1/48 kHz 单声道，FLAC 目标限 16 bit。参数、保真条件和验证见[音频链路说明](../docs/AUDIO_PIPELINE.md)。
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
├── services/     # 权限、录音、播放、导出、分享、格式转换
└── utils/        # 容器校验、时间、响应式、波形与动效
```

录音底层不会由页面直接调用：

```text
RecorderPage → RecordingService → AVRecorder (M4A)
                              └→ AudioCapturer → WAV header + PCM (WAV)
                                              └→ Native AVCodec + AVMuxer (FLAC)

RecordingsPage → RecordingRepository → files/recordings/
PlayerPage → PlaybackService → AVPlayer
更多菜单 → AudioConversionService → Native 解码/编码 → RecordingRepository
```

`entry/src/main/cpp/` 提供 FLAC 录制与音频转换的异步 N-API 桥。当前 Release 同时包含 arm64-v8a 和 x86_64 原生库；v3 的实际设备结果见[优化与验证](../docs/V3_OPTIMIZATION.md)。

### 音频接口分工

AAC/FLAC 编解码由系统 `AudioCodec` 执行，转换使用 `AVDemuxer` 解封装和 `AVMuxer` 封装。Native 层负责缓冲调度、PCM 表示转换、AAC 尾帧和预热样点处理、FLAC 元数据及文件收尾；没有自研压缩编解码器。`pcm_conversion.h` 仅改变 PCM 的存储表示，保留样点顺序、采样率和声道。

当前采集使用 `SOURCE_TYPE_MIC`；`getStreamInfo()` 用于核对已经创建的采集流，不等同于枚举设备最大采集能力。`SOURCE_TYPE_UNPROCESSED` 纯净模式、设备能力自动选择及应用级降噪尚未实现。普通/纯净模式、同步/异步调度的效果需要在同一设备与声源条件下比较，当前不声明音质、速度或功耗提升比例。

## 构建与运行

本目录是 DevEco 工程根目录。推荐使用 DevEco CLI：

```powershell
devecocli build
devecocli build --product default --build-mode release
devecocli device list
devecocli run --module entry --device <serial>
```

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

公开仓库不包含签名材料。首次部署前，请在 DevEco Studio 中为自己的应用包名配置调试签名；正式发布则按 AGC 当前流程配置发布签名。[v3.0.1 附件](../release/v3.0.1/README.md)中的 HAP 与 APP 均未签名，不能直接作为已签名安装包使用。

## 测试

### Host 自动化检查

以下命令在仓库根目录运行，即包含 `HarmonyRecorder/` 和 `scripts/` 的目录。需要 Node.js，以及 DevEco Studio 自带的 TypeScript 编译器；将占位路径替换为自己的安装目录：

```powershell
$env:FACILIS_TYPESCRIPT = '<DevEco Studio 安装目录>\tools\ohpm\node_modules\typescript\lib\typescript.js'
node scripts/test-ui-model.cjs
node scripts/test-recording-service.cjs
node scripts/test-recording-repository.cjs
node scripts/test-recording-actions.cjs
node scripts/test-playback-service.cjs
node scripts/test-audio-conversion-service.cjs
```

所有脚本也支持将编译器路径作为第一个参数，参数优先于环境变量。例如：

```powershell
node scripts/test-playback-service.cjs '<DevEco Studio 安装目录>\tools\ohpm\node_modules\typescript\lib\typescript.js'
```

2026-10-08 v3 复验结果：

| 入口 | 覆盖范围 | 结果 |
| --- | --- | --- |
| [test-ui-model.cjs](../scripts/test-ui-model.cjs) | 同步模型与主题资源检查；含格式配置、音频头、PCM 振幅、动效、缓存曲线等价性和横竖屏空间预算 | 59/59 |
| [test-recording-service.cjs](../scripts/test-recording-service.cjs) | 两小时加速 PCM 流、背压、短写入、RIFF 边界、暂停继续、中途检查点、队列合并、采集停滞及实际流参数/失败收尾 | 22/22 |
| [test-recording-repository.cjs](../scripts/test-recording-repository.cjs) | 文件/索引事务、路径、损坏文件、容器参数、部分读写；批量扫描次数、期间新录音保存及批次刷新失败 | 37/37 |
| [test-recording-actions.cjs](../scripts/test-recording-actions.cjs) | 真实页面方法的确认顺序、重复操作、删除保护、失败恢复、正常取消确认框及异步批次锁 | 13/13 |
| [test-playback-service.cjs](../scripts/test-playback-service.cjs) | 加载替换、旧回调隔离、释放、音频打断、Seek、准备/控制超时与界面回调异常 | 37/37 |
| [test-audio-conversion-service.cjs](../scripts/test-audio-conversion-service.cjs) | 参数、进度/取消、资源释放、登记失败保护，以及单调进度、重复通知抑制和服务复用 | 17/17 |

合计 185/185。真实容器参数可通过 `node scripts/inspect-audio-files.cjs <typescript.js> <audio-file...>` 检查；该检查不会完整解码音频。独立流式解码与无损比较使用 `node scripts/verify-audio-streams.cjs <fixture-directory>`，需要本机 FFmpeg。

脚本失败时返回非零退出码。Host 检查通过源码转译执行逻辑，不替代 ArkTS 编译、ArkUI 渲染或设备音频测试。其中“两小时”是加速数据流模拟，并非两小时设备录音；FLAC 桥接的调用顺序测试也不验证系统编码器生成的音频文件。

另外，生产转换链路的 PCM 函数检查 5/5：遍历全部 16/24-bit 取值的 F32/S32 往返，覆盖满幅舍入、异常输入、块尾部与缓冲复用。Linux/WSL 中可在仓库根目录编译运行，无需 HarmonyOS 运行时：

```sh
mkdir -p .codex
c++ -std=c++17 -O2 -Wall -Wextra -Werror -fsanitize=address,undefined -fno-omit-frame-pointer scripts/test-native-pcm.cpp -o .codex/test-native-pcm
./.codex/test-native-pcm
```

独立报告工具检查 7/7，需要 FFmpeg/ffprobe 在 PATH 中；生成的临时夹具在检查结束后清理，包含 AAC 尾部截断与额外延迟样点的检出：

```text
node scripts/test-audio-stream-validator.cjs
```

这两组检查分别验证软件表示精度和报告工具，不替代真机编码器或麦克风质量测试。

### HarmonyOS 测试模块

在 `HarmonyRecorder/` 工程目录构建测试模块：

```powershell
devecocli build --modules entry@ohosTest
```

该命令只构建测试包，不执行设备测试。默认测试模块执行单元用例，原生 FLAC、转换和文件播放集成测试按需启用。设备执行结果见[音频验证记录](../data/audio-functional-validation/README.md)和[录音增强记录](../docs/RECORDING_ENHANCEMENTS.md)。

## 验证状态

2026-10-08 v3.0.1：Host 185/185、Debug/Release/ohosTest 构建通过。真实 MatePad Air 覆盖升级后，单元、转换与流式/取消检查 66/66；51 个转换夹具独立解码、5 组无损比较和 15 组 AAC 尾部/延迟检查通过。两个 ABI 的原生音频库与 v3.0.0 SHA-256 相同。本次未重复麦克风长录音或界面验收，详细结果见 [v3.0.1 验证](../data/v3.0.1-validation/README.md)。

2026-10-08 v3.0.0：Host 185/185，PCM 精度/内存检查 5/5，独立报告工具检查 7/7，Debug、Release、测试包构建通过，版本为 3.0.0 / 3000000。最终 Release 已覆盖安装到真实 MatePad Air，回归 80/80，含原生双向滑动、录音页及播放器横竖屏、三种格式录制/播放、转换和 AAC 边界用例；十分钟 WAV 实录及 66 个文件的独立解码通过。修复满输入队列查询错误、AAC 不完整尾帧和解码预热帧；已有录音保留，详见 [v3 验证记录](../docs/V3_OPTIMIZATION.md)。

2026-09-27 功能回归：Debug、Release、ohosTest 构建通过，Host 166/166；API 24 平板模拟器 67/67（52 单元、10 FLAC 集成、5 转换集成）通过。15 个文件（11 个转换输出、4 个输入样本）由 FFmpeg 完整解码，5 组 PCM 逐样点一致。WAV、FLAC、M4A 既有录音的隔离副本均通过头/中/尾服务播放；系统文件选择器保存的 FLAC 副本与原件 SHA-256 一致。

2026-09-28 v2.0.0 Release 构建通过；包内版本为 2.0.0 / 2000000，`debug=false`，最低兼容和目标版本仍为 API 24，支持 phone/tablet。

手机与平板布局、最近删除和 30:57.62 WAV 模拟器实录见[录音增强记录](../docs/RECORDING_ENHANCEMENTS.md)。最新音频回归复用了该长录样本，没有重新录制 30 分钟。API 26 原生材质、实体设备听感、锁屏策略、长时间转换和功耗尚未验证；模拟器播放推进不等同于听感验收。

版本汇总见 [v2 实施记录](../docs/V2_IMPLEMENTATION.md)，历史需求验收见 [ACCEPTANCE.md](ACCEPTANCE.md)，应用市场准备见 [AppGallery 发布清单](../docs/APPGALLERY_RELEASE.md)。

## 暂未实现

未实现 DSP、纯净采集模式、设备最大能力自动探测、手动音频输入设备选择、重采样、声道混合、24-bit FLAC、RF64 或自动分卷。当前转换限 WAV/FLAC/M4A、44.1/48 kHz 和单声道；AAC 是有损编码，不能通过转成 WAV/FLAC 恢复已丢失的信息。完整边界见[音频链路说明](../docs/AUDIO_PIPELINE.md)。
