# BFG 电量校准 iOS 2.2.0

以开源安卓版 5.0.35 的主要蓝牙校准功能为基准的 iOS 移植。支持 iOS 16 及以上的 arm64 iPhone。项目没有完成该用户的 B30C / 磷酸铁锂配置实车验收。

## 功能范围

- 扫描并明确选择车辆，车端按键确认配对；使用系统钥匙串保存凭据，恢复已配对车辆和当前选择。
- 读取 SOC、容量、电压、固件版本与通信模式。
- 原有计量模块 Profile 档位写入、受固件组合限制的仪表盘电压配置写入，以及写后回读。
- 首次原参数、最近写前参数和仪表配置备份与恢复；写前快照保存并核实后才允许继续。
- 原有只读寄存器扫描、诊断导出与分享。

本版本移除了独立 0x0E 容量写入、候选寄存器写探测、容量扫值、专家模式和 N 前缀只读豁免。N 开头车辆保留原版只读限制；仪表写入保留原版四项固件条件。

当前实现不包含 Android APK 虚拟运行、BlackBox 或读取其他应用的私有数据库。iPhone 越狱不会自动补齐这些代码；本应用的凭据来自自己的配对流程。

## 验证

```sh
npm ci --ignore-scripts
npm test
swift test
python3 Tools/run-transport-regression.py
swift run bfgdemo
```

CI 还检查页面动作契约，并在 macOS 上生成 Xcode 工程、编译 iOS Release 和检查产物权限声明。蓝牙适配器回归执行的是生产适配器源码与模拟 CoreBluetooth，不代表实际无线链路或真机 CPU / 内存测试。

精确测试结果以相应提交的 Actions 记录为准。安装后仍需先验证扫描、目标车辆身份、配对、重连和只读数据；实车写入与恢复要单独验收。编译或模拟测试成功不能证明具体车辆可校准，也不会自动生成磷酸铁锂专用 SOC 曲线。

## 构建和安装

```sh
brew install xcodegen
xcodegen generate --spec ios/project.yml
```

`.github/workflows/ios.yml` 生成未签名 IPA。普通安装需要签名；已安装 TrollStore 且受支持的系统可以由 TrollStore 处理安装。不要向项目或聊天提交 Apple ID 密码、访问令牌或签名私钥。

架构和修复说明见 [docs/IOS_PORT.md](docs/IOS_PORT.md)，测试边界见 [docs/TESTING.md](docs/TESTING.md)，证书构建说明见 [docs/IOS_SIGNING.md](docs/IOS_SIGNING.md)。

## 许可证

Apache License 2.0，详见 LICENSE。保留原项目及上游版权声明。
