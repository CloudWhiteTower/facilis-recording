# v2 实施与验收记录

更新：2026-09-27。分支：`v2/harmony-immersive-ui`。状态：v2 开发版源码交付，未创建正式 v2 Release。

## 交付与验证概览

本次源码提交为 `a8a60fc`。9 月 23 日首次推送因连接失败未到达远端；9 月 27 日源码与截图已成功推送至 [v2 分支](https://github.com/CloudWhiteTower/facilis-recording/tree/v2/harmony-immersive-ui)，并同步整理文档。分支上传不等同于合并 main、发布安装包或通过 AppGallery 审核。

| 范围 | 最近验证结果 | 验证日期 |
| --- | --- | --- |
| Debug / Release / entry@ohosTest | 构建通过 | 2026-09-23 |
| 本机模型与资源检查 | 37/37 通过 | 2026-09-23 |
| Pura 90 API 24 单元测试 | 35/35，Failure 0，Error 0 | 2026-09-23 |
| 手机亮暗录音页、质量 Sheet、暗色 Select | 截图检查通过；覆盖安装后无应用崩溃日志 | 2026-09-23 |
| HDS 高级材质 / API 26 原生材质 | 当前模拟器未报告高级材质支持；API 26 未验证 | — |
| 新曲线实时录音、平板完整矩阵、HiSmartPerf | 尚无完整验收记录 | — |

9 月 27 日仅整理文档与上传，不将之前的构建和设备测试表述为当日重测。当前截图索引见 [外观检查](../data/v2-validation/README.md)。

## 2026-09-23 光感与连续波形

- 官方依据：[设计资源](https://developer.huawei.com/consumer/cn/design/resource)、[UI Design Kit](https://developer.huawei.com/consumer/cn/sdk/ui-design-kit)、本地官方《沉浸光感》最佳实践（`最佳实践/沉浸光感/bpta-spatiality-immersive`）和 HDS Navigation/Tabs 材质 FAQ。
- 核对安装的 SDK 声明：`hdsMaterial` 从 6.1.0(23) 提供；它与 API 26 的 `uiMaterial.ImmersiveMaterial` 是不同能力。修正原先把 HDS 沉浸材质也限制在 API 26 的判断。导航使用 ADAPTIVE；设备不报告沉浸材质时使用官方建议的 SMOOTH 档位。
- 自定义内容采用统一的原生 `backgroundEffect`：半透明暖色磨砂、方向性高光与细边缘。系统 Sheet 使用 `blurStyle`，Select 使用 `menuBackgroundBlurStyle`；亮暗资源独立配色。窗口失活后关闭模糊，动态边缘光仅在前台可见录音时运行。
- 录音页采用 170vp 手机波形区域、18fp 时间标题、无额外标签的格式/容量信息，以及有按压光感的磨砂录音控制。保留原生 HDS 浮动底栏，关闭横向滑页。
- 连续曲线来自真实录音振幅包络：固定 96–180 个可视采样点，单调三次 Bézier 插值经过采样点、无额外峰值，左侧透明消退，末端柔光。游标使用同一曲线插值，滚动时与曲线对齐；暂停冻结、停止清空。该曲线不是声波频率或音高的重建。
- 根 README 与版本 README 中涉及参考应用的内容和调研链接已清理；第三方代码许可证与版权声明保留。
- 本机模型检查：37 项通过，0 失败，包含曲线边界、极值保持、实时游标和材质能力分离。设备 Hypium：`Tests run: 35, Failure: 0, Error: 0, Pass: 35, Ignore: 0`。
- 最终源码 Debug、Release 和 entry@ohosTest 均构建成功；Release 已覆盖安装启动，随后恢复 Debug 供用户检查。亮暗录音空闲页、亮暗质量 Sheet、暗色 Select 已实际检查。新增曲线的麦克风录音/暂停/恢复由用户验收。
- Pura 90 运行日志为 `FacilisMaterial api=24 types=`，设备未报告 HDS 高级材质支持。本次截图展示系统模糊与轻量光感路径，不作为硬件加速沉浸材质或 API 26 效果验收。
- 修正截图中发现的渐变按钮圆形裁切，以及透明渐变经过黑色导致的灰色脏边；使用显式圆形 Button、裁切及同色透明端点。
- 最终 Debug 包再次覆盖安装、启动成功，应用崩溃日志为空；`git diff --check` 通过，README 检索无参考应用残留。源码/文档敏感字段扫描无命中；本地签名配置未改动或上传。交付到模拟器，未创建 GitHub v2 Release。

以下 9 月 5 日记录为历史验证状态；本次交付以本节新增记录为准。

## 范围

按已确认计划统一暖橙语义色、HDS 导航与浮动底栏、录音舞台、Canvas 波形、扁平资料库、播放器与外观设置。录音引擎、存储结构和已有录音不迁移。只有用户确认最终验收后才升级版本号、创建 GitHub v2 Release。

## 2026-09-05 历史验证

- 已实现亮暗语义令牌、HDS 导航/浮动底栏、HdsNavDestination 播放路由、日期分组资料库、Canvas 固定窗口波形和仅录音时启用的单条边缘光效。
- 当前 DevEco Studio 为 6.1.1.300，编译 SDK 和运行中的 Pura90 模拟器均为 API 24。API 26 工具链与镜像尚未就绪，不能声称已验证 API 26 沉浸材质。
- 用户已恢复原开发签名，已关联到 default 产品。CLI 多次确认 `App installed successfully` / `start ability successfully`，新版已覆盖安装到 Pura 90；没有卸载、清除或迁移已有录音。
- 已验证手机录音空闲页、设置主题切换、亮暗音质 Sheet、暗色 Select，以及 M4A 选择后主页面和 Sheet 的实时更新。测试时未代替用户进行麦克风录音或删除其录音。
- 设备 Hypium：31 项通过，Failure 0、Error 0（09:51 执行）。随后新增自定义 dB 范围测试；当前本机模型测试 34 项通过，其中两项资源文件检查仅在本机运行。新增用例尚未在设备重跑。
- 最新源码 Debug、Release、entry@ohosTest 已再次全部构建成功并生成签名包，git diff --check 通过。模拟器关闭后新增的暂停滚动位置冻结、自定义 dB 刻度和 default 材质元数据尚未重新安装到设备。
- 模拟器现已停止，设备列表为空。API 24 平板启动被许可确认拦截；未重试或代为接受协议。API 26 下载/升级及镜像仍待用户准备。
- HiSmartPerf 已确认设备存在 SP_daemon；尚未取得有效采集数据。首次采集输出路径含连字符被参数解析器拒绝，改为下划线后设备已断开，不能声称性能通过。
- 敏感信息扫描 71 个候选文本文件，仅发现用户刚恢复的本地 `HarmonyRecorder/build-profile.json5` 签名配置。此文件不可直接提交或上传；签名材料仍保持本地，v2 尚未提交或发布。

## 待完成门禁

- [x] 统一材质入口，移除页面级重复模糊/阴影组合。正文舞台使用集中配置的 backgroundEffect，原生 HDS 导航材质独立处理。
- [x] 实现页签可见性驱动的资料库刷新、后台停止计时器和主题系统栏同步；需补全状态矩阵的设备回归。
- [x] 实现原生 HdsNavDestination 播放路由和相对宽度/最大宽度布局；播放器、平板仍需实际外观验证。
- [x] 实现波形 30fps 上限、暂停冻结、正确 dB 映射及单元测试；实时录音阶段的视觉和性能仍需验证。
- [ ] 安装官方 API 26 工具链，按最新官方版本命名配置 target，保留兼容 API 24。
- [ ] API 26 原生材质运行时保护与能力降级测试。
- [x] Debug、Release、ohosTest、差异与敏感信息检查（2026-09-23）。
- [x] 恢复升级签名，安装并启动到手机模拟器；每次新改动仍须重装验证。
- [ ] API 24/26 手机和平板截图矩阵、功能状态和 HiSmartPerf 检查。
- [ ] 用户实际录音验收、README/截图更新，再决定正式发布。

## 官方依据与边界

- [沉浸材质启用](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkts-immersive-light-sense-enable)
- [兼容指南](https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/arkts-immersive-light-sense-compatibility)
- [光效与功耗约束](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-immersive-light-sense-constraints)
- [升级指南](https://developer.huawei.com/consumer/cn/doc/doccenter-release-notes/upgrade-adaptation)

本地官方文档说明 `uiMaterial.ImmersiveMaterial` 从 26.0.0 起支持，并限制生效容器/组件。普通正文舞台不能仅因设备为 API 26 就宣称原生沉浸效果生效；需按官方支持范围实现并实机验证。HDS 材质能力与 API 26 原生 uiMaterial 能力分别判断。

## 当前实现方式

- 亮色橙 `#C85A10`、暗色橙 `#FFB457`，系统资源令牌覆盖文字、图标、背景、Sheet、Select。Canvas 使用对应颜色字符串。
- 录音舞台保留 28vp 圆角。以静态暖橙渐变作为底色，单次系统背景模糊提供半透明材质；不运行背景装饰动画。手机录音内容无 Scroll，浮动底栏占用空间已留出。
- StageEdgeLight 使用不参与命中测试的 Canvas 绘制单条边缘高光；空闲为静态高光，前台可见录音时流动。暂停、隐藏、后台均清除计时器。质量入口与 Sheet 已在设备上检查可用。
- LiveWaveform 动态取 96–180 个采样点，用单调三次 Bézier 曲线连接；左 15% 透明消退，末端 20% 橙色增强。停止清空历史，暂停保持采样与滚动位置并降低饱和度。曲线与刻度使用同一 dB 映射，实时指示点沿末段曲线插值。
- 播放页只使用静态 Symbol 和实际播放进度，不制造离线音频波形。

## 复现验证

工程目录下使用 `devecocli build`、`devecocli build --build-mode release`、`devecocli build --modules entry@ohosTest`。默认构建和最后一轮安装均使用 API 24，不能作为 API 26 兼容证明。

仓库根目录运行 `node scripts/test-ui-model.cjs <DevEco自带typescript/lib/typescript.js路径>`。这个脚本复用 Hypium 的同步模型测试，操作系统 API 不做模拟实现，不能测试 ArkUI 渲染、麦克风或真实材质能力。

设备测试使用签名测试 HAP 安装后执行：

```text
hdc -t 127.0.0.1:5555 shell aa test -b com.example.harmonyrecorder -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 30000 -w 40
```

## 后续人工步骤

1. API 26 官方下载中心需要登录。用户准备配套 DevEco Studio、SDK 及手机/平板镜像后，提供安装路径；代理不得自行操作账号登录或接受许可。
2. API 24 平板启动需用户运行 `devecocli emulator license` 并确认许可；用户确认后才重试。
3. 手机新版已于 9 月 23 日安装。后续补齐主题重启持久化、资料库/播放器及录音状态截图；直观录制和麦克风效果由用户验收。
