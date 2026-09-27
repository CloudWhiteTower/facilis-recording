# 动画与交互优化

更新：2026-09-27。基于 API 24 实现，未升级 SDK 或录音格式，也未更改已有录音文件。

## 覆盖范围

| 交互 | 实现 |
| --- | --- |
| 三个底部页签 | 保留 HdsTabs 原生内容转场；高亮使用独立索引，在 onAnimationStart 响应，避免等页面切完才变色。选中底色保留节点，以透明度和缩放过渡。 |
| 资料库进入播放器、返回 | 保留 HdsNavigation / HdsNavDestination 原生进出场；减弱动效时关闭 NavPathStack 的动画。 |
| 开始、暂停、继续、结束录音 | 控件区固定为 112 vp 高，避免录音状态变化推动整个波形区域；只在录音状态改变时启动过渡，计时和振幅通知不触发动画闭包。 |
| 按压与质量入口 | 开始按钮使用可中断的跟手弹簧；Touch Move 不再提前取消按压。质量入口箭头随 Sheet 开关转动。 |
| 质量 Sheet、Select、确认弹窗与系统分享 | 保留原生组件的系统动效，不增加覆盖其进出场的整页动画。 |
| 搜索、多选、最近删除、空态和行增删 | 使用短透明度/位移转场与稳定记录 key；文件操作先完成，animateTo 闭包只提交 UI 状态。祖先列表不重复叠加行位移。 |
| 播放与进度拖动 | 播放/暂停图标只在状态改变时过渡。拖动预览与 AVPlayer 回调分离，释放/点击后提交一次 Seek；250 ms 内忽略明显偏离目标的旧进度，完成/错误/未准备状态可以解除保护。该短窗口是 UI 启发式，不是音频定位完成信号。 |
| 亮暗主题 | 选项高亮与缩放使用统一动效；Index 统一应用系统主题，移除设置页重复调用。系统资源换色不承诺逐色插值。 |
| 连续波形与边缘光 | 使用 displaySync 同步绘制，替换 34 ms setInterval。波形保留真实振幅，按 WAV 90 ms、M4A 120 ms 的现有采样节奏连续交接。 |

## 动效规则

`MotionTheme` 集中提供按压、状态切换、内容出现参数。按压使用 `responsiveSpringMotion(0.24, 0.9, 0.12)`，状态切换使用 `springMotion(0.32, 0.9, 0.12)`；内容淡入 180 ms、淡出 120 ms，位移分别为 6 vp 和 -3 vp。这些是本项目的调节值，非官方指定标准。

短交互向系统请求最高 120 fps 的绘制机会；Canvas 请求 30–60 fps、期望 60 fps。期望值不等于实测帧率，实际取决于屏幕、系统调度与负载。绘制直接使用 Canvas，不增加逐帧状态变量或布局计算。

VSync 时间戳按纳秒单调时钟换算。暂停、不可见、后台停止帧请求，恢复首帧增量为 0，销毁时解除订阅。待绘波形快照最多 8 份；极低帧率时跳过陈旧显示帧，保留最新快照中的真实历史，不改动录音数据。

使用系统无障碍接口读取并监听“减弱动效”。开启后取消位移/弹簧、停止装饰性持续运动，波形仍随新采样静态更新。页面通过响应式状态显式传入偏好，避免已显示组件持有旧转场参数。`duration: 0` 不能关闭弹簧曲线，因此减弱模式使用非弹簧参数。

## 官方依据

- [优化动画性能](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/arkts-animation-usage-guide)：优先系统动画、使用图形变换、合并同参数状态更新。
- 通过 `devecocli docs` 阅读《实现属性动画》`arkts-attribute-animation-apis`、《弹簧曲线》`arkts-spring-curve` 和《动画帧率优化》`bpta-animation-frame`，核对 UIContext 动画作用域与中断行为。
- 官方 Tabs FAQ `faqs-arkui-451`：高亮索引与内容索引分离，在动画开始时响应。HdsTabs 的事件同时按本机 API 24 声明核对，未使用其未暴露的 `animationMode` / `onAnimationEnd`。
- 官方 `js-apis-graphics-displaysync`、`displaysync-ui`、`bpta-vsync-power-optimization`：显示同步、正确 UIContext 和帧请求生命周期。
- 官方 `js-apis-accessibility`：API 23 起提供减弱动效查询和监听；本项目最低 API 24。

## 验证

2026-09-27：

- Debug、Release、entry@ohosTest 构建通过。仍有原存储/音频模块的异常和权限提示，以及 Release 混淆配置提示。
- 本机模型与资源测试 44/44 通过。新增 7 项波形调度测试，覆盖纳秒时钟、两种采样节奏、早到采样、暂停恢复、减弱动效和 1000 次连续快照压力情形。
- Pura 90 API 24 设备单元测试 42/42 通过，Failure 0、Error 0。另两项资源文件检查仅在本机运行。
- 临时页面方法检查 10/10，通过假宿主检查拖动预览、单次 Seek、短音频、完成/错误状态和动画闭包内无文件读取。该检查不替代 ArkUI 运行或音频测试。
- 最新 Debug 包已覆盖安装并启动。API 24 手机已检查页签往返、亮暗主题、质量 Sheet 开关、多选与退出、搜索无匹配后恢复列表、进入播放器和返回。暂停状态下拖动进度条后停留在实际 7.7 s 位置，未出现进度回退；没有操作录音文件的删除、重命名或分享。
- 未发现该应用崩溃日志。系统日志仍有 HDS 材质和 Sheet 参数的诊断输出，本次不将“无崩溃”表述为系统日志完全无错误。

尚需实际交互验收：两种格式录音时的持续帧节奏、暂停/恢复和后台往返，快速连续打断转场、播放中拖动，运行中切换系统减弱动效，平板布局与高刷新率真机。HiSmartPerf 的帧时间、掉帧与功耗尚未采集，不以单元测试或静态截图证明“稳定 60 fps”。

复现本机检查：

```powershell
node scripts/test-ui-model.cjs '<DevEco Studio>/tools/ohpm/node_modules/typescript/lib/typescript.js'
Set-Location HarmonyRecorder
devecocli build
devecocli build --modules entry@ohosTest
devecocli build --product default --build-mode release
```
