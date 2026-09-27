# HarmonyOS 简易录音软件 Demo 需求文档

## 1. 项目目标

开发一个运行于 HarmonyOS 的本地录音 Demo。

Demo 围绕本地录音、暂停、保存与回放的基本流程设计，暂不包含外部设备控制、DSP 或复杂音频编辑等高级功能。

当前版本只需要验证以下核心链路：

```text
选择录音格式
    ↓
开始录音
    ↓
暂停 / 继续
    ↓
停止录音
    ↓
保存本地文件
    ↓
在录音列表查看
    ↓
播放录音
```

### Demo 成功标准

满足以下条件即认为 Demo 完成：

- 可以正常调用系统麦克风录音
- 可以开始、暂停、继续、停止录音
- 可以选择至少 2~3 种录音格式
- 录音文件能够正确保存到本地
- App 内可以看到已经完成的录音
- 可以播放已经保存的录音
- 外接 DJI Mic 2 时，可直接使用系统当前音频输入源录音

---

# 2. Demo 功能范围

## 2.1 必须实现

### 录音

支持：

- 开始录音
- 暂停录音
- 继续录音
- 停止录音
- 显示当前录音时长
- 保存录音文件

录音状态：

```text
IDLE
↓
RECORDING
↓
PAUSED
↓
RECORDING
↓
STOPPED
```

---

## 2.2 录音格式

Demo 第一版只实现少量常用格式。

推荐：

```text
WAV
AAC / M4A
FLAC
```

如果 FLAC 在开发初期实现成本较高，可以暂时缩减为：

```text
WAV
AAC / M4A
```

### WAV

默认：

```text
48 kHz
16 bit
Mono
```

可选：

```text
Sample Rate:
44.1 kHz
48 kHz

Bit Depth:
16 bit
24 bit
```

如果 24-bit 在部分设备上暂时无法稳定实现，则 Demo 第一版仅保留 16-bit。

### AAC / M4A

提供简单质量选择：

```text
Standard
High
```

对应内部参数例如：

```text
Standard → 128 kbps
High     → 256 kbps
```

无需在 Demo 中暴露复杂 Codec 参数。

### FLAC

如果实现：

```text
44.1 / 48 kHz
16 bit
```

即可。

---

# 3. 录音页面

Demo 的主页面即录音页面。

建议结构：

```text
┌──────────────────────────┐

        Recorder

          00:01:32

       ● Recording

          [ Pause ]

────────────────────────────

Format
WAV

Quality
48 kHz / 16 bit

────────────────────────────

        [  STOP  ]

└──────────────────────────┘
```

未开始录音时：

```text
        00:00:00

          ● REC
```

录音时：

```text
        00:01:32

        Recording...

          Pause
           Stop
```

暂停时：

```text
        00:01:32

         Paused

          Resume
           Stop
```

---

# 4. 录音设置

Demo 不需要单独设计复杂设置页面。

直接在录音页面提供：

```text
Format
[ WAV ▼ ]

Quality
[ 48 kHz / 16 bit ▼ ]
```

即可。

例如：

```text
Format

○ WAV
○ AAC
○ FLAC
```

根据格式动态显示不同参数。

---

# 5. 录音文件列表

需要一个简单的 `Recordings` 页面。

示例：

```text
Recordings

──────────────────────────

Recording 001
00:03:42

WAV · 48 kHz · 16 bit

2026-09-02 21:35

──────────────────────────

Recording 002
00:01:18

AAC · High

2026-09-02 21:42

──────────────────────────
```

点击录音进入播放页面。

---

# 6. 文件命名

Demo 自动命名即可。

格式：

```text
Recording_YYYYMMDD_HHMMSS
```

例如：

```text
Recording_20260902_213522.wav
```

Demo 暂时不要求用户在录音前输入名称。

后续版本再加入：

- 重命名
- 标签
- 文件夹
- 搜索

---

# 7. 播放页面

播放页面只需要基础功能。

```text
Recording_20260902_213522

WAV · 48 kHz · 16 bit

        01:24 / 03:52

────────●──────────────

          ▶ / ❚❚
```

必须支持：

- 播放
- 暂停
- Seek
- 当前时间
- 总时长

Demo 不需要：

- 波形
- 剪辑
- EQ
- 降噪
- 倍速

---

# 8. 文件保存

所有录音保存在 App 本地目录。

推荐逻辑：

```text
App Storage
│
└── recordings/
    │
    ├── Recording_20260902_213522.wav
    ├── Recording_20260902_214012.m4a
    └── Recording_20260902_215531.flac
```

Demo 阶段无需设计复杂文件数据库。

可以直接：

```text
扫描 recordings 目录
        ↓
读取文件信息
        ↓
生成 Recordings 列表
```

如果需要保存额外信息，可以使用简单 Metadata：

```text
{
  id
  filename
  filepath
  format
  sampleRate
  bitDepth
  bitrate
  duration
  createdAt
}
```

---

# 9. 软件架构

Demo 保持简单，但不要把录音逻辑直接写进 UI。

推荐：

```text
UI
│
├── RecorderPage
├── RecordingsPage
└── PlayerPage

        ↓

Service
│
├── RecordingService
├── RecordingRepository
└── PlaybackService

        ↓

HarmonyOS
│
├── AudioCapturer / AVRecorder
├── AVPlayer
└── File API
```

---

# 10. RecordingService

RecordingService 是 Demo 最重要的模块。

统一提供：

```text
start(config)

pause()

resume()

stop()

getState()

getDuration()
```

UI 不直接控制底层 Audio API。

结构：

```text
RecorderPage
      ↓
RecordingService
      ↓
Audio API
      ↓
Audio File
```

---

# 11. RecordingConfig

统一定义：

```text
RecordingConfig
```

字段：

```text
format

sampleRate

bitDepth

bitrate

channels
```

例如：

```text
WAV

sampleRate = 48000
bitDepth   = 16
channels   = 1
```

或者：

```text
AAC

sampleRate = 48000
bitrate    = 256000
channels   = 1
```

注意：

AAC 不需要显示 bitDepth。

---

# 12. 音频输入

Demo 不实现麦克风设备管理。

原则：

```text
使用 HarmonyOS 当前默认音频输入
```

即：

```text
手机麦克风
       │
       │ 系统自动选择
       ▼
DJI Mic 2 Receiver
       │
       ▼
 HarmonyOS Audio Input
       │
       ▼
    Recorder
```

App 不负责：

- DJI 配对
- DJI 增益控制
- DJI 固件
- 指定麦克风型号
- 无线设备管理

---

# 13. 权限

必须处理：

```text
Microphone Permission
```

首次录音：

```text
用户点击 REC
    ↓
检查麦克风权限
    ↓
无权限
    ↓
申请权限
    ↓
允许
    ↓
开始录音
```

如果拒绝：

```text
无法开始录音

需要麦克风权限。
```

---

# 14. Demo 暂时不实现的功能

以下功能全部放到后续版本。

## 文件管理

暂不实现：

- 重命名
- 分享
- 删除
- 最近删除
- 文件夹
- 搜索
- 批量选择

---

## 音频编辑

暂不实现：

- 裁剪
- 拼接
- Fade in / Fade out
- Marker
- 波形编辑

---

## DSP

暂不实现：

- EQ
- Compressor
- Limiter
- Noise Reduction
- Noise Gate
- AGC
- AI 降噪

---

## 设备功能

暂不实现：

- 外接麦克风选择
- DJI 控制
- 外接麦克风的专用设备控制
- USB Audio 参数控制

---

## 高级录音

暂不实现：

- 32-bit Float
- 96 / 192 kHz
- 多轨录音
- Stereo / Mono 手动路由
- 实时监听
- 输入增益
- Peak Hold
- LUFS

---

# 15. Demo 页面结构

最终只需要三个页面：

```text
             App
              │
        ┌─────┴─────┐
        │           │
     Recorder    Recordings
                    │
                    ▼
                  Player
```

即：

```text
RecorderPage
RecordingsPage
PlayerPage
```

---

# 16. Demo 第一版推荐配置

为了最快得到可运行版本，第一版建议严格控制为：

```text
FORMAT

WAV
└── 48 kHz / 16 bit

AAC
├── Standard 128 kbps
└── High 256 kbps
```

如果这些功能稳定运行，再加入：

```text
WAV
├── 44.1 kHz
├── 48 kHz
├── 16 bit
└── 24 bit

FLAC
└── 48 kHz / 16 bit
```

---

# 17. Demo 验收标准

## 录音

- [ ] App 可以申请麦克风权限
- [ ] 点击 REC 可以开始录音
- [ ] 录音时间正确更新
- [ ] 可以 Pause
- [ ] 可以 Resume
- [ ] 可以 Stop
- [ ] Stop 后生成有效音频文件

## 格式

- [ ] WAV 可以正常录音
- [ ] AAC/M4A 可以正常录音
- [ ] 可以切换格式
- [ ] 不同格式生成正确文件扩展名

## 文件

- [ ] 录音文件可以保存
- [ ] 重启 App 后文件仍然存在
- [ ] Recordings 页面可以找到历史录音
- [ ] 显示文件名
- [ ] 显示录音时间
- [ ] 显示格式

## 播放

- [ ] 点击录音可以播放
- [ ] 可以暂停
- [ ] 可以继续
- [ ] 可以拖动进度条

## 外接麦克风

- [ ] DJI Mic 2 接管系统输入后 App 可以正常录音
- [ ] App 不依赖特定麦克风设备

---

# 18. 最终 Demo 定义

整个 Demo 可以概括为：

```text
┌─────────────────────────┐
│       Recorder UI       │
└────────────┬────────────┘
             │
             ▼
      RecordingService
             │
             ▼
       HarmonyOS Audio
             │
      ┌──────┴──────┐
      ▼             ▼
     WAV           AAC
      │             │
      └──────┬──────┘
             ▼
      Local Recordings
             │
             ▼
       Recordings List
             │
             ▼
          AVPlayer
```

## Demo 核心原则

> 第一版的目标不是制作一个完整的专业录音软件，而是证明 HarmonyOS 上的“高质量录音 → 多格式保存 → 本地管理 → 播放”核心链路能够稳定运行。

只要这一链路完成，后续的 FLAC、24-bit、分享、重命名、最近删除、格式转换、波形以及鸿蒙原生录音界面都可以在现有架构上逐步增加，而不需要重写录音核心。
