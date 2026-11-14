# iOS 2.2.0 验证方法

## 自动回归

```sh
npm ci --ignore-scripts
npm test
swift test
python3 Tools/run-transport-regression.py
swift run bfgdemo
```

- UI 回归使用实际页面源码：目标选择、导航、弹窗、取消、风险确认、选择值保留、清除后状态和实验入口删除。
- Swift 回归包括标准加密向量、原有策略与协议，以及新增的分片收包、损坏配对 MAC 拒绝、日志脱敏、车辆选择恢复、快照持久化和首遍超时不能视为稳定。
- 适配器回归把生产 BleTransport.swift 与 CoreBluetooth 桩一起编译执行，检查无轮询等待、分片发送、背压、ACK 顺序、失效外设回调和断开后的回调隔离。
- 车辆模拟演示保留原有端到端场景。测试模型与真实车辆可能不同。

页面/原生动作契约由 Tools/check-ui-wiring.py 的 part1_contract_diff 检查；CI 不依赖它的可选 Chrome 启动路径。回归输出 build/ui-test-results.json 作为 CI 产物保存。

## 编译与包检查

CI 使用 macos-15，生成工程并执行 Release 真机架构编译。检查生成前后的蓝牙权限和启动屏配置，产出未签名 IPA。交付时再核对 IPA 哈希、版本、arm64 架构、最低 iOS 版本及包内页面。

## 必须另行完成的真机检查

1. iPhone 上的满屏布局、灵动岛/底部安全区及蓝牙权限。
2. 明确选择车辆后的 SN 一致性、配对、杀进程后重连和只读数据。
3. 前台空闲、扫描、连续读取、诊断导出和多轮取消期间的 CPU、内存与响应时间；使用 Instruments / Memory Graph / Time Profiler 等工具。
4. 在只读链路和备份验证可靠后，单独验证允许的校准写入、写后回读与恢复。不得用编译或模拟测试替代实车结论。

本版本的测试结果以具体提交的 Actions 日志为准；不把历史测试数量或旧版本真机描述视为新包验收结果。
