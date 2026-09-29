# JevWeChatTweak

第一阶段只验证：rootless 编译、打包、注入微信和测试按钮。

目标：
- iPhone 14 Pro Max
- iOS 16.2
- Dopamine
- WeChat 8.0.75
- Bundle ID: com.tencent.xin

本阶段不读取聊天、不 Hook 微信私有消息类、不调用 Jev API、不修改输入框。

构建：
GitHub Actions 使用 macOS runner + Theos。
成功后从 workflow artifact 下载 `.deb`。

请先完成 CI 构建验证，再进行设备安装测试。
