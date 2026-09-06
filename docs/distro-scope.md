# marr 发行版组件范围(distro scope)

> 相关文档:[repo-layout.md](repo-layout.md)(工程目录) · [ci.md](ci.md)(CI/CD)

本文回答一个问题:**"内核 + ONNX Runtime"之外,一个能交付运动智能的小脑发行版还包含什么**。它是 marr-runtime 与 image recipe 的设计输入。

## 决策记录

| 决策 | 状态 | 结论 |
|---|---|---|
| 与大脑的通信栈 | **已定** | **ROS 2 + Cyclone DDS**(meta-ros 引入;ROS 2 代号选 meta-ros 支持的最新 LTS 代号,与内核 LTS 兼容矩阵对齐) |
| 发行版形态 | 待确认 | 建议 image-based:整卡镜像 + A/B OTA,不向用户暴露包管理器(ChromeOS/OSTree 形态,非 Debian 形态) |
| OTA 引擎 | 待定 | 建议 RAUC(整卡镜像世界观原生的 A/B 更新器) |
| secure boot 与签名链 | 待定时间点 | 见"安全"层;策略模型签名建议提前 |

## 组件清单(六层)

### 1. 启动链

idbloader + U-Boot + 内核(整卡 wic 已覆盖)。secure boot(ROTPK → U-Boot 验证 → fitImage 签名)后置,但 wks 分区与启动参数**从第一版就不堵死**这条路。

### 2. 推理运行时(小脑的核心)

- ONNX Runtime:已定,`recipes-support/onnxruntime`,`marr-versions.inc` 统一锁定。
- **marr-runtime(第一方应用,当前最大缺口)**:策略模型加载与热替换、推理循环(1ms 级周期调 ORT)、观测→动作接口约定、**failsafe**(推理超时/模型异常 → 安全停机)、策略包格式(model + metadata + 签名,大脑侧导出的标准产物)。

### 3. 通信(已定)

- ROS 2 + Cyclone DDS:meta-ros 作为上游 layer 在 `marr-base.yaml` 锁定引入(SoC 无关,属于发行版层能力);ROS 2 与 Cyclone 版本进 `marr-versions.inc`,与 ONNX Runtime 同一机制、同一纪律。
- 运行时进程以普通核运行,不侵入实时预算;大脑侧据此对齐 QoS 与消息 schema。
- PTP/gPTP 时间同步(多机协同前置)排 P2。

### 4. 硬件接口(小脑的本职)

CAN/CANFD、PWM、编码器、IMU 的驱动与 dts 绑定;首板 DC_A568 的外设盘点是适配任务清单的主体,产出直接进 `boards/gzdc/dc-a568/` 的 dts 与 config。

### 5. 系统维护与升级

- **A/B 双 rootfs + data 分区**:必须进 `marr-sdimage.wks` 第一版——整卡镜像世界里 OTA 引擎可以后装,分区布局后补最痛。
- OTA 引擎(建议 RAUC)、provisioning(首启身份/网络/密钥)排 P2。
- systemd 基础件排 P1:ssh、网络管理、journald、硬件 watchdog——决定"可远程运维"。

### 6. 安全与签名链

- **策略模型签名验证**:模型即代码,是"交付运动智能"的供应链核心——unsigned 模型能刷进小脑等于任何拿到索引的人能给机器换大脑。建议随 marr-runtime 首版就定格式,实现可后置。
- secure boot 链、运行时进程非 root,排 P3。

## 优先级

- **P1(首板可交付)**:marr-runtime 骨架(含 failsafe 与策略包格式)、ROS 2 + Cyclone 接入、wic 分区 A/B 预留、systemd 基础件、ONNX Runtime recipe。
- **P2**:RAUC OTA、provisioning、PTP、DC_A568 外设全量。
- **P3**:secure boot 签名链、性能验收(cyclictest + cpuset/affinity 调优)、SDK/二次开发支持。
