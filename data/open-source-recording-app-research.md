# 开源移动录音项目调研

检索日期：2026-09-02

目标：为鸿蒙原生手机录音软件寻找可参考的开源实现，同时横向了解 Android、iOS 和 Flutter 项目通常提供哪些功能、怎样组织录音链路。

## 先看哪些项目

如果目标是做一个普通的鸿蒙手机三方 App，建议按下面顺序阅读：

1. **[OpenHarmony SoundRecorder](https://github.com/openharmony/applications_sound_recorder)**：最接近完整产品，覆盖录音、播放、波形、标签、文件管理、数据库、服务卡片和手机/平板适配。但它是系统预置应用，依赖系统签名和系统级权限，适合学习架构与业务边界，不适合直接照搬全部工程。
2. **[OpenHarmony Recorder sample](https://github.com/openharmony/applications_app_samples/tree/master/code/SystemFeature/Media/Recorder)**：更小的 ArkTS 端到端示例，包含录音、暂停、播放、重命名、删除和公共媒体文件管理，适合先跑通 API 11 的基础链路。
3. **[Dimowner/AudioRecorder](https://github.com/Dimowner/AudioRecorder)**：Android 上功能较完整，适合研究格式、采样率、声道、波形、书签、导入、文件导出和架构演进。
4. **[Fossify Voice Recorder](https://github.com/FossifyOrg/Voice-Recorder)**：Android 上维护活跃、隐私导向的实用录音 App，适合观察权限、文件命名、音量可视化、主题和小组件等产品细节。
5. **[genedelisa/AVFoundationRecorder](https://github.com/genedelisa/AVFoundationRecorder)**：iOS 最小但完整的录音列表示例，适合快速理解 `AVAudioRecorder`、文件列表、播放、重命名和删除。
6. **[atacan/AudioRecorder](https://github.com/atacan/AudioRecorder)**：iOS/macOS 的可测试录音包，覆盖 `AVAudioEngine`、PCM 流、VAD（Voice Activity Detection，语音活动检测）、文件录音和依赖注入，适合研究复杂录音服务。
7. **[jaromiru/diktafon](https://github.com/jaromiru/diktafon)**：Flutter 的完整语音备忘录产品，包含分段录音、本地转写、摘要、搜索、导入导出和离线优先流程，适合观察“录音文件如何变成可检索内容”。
8. **[llfbandit/record](https://github.com/llfbandit/record)**：Flutter 录音插件，直接展示多平台抽象如何映射到 Android 的 `AudioRecord`/`MediaRecorder`、iOS 的 AVFoundation 以及不同格式和流式输出。

## 一、鸿蒙 / OpenHarmony 项目

### 1. OpenHarmony SoundRecorder：完整的手机/平板系统录音机

- 项目：[openharmony/applications_sound_recorder](https://github.com/openharmony/applications_sound_recorder)
- 平台：OpenHarmony；ArkTS + ArkUI Stage；手机、平板。
- 类型：完整系统预置应用，不是普通的三方 App 模板。
- 许可证：Apache-2.0，见仓库 [LICENSE](https://github.com/openharmony/applications_sound_recorder/blob/master/LICENSE)。
- 主要功能：
  - 开始、暂停、继续、停止录音；录音时长和波形展示。
  - 后台连续任务保活；通知栏和服务卡片控制。
  - 播放、暂停、进度拖动、倍速播放；`AVPlayer` + `AVSession`。
  - 录音文件列表、搜索、排序、多选、滑动操作、重命名、详情、删除、恢复最近删除。
  - 录音标签：录音中或播放中添加、编辑、跳转到关键位置。
  - 文件与数据库同步；默认支持 m4a、wav。
  - 2×1、2×2 服务卡片；手机/平板形态适配。
- 最值得看的目录：
  - `feature/recorder/src/main/ets/pages/RecordingPage.ets`：录音页面。
  - `feature/recorder/src/main/ets/pages/RecordPlayPage.ets`：播放页面。
  - `feature/recorder/src/main/ets/controller/RecordManager.ets`：录音控制和状态机。
  - `feature/recorder/src/main/ets/controller/PlayManager.ets`：播放控制、倍速和 AVSession 协同。
  - `feature/recorder/src/main/ets/components/`：波形、列表、侧边栏、标签等组件。
  - `feature/database_manager/`：录音、标签、最近删除数据表和 CRUD。
  - `feature/file_manager/`：文件监听、列表同步、删除和恢复。
  - `product/phone/`：应用入口、手机/平板布局、服务卡片。
  - `product/phone/src/main/module.json5`：设备形态、后台模式、权限和 Ability 配置。
- 关键限制：README 明确把它定义为系统预置应用 `com.ohos.soundrecorder`，需要系统签名证书；`KEEP_BACKGROUND_RUNNING`、`GET_TELEPHONY_STATE`、`FILE_ACCESS_MANAGER` 等权限也不是普通应用可以随意获得的。
- 对本项目的借鉴价值：**最高**。优先学习模块边界、录音状态机、文件/数据库一致性、波形采样和后台生命周期；实现普通三方 App 时应替换系统专属部分。

### 2. OpenHarmony applications_app_samples/Recorder：官方小型端到端示例

- 项目：[applications_app_samples/code/SystemFeature/Media/Recorder](https://github.com/openharmony/applications_app_samples/tree/master/code/SystemFeature/Media/Recorder)
- 平台：OpenHarmony；ArkTS；API version 11；标准系统设备。
- 类型：官方 sample，工程规模小，适合从头跟读。
- 许可证：请以仓库当前根目录和该 sample 的许可证文件为准；官方样例通常还需要检查依赖和 NOTICE。
- 主要功能：
  - 录音、暂停、停止。
  - 播放、暂停、继续播放。
  - 长按进入多选，批量重命名和删除。
  - 左滑显示重命名和删除操作。
  - 使用 `userFileManager` 管理音频文件。
- 值得看的源码：
  - `entry/src/main/ets/model/RecordModel.ts`：录音模型和流程。
  - `entry/src/main/ets/model/AudioModel.ts`：音频对象和媒体信息。
  - `entry/src/main/ets/model/MediaManager.ts`：媒体文件查询、重命名、删除。
  - `entry/src/main/ets/pages/RecordPage.ets`：录音界面。
  - `entry/src/main/ets/pages/Play.ets`：播放页面。
  - `entry/src/main/ets/common/AudioItem.ets`、`RenameDialog.ets`：列表和交互。
- API 线索：`@ohos.multimedia.media`、`@ohos.filemanagement.userFileManager`、`@ohos.abilityAccessCtrl`、`@ohos.data.preferences`。
- 对本项目的借鉴价值：**很高**。如果要先实现 MVP，这个项目比 SoundRecorder 更适合作为起点；它的限制是只面向标准系统，版本较旧，界面和工程结构需要按当前 SDK 调整。

### 3. OpenHarmony-SIG applications_recorder：较早的模块化录音机

- 项目：[openharmony-sig/applications_recorder](https://gitee.com/openharmony-sig/applications_recorder)
- 平台：OpenHarmony；ArkTS；README 标注 DevEco Studio for OpenHarmony、SDK API 10、标准系统。
- 类型：较早的完整录音机应用。
- 许可证：检索到的仓库 README 没有明确显示许可证；在复制代码前应打开仓库当前的 LICENSE、NOTICE 和子目录许可证确认。
- 主要功能：通过麦克风录音并播放。
- 架构线索：
  - `product`：不同业务形态和屏幕形态。
  - `feature`：公共特性、模型和控制逻辑。
  - `common`：基础能力和通用资源。
- 对本项目的借鉴价值：**中等**。适合对比早期 `product + feature + common` 的拆分方式，但 API、文件访问方式和工程模板都可能落后于当前 HarmonyOS NEXT。

### 4. Explore-In-HMOS-Wearable/how-to-record-voice：最小 ArkTS 录音 App

- 项目：[Explore-In-HMOS-Wearable/how-to-record-voice](https://github.com/Explore-In-HMOS-Wearable/how-to-record-voice)
- 平台：HarmonyOS；ArkTS + ArkUI；HarmonyOS SDK 5.1.0(18)。
- 类型：最小可运行示例，目标设备是 Huawei Watch 5，不是手机项目。
- 许可证：MIT。
- 主要功能：快速录音并保存语音片段。
- 源码结构：`services/AudioService.ets`、`services/RecorderService.ets`、`pages/Index.ets`、Ability 和备份 Ability。
- 依赖：`@kit.MediaKit`、`@kit.AbilityKit`、`@kit.CoreFileKit`、`@kit.BasicServicesKit`。
- 对本项目的借鉴价值：**高（仅限最小录音链路）**。适合先看权限、服务层和页面如何连接；不包含手机录音机需要的列表、数据库、标签、复杂后台管理。

### 5. Explore-In-HMOS-Wearable/how-to-build-media-creation-studio：较新的 AVRecorder + 播放示例

- 项目：[how-to-build-media-creation-studio](https://github.com/Explore-In-HMOS-Wearable/how-to-build-media-creation-studio)
- 平台：HarmonyOS；ArkTS + ArkUI；HarmonyOS SDK 6.0.1；目标是 Huawei Watch 5 和 DevEco Studio Simulator。
- 类型：穿戴设备 codelab，包含录音和媒体处理的组合示例。
- 许可证：MIT。
- 主要功能：
  - `media.AVRecorder` 以 AAC 编码、M4A 容器保存语音片段。
  - 使用 `AVPlayer` 播放沙箱中的录音。
  - 同一工程还演示 `AVImageGenerator` 和自定义媒体源加载，不属于录音核心。
- 对本项目的借鉴价值：**高（API 版本和 AVRecorder 配置参考）**。可以用来对照当前 `@kit.MediaKit` 写法，但要自己补充手机端文件管理、后台连续任务、波形和数据库。

### 6. 官方 ArkTS AVRecorder 文档：高层格式化录音

- 文档：[Using AVRecorder to Record Audio (ArkTS)](https://github.com/openharmony/docs/blob/master/en/application-dev/media/media/using-avrecorder-for-recording.md)
- 适合：要直接得到 m4a、mp3 等封装文件，先完成稳定 MVP。
- 核心模型：
  - 创建 `media.createAVRecorder()`。
  - 监听 `stateChange` 和 `error`。
  - 配置 `AVRecorderProfile`：码率、声道、编码、采样率、容器格式。
  - 通过 `fileIo.openSync()` 创建文件，把 `fd://<fd>` 传给 `AVRecorderConfig.url`。
  - 严格遵循 `idle/stopped -> prepared -> started <-> paused -> stopped -> released` 状态机。
  - 结束后 `stop()`、`reset()`/`release()`，最后关闭文件描述符。
- 关键权限和限制：需要 `ohos.permission.MICROPHONE`；后台录音需要连续任务；录音必须在前台启动，启动后才允许切入后台。
- 对本项目的借鉴价值：**最高**。普通鸿蒙录音 App 建议先采用这条链路，避免一开始就自行处理 PCM、编码和封装。

### 7. 官方 ArkTS AudioCapturer 文档：低层 PCM 录音

- 文档：[使用 AudioCapturer 开发音频录制功能](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/media/audio/using-audiocapturer-for-recording.md)
- 适合：需要实时音量、波形、VAD、音频分析、实时转写或自定义 DSP（Digital Signal Processing，数字信号处理）。
- 核心模型：
  - 使用 `@kit.AudioKit` 的 `audio.createAudioCapturer()`。
  - 配置采样率、声道、采样格式、原始编码和 `SourceType`。
  - 监听 `readData`，将 `ArrayBuffer` 分块写入 PCM 文件或送入处理管线。
  - 依次执行 `start()`、`stop()`、`release()`。
  - 回调中不要执行耗时任务；结束时务必释放音频资源。
- 重要区别：AudioCapturer 输出的是 PCM 数据，不会自动替你完成 m4a/wav 的完整封装。若需要公开可播放文件，要额外实现 WAV header、编码或改用 AVRecorder。
- 对本项目的借鉴价值：**高，但适合第二阶段**。可以用于实时波形和音频处理，不建议拿它作为最初的文件录音实现。

### 8. OpenHarmony multimedia_audio_standard：C/C++ 音频底层实现

- 项目：[openharmony/multimedia_audio_standard](https://github.com/openharmony/multimedia_audio_standard)
- 平台：OpenHarmony；C/C++ 音频框架实现。
- 类型：系统组件，不是录音 App。
- 内容：`AudioCapturer` 的创建、采样率、编码、采样格式、通道、输入设备和 PCM 采集等底层实现线索。
- 对本项目的借鉴价值：**中等到高**。只有在 ArkTS/Kit 层无法满足低延迟、特殊设备或自定义 DSP 时才值得深入；普通 App 不应直接从系统组件层开始。

## 二、Android 原生项目

### 9. Fossify Voice Recorder：实用型、隐私优先的 Android 录音机

- 项目：[FossifyOrg/Voice-Recorder](https://github.com/FossifyOrg/Voice-Recorder)
- 平台：Android；Kotlin 为主；Fossify 生态。
- 类型：完整用户应用，维护较活跃。
- 许可证：GPL-3.0。
- 主要功能：
  - 离线录音、无广告、无需网络权限。
  - 实时音量可视化。
  - 自定义主题、颜色、深色模式和字体。
  - 自定义录音文件命名格式。
  - 小组件、快速启动和文件分享。
  - 录音采样率设置、外部麦克风兼容性和常见录音文件问题修复。
- 值得观察：
  - Android 动态麦克风权限和隐私提示。
  - 录音列表与文件 URI/分享 Provider。
  - 长时间录音的状态恢复、取消确认和文件完整性处理。
  - 录音设置如何兼容不同 Android 设备。
- 对本项目的借鉴价值：**高（产品细节）**。它比较适合作为“简洁录音 App 应该做到什么程度”的参照；由于是 GPL，复制或改造代码前必须评估许可证义务。

### 10. Dimowner/AudioRecorder：格式和业务功能较完整

- 项目：[Dimowner/AudioRecorder](https://github.com/Dimowner/AudioRecorder)
- 平台：Android；Java/Kotlin；当前 README 同时记录旧架构和 Kotlin/Compose 重构计划。
- 类型：完整录音应用，Apache-2.0。
- 主要功能：
  - M4A、WAV、3GP 等格式。
  - 采样率、码率、单声道/立体声设置。
  - 录音和播放波形。
  - 播放、分享、导入、重命名、书签和主题。
  - 录音文件默认保存在应用私有目录，并支持导出到公共目录。
  - 新架构方向使用 Kotlin、Jetpack Compose、Room、ExoPlayer、Hilt，并增加单元测试覆盖。
- 值得观察：
  - `AudioRecordingService`：后台录音服务和生命周期。
  - `WavRecorderV2`：WAV 写入、时长和波形处理。
  - `FormatConfig`：不同格式的能力和参数约束。
  - 录音导入、损坏恢复、剩余空间检查和文件导出。
- 对本项目的借鉴价值：**很高**。如果需要对比“高层编码录音”和“自己写 WAV/PCM 录音”的差异，这个项目很有参考价值。

### 11. tuuhin/RecorderApp：功能较完整的现代 Android App

- 项目：[tuuhin/RecorderApp](https://github.com/tuuhin/RecorderApp)
- 平台：Android；Jetpack Compose；Android API 29+；MIT。
- 类型：完整用户应用。
- 主要功能：
  - AAC、AMR、Opus 等多种编码和质量设置。
  - 后台录音；通知栏控制。
  - 实时振幅可视化。
  - 内置播放器、进度拖动和播放控制。
  - 录音分类、重命名、删除、分享。
  - 编辑器：裁剪和剪切录音。
  - 书签，并可将书签导出为 CSV。
  - 两种小组件和快捷方式。
  - 可处理来电状态和可选的位置元数据。
- 架构线索：仓库拆分为 `app`、`core`、`data`、`feature`、`testing`，并使用 Room、ExoPlayer、Glance AppWidget、DataStore 等组件。
- 对本项目的借鉴价值：**很高（功能规划）**。它能帮助确定录音 App 从“能录”到“可用”通常会增加哪些模块。

### 12. exrivalis/AudioRecorder：小型 Kotlin + Room + 波形示例

- 项目：[exrivalis/AudioRecorder](https://github.com/exrivalis/AudioRecorder)
- 平台：Android；Kotlin；当前 README 标注为 work in progress。
- 类型：小型学习项目；页面显示仅有少量提交，未在项目页明确显示许可证。
- 主要功能：
  - 录音文件。
  - 实时波形，反映声音振幅。
  - Room 保存录音路径和元数据。
  - 播放速度控制。
  - 重命名、删除和搜索。
  - Material Design、BottomSheet 重命名交互。
- 对本项目的借鉴价值：**高（MVP 结构）**。适合学习“文件实体 + Room 元数据 + 波形 UI”的最小闭环；没有明确许可证时不要直接复制代码。

## 三、iOS 原生项目

### 13. genedelisa/AVFoundationRecorder：最小完整录音列表

- 项目：[genedelisa/AVFoundationRecorder](https://github.com/genedelisa/AVFoundationRecorder)
- 平台：iOS；Swift；AVFoundation；MIT。
- 类型：完整但简洁的示例 App。
- 主要功能：
  - `AVAudioRecorder` 录音。
  - 默认保存为 Apple Lossless，也可以改其他格式。
  - CollectionView 展示录音列表。
  - 单击、双击、长按分别承担播放、重命名、删除等交互。
- 对本项目的借鉴价值：**高（最小闭环）**。相当于“鸿蒙 AVRecorder + 录音文件列表”的 iOS 对照样本。

### 14. atacan/AudioRecorder：面向测试和实时处理的 Swift 录音包

- 项目：[atacan/AudioRecorder](https://github.com/atacan/AudioRecorder)
- 平台：iOS 16+、macOS 13+；Swift 5.7+；Swift Package Manager；MIT。
- 类型：可复用录音库，附带可运行的 Xcode examples，不是完整录音产品。
- 核心能力：
  - 权限请求、PCM16/Float32 实时流和文件录音。
  - VAD：检测语音结束并自动裁掉静音。
  - 单会话独占，防止多个录音会话争抢麦克风。
  - 明确的 lifecycle API；释放失败时保留部分文件并阻止不安全地开启新会话。
  - 依赖注入、测试替身、SwiftUI Preview 和单元测试。
- 值得看的源码：`AudioRecorderClient+LiveKey.swift`、`AudioRecorderClient+TestKey.swift`、`Examples/AudioRecorderExamples/`。
- 对本项目的借鉴价值：**很高（录音服务设计）**。特别适合借鉴录音资源独占、错误恢复、实时流和可测试接口，而不是只研究按钮点击后调用 API。

### 15. AudioKit + Cookbook：音频引擎和录音示例

- 框架：[AudioKit/AudioKit](https://github.com/AudioKit/AudioKit)
- 示例：[AudioKit/Cookbook](https://github.com/AudioKit/Cookbook)
- 平台：iOS、macOS、tvOS；Swift；MIT。
- 类型：音频处理框架和示例集合，不是单一录音 App。
- `Cookbook` 的 Recorder 示例使用：
  - `AudioEngine` 获取输入节点。
  - `NodeRecorder` 将输入录制到文件。
  - `AudioPlayer` 播放录音。
  - `Fader` 和 `Mixer` 管理输入、播放和静音关系。
  - `Conductor` 负责音频图，`Data` 保存状态，`View` 负责 SwiftUI 界面。
- 对本项目的借鉴价值：**中等到高**。适合需要监听 PCM、混音、效果器、返听或后续 DSP 的方案；普通语音备忘录不一定需要引入同等复杂度。

### 16. GRimAce11/WaveformKit：波形、FFT 和播放定位组件

- 项目：[GRimAce11/WaveformKit](https://github.com/GRimAce11/WaveformKit)
- 平台：iOS 17+、macOS 14+；SwiftUI；MIT。
- 类型：录音/播放可视化组件，不是完整 App。
- 主要能力：
  - 实时麦克风振幅。
  - 多种波形样式。
  - `AVAudioEngine`/音频处理 tap。
  - FFT（Fast Fourier Transform，快速傅里叶变换）频谱条。
  - 播放进度、点击跳转、标记和缓存。
  - 对长录音限制波形数组，避免内存无限增长。
- 对本项目的借鉴价值：**高（波形设计）**。重点学习“采样值如何降采样成固定数量显示柱”，而不是把每一个音频帧都直接绑定到 UI。

### 17. vasiliy-l/tutorial-ios-voice-recorder：最基础的 AVFoundation 流程

- 项目：[tutorial-ios-voice-recorder](https://github.com/vasiliy-l/tutorial-ios-voice-recorder)
- 平台：iOS；Swift；AVFoundation。
- 类型：教程级示例，录音后播放；项目页面未明确显示许可证。
- 对本项目的借鉴价值：**中等（入门）**。适合快速对照权限、`AVAudioRecorder` 初始化、录音和播放，不适合直接作为生产架构。

### 18. CodyBontecou/Vox.md：复杂的本地语音采集产品

- 项目：[CodyBontecou/Vox.md](https://github.com/CodyBontecou/vox.md)
- 平台：iOS、iPadOS、macOS、watchOS；Swift 5、SwiftUI；AGPL-3.0。
- 类型：多模态本地优先采集 App，录音只是其中一个功能。
- 主要功能：
  - 持久化录音、分段采集、后台音频。
  - App、键盘扩展、Share Extension、Widget、Live Activity、Apple Watch 协同。
  - 录音转写、历史记录、失败重试和本地队列。
  - App Group、共享容器和跨扩展同步。
- 值得看的源码：`PersistentRecorder.swift`、`CaptureComposerViewModel.swift`、`LiveActivityController.swift` 以及 `Packages/VoxboardShared/`。
- 对本项目的借鉴价值：**中等到高（高级产品能力）**。适合参考录音完成后如何进入“持久化 -> 转写 -> 搜索 -> 重试”的队列；对于单纯录音 App 来说功能明显超出 MVP。

## 四、Flutter / 跨平台项目

### 19. jaromiru/diktafon：离线优先语音备忘录

- 项目：[jaromiru/diktafon](https://github.com/jaromiru/diktafon)
- 平台：Flutter；Android、iOS、Linux；MIT 主许可证，仓库还包含依赖和模型的单独许可证说明。
- 类型：完整语音备忘录产品。
- 主要功能：
  - 按主题组织的 cassette/录音集合。
  - 一键录音、分段播放、跨分段 seek、彩色分段条。
  - 本地 Whisper 转写、Qwen 摘要、自动标题和多语言检测。
  - VAD、静音裁剪、低频噪声处理；原始音频不被覆盖。
  - 本地搜索、导入导出、主题和录音重试。
  - `flutter analyze`、单元测试、集成测试。
- 对本项目的借鉴价值：**高（录音后的内容产品）**。它提示录音软件的差异化功能不一定来自录音 API，也可以来自组织、检索、转写和离线可靠性。

### 20. llfbandit/record：多平台录音抽象层

- 项目：[llfbandit/record](https://github.com/llfbandit/record)
- 平台：Flutter；Android、iOS、Web、Windows、macOS、Linux。
- 类型：录音插件，不是完整 App；各平台实现分别位于 `record_android`、`record_ios`、`record_windows`、`record_macos`、`record_linux` 等目录。
- 底层映射：
  - Android：`AudioRecord`、`MediaCodec` 或 `MediaRecorder`。
  - iOS/macOS：AVFoundation。
  - Windows：MediaFoundation。
  - Linux：`parecord`、`pactl`、`ffmpeg`。
- 暴露能力：
  - 文件录音和 PCM/AAC 流。
  - 暂停、继续、停止、取消。
  - dBFS 振幅、权限检查、声道数、设备选择。
  - AAC、AMR、Opus、WAV、FLAC、PCM16 等格式，实际支持依赖平台。
  - Android/iOS 后台录音配置说明。
- 对本项目的借鉴价值：**很高（平台抽象和能力矩阵）**。尤其适合比较“统一业务接口”和“平台差异适配”的边界。

### 21. abraralidev/flutter_voice_recorder：简单的 Android/iOS 插件

- 项目：[flutter_voice_recorder](https://github.com/abraralidev/flutter_voice_recorder)
- 平台：Flutter；Android + iOS；MIT。
- 类型：插件和示例，不是完整录音产品。
- API：权限检查、初始化、开始、暂停、继续、停止；支持 AAC/WAV；读取文件路径、时长、状态和平均/峰值功率。
- 对本项目的借鉴价值：**中等（API 设计）**。适合观察跨平台插件把录音状态和 metering（电平计量）统一成什么样的接口。

### 22. abdallahyassein-dev/voice_note_kit：带波形和播放 UI 的 Flutter 示例

- 项目：[voice_note_kit](https://github.com/abdallahyassein-dev/voice_note_kit)
- 平台：Flutter；主要面向移动端；许可证需以当前仓库 LICENSE 为准。
- 类型：语音录音和播放示例/组件集合。
- 主要功能：
  - 本地录音和播放。
  - `just_waveform` 动态波形。
  - `permission_handler` 权限管理。
  - 播放、暂停、继续、停止和倍速播放。
  - 多种音频播放器样式。
- 对本项目的借鉴价值：**中等到高（UI 交互）**。适合参考录音列表卡片、播放器状态、波形和权限处理如何组合。

## 五、平台官方实现对照

### 录音 API 的两条路线

| 目标 | 鸿蒙 | Android | iOS | 适用场景 |
|---|---|---|---|---|
| 直接得到封装文件 | `AVRecorder` | `MediaRecorder` | `AVAudioRecorder` | 普通语音备忘录、采访、会议录音 |
| 获取原始 PCM/实时音频流 | `AudioCapturer` / OHAudio | `AudioRecord` | `AVAudioEngine` | 实时波形、VAD、转写、降噪、DSP、返听 |

官方参考：

- 鸿蒙：[AVRecorder 音频录制指导](https://github.com/openharmony/docs/blob/master/en/application-dev/media/media/using-avrecorder-for-recording.md)、[AudioCapturer 音频录制指导](https://github.com/openharmony/docs/blob/master/zh-cn/application-dev/media/audio/using-audiocapturer-for-recording.md)。
- Android：[MediaRecorder overview](https://developer.android.com/media/platform/mediarecorder)、[AudioRecord API](https://developer.android.com/reference/android/media/AudioRecord)。
- iOS：[AVAudioRecorder](https://developer.apple.com/documentation/avfaudio/avaudiorecorder)、[AVAudioSession](https://developer.apple.com/documentation/avfaudio/avaudiosession)。

### 后台录音的关键差异

- 鸿蒙：录音需要先在前台启动；持续/后台录音要申请连续任务，模块中配置 `audioRecording`，并正确处理录音与系统音频焦点。
- Android：通常需要 `RECORD_AUDIO`；Android 9 以后后台访问麦克风受限，长时间录音需要前台服务；较新 target 还要声明 `FOREGROUND_SERVICE_MICROPHONE` 和 `foregroundServiceType="microphone"`。
- iOS：需要配置 `AVAudioSession` 的 `record` 或 `playAndRecord` 类别，并在 `UIBackgroundModes` 中启用 `audio` 才能在锁屏/切后台后持续录音。

## 六、从这些项目归纳出的通用录音架构

推荐把录音 App 拆成下面几层，而不是把所有代码放在录音页面里：

```text
权限与设备检查
        |
        v
录音会话层 ── create/prepare/start/pause/resume/stop/release
        |
        +── 文件写入层 ── 沙箱或公共目录、临时文件、原子完成
        |
        +── 实时指标层 ── 时长、电平、波形降采样、VAD
        |
        +── 播放层 ── 播放状态、seek、倍速、音频焦点/AVSession
        |
        +── 记录索引层 ── 文件路径、时长、格式、大小、标题、标签
        |
        +── 产品功能层 ── 搜索、分类、分享、重命名、删除/恢复、转写
```

应重点借鉴以下设计：

1. **状态机必须显式化**：至少区分 `idle`、`prepared`、`recording`、`paused`、`stopped`、`released`，UI 按状态决定按钮，而不是让每个按钮自行猜测当前状态。
2. **文件是事实来源，数据库是索引**：先把录音文件安全落盘，再写入数据库；应用启动时扫描文件并修复数据库，避免数据库有记录但文件不存在。
3. **录音和 UI 解耦**：录音服务负责麦克风、文件描述符、状态和异常；页面只订阅状态。这样切后台、旋转屏幕或切换页面时不会销毁录音会话。
4. **波形不要保存每一帧**：对一段时间内的振幅做 RMS/峰值采样，再降采样成固定数量的柱；长录音需要限制内存和缓存大小。
5. **高层录音优先，PCM 后置**：MVP 先用 `AVRecorder` 生成 m4a/wav；只有实时转写、VAD、特殊音效或低延迟需求出现时，再引入 `AudioCapturer`/PCM 管线。
6. **后台录音是平台能力，不是 Timer 保活**：必须按平台声明前台服务、连续任务或后台音频模式，并处理来电、耳机拔出、其他应用抢占音频焦点等中断。
7. **结束录音要做完整性处理**：停止编码器、等待文件封装完成、关闭 fd、读取最终时长和大小，再提交数据库；异常时保留临时文件并提供恢复或清理策略。
8. **许可证要逐项目核验**：MIT/Apache-2.0、GPL-3.0、AGPL-3.0 的再分发义务不同；没有明确许可证的仓库只能学习思路，不能默认允许复制代码。

## 七、对本鸿蒙项目的落地建议

### MVP 阶段

- 使用 ArkTS + ArkUI Stage。
- 使用 `AVRecorder` 录制 AAC/M4A，先只支持麦克风、开始/暂停/继续/停止、播放和删除。
- 使用应用沙箱目录保存文件；如果要让用户在系统文件管理器中看到，再单独设计公共目录导出流程。
- 建立一个 `RecorderService`/`RecordManager`，页面只消费状态和事件。
- 用 Preferences 或轻量数据库保存标题、创建时间、时长、文件路径、大小和状态。
- 第一版不做自定义 PCM 编码、不做通话录音、不做系统音频录制。

### 第二阶段

- 加入实时电平和固定内存的波形数据。
- 加入 `AVSession`、通知和连续任务，验证锁屏、切后台、来电、耳机拔出和其他 App 播放时的行为。
- 增加重命名、搜索、排序、分享和最近删除恢复。
- 用标签表保存 `recordId + timestamp + title`，支持录音中和播放中跳转。

### 第三阶段

- 评估 `AudioCapturer`/OHAudio 做 PCM 流、VAD、实时转写或自定义 DSP。
- 增加设备路由、外接麦克风、回声消除、降噪和音质配置。
- 如果要做会议录音产品，再引入本地转写、全文搜索、摘要和失败可重试队列。

## 八、许可证和可复制性速查

| 项目 | 页面标注许可证 | 复制代码前的注意点 |
|---|---|---|
| OpenHarmony SoundRecorder | Apache-2.0 | 还要检查系统专属权限、签名、依赖和 `open_source` 材料 |
| Watch voice samples | MIT | 可以作为较宽松参考，但要检查依赖许可证 |
| Fossify Voice Recorder | GPL-3.0 | 修改并分发衍生作品时需要认真评估 GPL 义务 |
| Dimowner/AudioRecorder | Apache-2.0 | 注意仓库内第三方库和不同版本架构 |
| RecorderApp | MIT | 检查依赖和资源文件的单独许可证 |
| AVFoundationRecorder | MIT | 简单清晰，适合直接学习文件列表闭环 |
| AudioRecorderClient | MIT | 检查其改编自其他项目的部分及依赖 |
| AudioKit / Cookbook | MIT | 框架、示例和第三方音频资源分别核验 |
| WaveformKit | MIT | 组件可参考，不能假定所有示例资源同许可证 |
| Diktafon | MIT 主许可证 | Whisper、Qwen、VAD、模型、字体等有额外许可证 |
| llfbandit/record | 子包各自带许可证文件 | 按实际使用的 platform package 逐一核验 |
| 无明确 LICENSE 的项目 | 未知 | 只看思路，不复制、重发或合并源码 |
