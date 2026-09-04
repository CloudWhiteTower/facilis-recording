# Contributing

感谢你改进 Facilis Recording。

## 开发流程

1. Fork 仓库并创建功能分支。
2. 在 `HarmonyRecorder/` 中完成修改。
3. 执行：

   ```powershell
   devecocli build
   devecocli build --modules entry@ohosTest
   ```

4. 对录音、播放、删除或权限相关修改，在至少一种真实设备或模拟器上补充手工验证。
5. 提交 Pull Request，说明行为变化、验证结果以及涉及的 HarmonyOS/API 版本。

## 约束

- 不提交签名证书、Profile、密钥、密码、令牌、本机路径或录音样本。
- 不把仅改文件扩展名描述为音频转码。
- 不加入未经许可的第三方代码、图标、截图或商标素材。
- 新增权限、网络请求、第三方 SDK 或数据收集时，必须同步更新隐私文档。
