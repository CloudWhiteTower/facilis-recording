# v3 全应用优化与验证

更新：2026-10-08。版本 `3.0.0 / 3000000`，保持 API 24、现有包名和录音目录。录音与转换继续使用系统音频接口，应用保持纯离线，不新增运行时依赖。

## 实现

| 环节 | 变化 | 作用 |
| --- | --- | --- |
| 连续波形 | 按测量历史、尺寸和分贝范围缓存插值曲线；逐帧仅平移横坐标，渐变按主题和状态复用 | 减少显示同步回调中的数组、曲线和渐变创建，保持原来的振幅和移动轨迹 |
| 边缘光 | 缓存圆角路径；尺寸变化时重建 | 避免每一帧重复提交整条边框的几何命令 |
| 资料库 | 缓存搜索结果和日期分组，隐藏页面首次加载延后至可见时 | 减少无关状态变化带来的过滤、分组和文件读取 |
| 批量文件操作 | 一次读取两个目录，复用事务成功后的列表；操作之间让出主线程 | 大量选择时界面能更新忙碌状态；成功批次不再逐条重新扫描全部录音 |
| 批次与新录音并存 | 索引写入增加版本计数；批次让出线程后检查是否发生其他保存 | 防止批次中的旧快照覆盖期间新保存的录音 |
| PCM 录制 | 仅合并已排队的数据，最大合并块 64 KiB；保留 2 MiB / 64 包背压限制 | 存储繁忙时减少异步写入和 Native 工作项，不为凑块而延迟新音频 |
| WAV 恢复 | 每写入约 5 秒音频更新一次文件头并同步；暂停时也更新 | 异常结束前已完成的前缀能被识别，减少整段 WAV 无法打开的情况 |
| 采集停滞 | PCM 录制连续 5 秒没有收到数据时停止采集并尝试保存已写入内容 | 避免显示计时正常而实际没有继续收到录音样点 |
| 音频转换 | 复用重排缓冲区；相同 PCM 表示直接写入；AAC 完整帧直接提交，只有尾部缓存 | 降低重复分配和复制，保持采样率、声道、整数 PCM 精度和尾部样点 |
| 解码调度 | 每轮最多提交、取出各 8 个立即可用的编解码缓冲；没有进展时短暂等待 | 减少按单个压缩帧串行等待，同时保留取消和停滞超时 |
| 转换进度/取消 | 按实际消耗的 PCM 更新进度，进度单调且去重；FLAC 编码等待检查取消 | 减少进度条反复更新和取消等待；只有文件登记成功后显示完成 |
| 播放控制 | 播放/暂停最多等待 8 秒，超时隔离旧实例；录音、播放回调捕获界面异常 | 按钮不会因一次未返回的系统调用持续失效，页面销毁也不会破坏资源清理 |

动画沿用系统导航、Sheet、HDS 按压光感和既有弹簧参数。Canvas 的请求范围仍是 30–60 fps，短交互仍向系统请求最高 120 fps；这些是请求值，不是实测帧率。后台、不可见、暂停和减弱动效条件下的绘制生命周期保持一致。

WAV 中途检查点仅声明已完成、对齐且具备合法 RIFF 大小的前缀，24-bit 奇数样点的末尾补齐仍只在最终结束时写入。异常退出可能失去最后一次检查点之后的内容；此机制不能保证对断电、硬件故障或严重磁盘损坏的恢复。不会把未完成的录音主动加入资料库可操作列表。

## 验证记录

Host 回归 **178/178**：模型 55、录音服务 19、仓库/导出 37、页面操作 13、播放服务 37、转换服务 17。新增用例验证中途 WAV 文件头、短写入、合并写入、停滞收尾、界面回调异常、曲线缓存等价性、批次期间保存新录音、失败刷新时保留已完成结果、播放控制超时和单调转换进度。

40 条录音成功批量移动只扫描两个目录各一次；逐文件索引更新和事务恢复仍保留。两小时录音压力检查使用加速数据和平台替身，不能算作两小时真实设备录音。

Debug、Release 和 `entry@ohosTest` 均已构建。真实 MatePad Air 已覆盖安装，未卸载应用；设备启动和测试目前等待解锁。设备结果、独立解码及实录时长完成后会补入本节。

## 复现

Host 回归命令见[工程测试说明](../HarmonyRecorder/README.md#测试)。真实设备构建与覆盖安装使用 DevEco CLI；需配置自己的签名，且保持原有签名兼容。

```powershell
Set-Location HarmonyRecorder
devecocli build
devecocli build --product default --build-mode release
devecocli build --modules entry@ohosTest
devecocli run --module entry --device <serial>
```

测试包安装后，可使用 SDK 的设备测试命令启用编解码、录制和长录音用例；默认单元测试不访问麦克风：

```text
hdc -t <serial> shell aa test -b com.example.harmonyrecorder -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 900000 -s integration true -s conversion true -s v3 true -s capture true -s soakSeconds 600 -w 1200
```

实录用例只清理自己生成的资料库记录，并保留缓存副本用于独立解码；已有录音不会被选择。编解码压力夹具以 8192 样点分块生成，PCM 比较以 64 KiB 分块执行。运行长录音前应保证设备已经解锁且电量、剩余空间足够。

将缓存音频复制到本地后，使用独立 FFmpeg 流式解码，检查实际参数、样点数、信号与无损哈希：

```text
node scripts/verify-audio-streams.cjs <fixture-directory>
```

## 保真与范围

转换不增加重采样、声道混合、DSP 或降噪。WAV/FLAC 无损往返应保持整数 PCM 逐样点相等，AAC 则允许有损编码及编码帧填充；把 AAC 转为 WAV 或 FLAC 不会恢复此前丢失的信息。44.1/48 kHz 单声道、FLAC 输出 16 bit 和 24-bit 输入精度保护的边界保持原状。

目前没有采集 HiSmartPerf 帧时间、系统功耗或扬声器/耳机主观听感，也不声称定量加速倍数。GitHub 发布与 AppGallery 正式审核、发布签名是不同交付步骤。

参考：[官方同步音频解码](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/synchronous-audio-decoding)、[官方同步音频编码](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/synchronous-audio-encoding)、[官方动画帧率优化](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/bpta-animation-frame)、[动画实现说明](MOTION_IMPLEMENTATION.md)、[音频链路](AUDIO_PIPELINE.md)。
