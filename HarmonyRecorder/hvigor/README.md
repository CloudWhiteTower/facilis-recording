# 分层图标构建校验

当前 SDK 的图片转码器会将 1024 像素分层 PNG 缩成 512 像素，并将背景透明度 255 改成 254。`preserve-layered-icons.ts` 通过官方 Hvigor 插件任务，在资源编译后、打包前恢复经过校验的原始图标；资源名称与资源索引不变。标准资源校验和后续打包、签名流程继续执行。

- `VerifyLayeredIconResources` 检查 1024 像素、纯色不透明背景及透明前景，并核对打包输入与源文件字节一致。
- `VerifyPackagedLayeredIcons` 只读检查未签名 HAP 中的两张 PNG；检查通过后才继续签名。
- 两个任务适用于 `default` 与 `ohosTest`，在增量构建中也执行。任务不存在、图标缺失或校验失败均阻止构建。
- 仅使用 Node.js 内置模块，不修改 SDK、已生成的 APP/HAP 或用户签名配置。

实现依据：[定制 Hvigor 插件](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/bpta-custom-hvigor-plugin)、[扩展构建实践](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/ide-hvigor-config-ohos-sample)。升级 SDK 后，可在确认其原生打包完整保留图标后移除此插件。
