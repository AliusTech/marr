# DC_A568 Linux Bring-up 清单

> 相关文档:[repo-layout.md](repo-layout.md)(工程目录) · [distro-scope.md](distro-scope.md)(组件范围)。本文是首板 Linux 移植的执行清单:板卡事实、已定决策、参考资料、待确认项、验收标准、任务顺序。实测结果随时回填。

## 板卡事实

定昌电子(与智通利为同一家公司)DC_A568 一体板(RK3568,4×A55,4GB 内存 + 16GB eMMC,DC 12V)。

> **资料口径(2026-09 澄清)**:目前手上的 Linux SDK(wiki 同源)是**核心板家族(C568/YM568)的配套资料**,不含 A568 一体板专属 dts——SDK 全树唯一的定制板型即 `ztl-YM568-linux.dts`。因此下述外设事实是**核心板/EVB 参照**,其中"核心板侧"项在 A568 基于同款 SOM 时大概率沿用,"载板侧"项必须以 A568 专属资料或实测为准(尤其产品页"百兆"与 EVB 千兆 RTL8211F 的矛盾,可能正是两块板载板设计不同所致)。

**核心板侧(若 A568 = 该 SOM + 载板,则大概率沿用)**:PMIC RK809、vdd_cpu TCS4525(i2c0@0x1c)、eMMC = `&sdhci`、DDR 初始化(rkbin ddr v1.23)、bl31 v1.44。

**载板侧(DC-A568-V06 规格书 + A568 出厂 Ubuntu 固件 dtb 反编译,双双落地 `~/workspace/marr-materials/a568/`)**:

- **网口(固件 dts 定案)**:**gmac1 = RMII 百兆,phy@1(MDIO 地址 0x1),SoC 输出 50MHz 参考时钟**,通用 `ethernet-phy-ieee802.3-c22` 绑定(型号厂商未写死,MDIO 自动探测;上机 `ethtool` 实测可得名);gmac0(RGMII)在本板 disabled——核心板 EVB 的千兆 RGMII 参数对本板无效;两个物理口(RJ45/4P)与 MAC 的对应待上机验证;
- **UART(固件 dts 定案)**:uart3/4/5 = okay(对外三路,Linux 节点 ttyS3/S4/S5);**RS485 = uart4/ttyS4**(规格书);uart1 disabled;uart2 为厂商 fiq-debugger 控制台(主线移植改用标准 8250 console,1500000);
- **CAN:本板无**(规格书零提及,dts 三个 SoC CAN 节点全部不启用;注:RK3568 CAN 为 2.0 非 FD,未来原生 CAN 板注意)——CAN 方案维持 USB 适配器(gs_usb);
- USB:5 Host + 1 OTG,**对外供电总上限 3A**(机器人供电预算需计入);
- 存储:eMMC 8/16/32/64/128G 可选(本板 16G),LPDDR4X 1-8G,TF ≤128G;RTC HYM8563 @ i2c5 0x51(dts 确认);
- GPIO(5 IO 座):GPIO1_A1(上拉默认)、GPIO3_A6(下拉选配)、GPIO3_A3(IO5)等;触摸/屏相关脚(GPIO0_B5/B6、GPIO4_C6)属显示域,随显示一起 disabled;
- **dts 移植基准**:以固件内 `ztl, A568` dtb 的反编译源(`~/workspace/marr-materials/a568/a568-vendor.dts`)为准抄 pinmux/时钟/复位——源级 dts 在厂商内部,我们 SDK 里的 `ztl-YM568-linux.dts` 仅是同家族核心板版,只能参照不可照抄(网口/串口已证实不同);
- 固件:`GB-RK3568-ubuntu22.04-20260715-...img`(RKFW 格式,9 个 568 家族变体 dtb 超集)兼作 bring-up 任务 0 的"厂商镜像点亮"素材;
- 厂商文档:<http://wikicn.gzdcsmt.com/wendang_id_59.html>(C568 家族)与产品页资料下载区(A568 规格书/固件/串口说明等 13 项)。

## 已定决策(bring-up 范围)

1. **Bootloader**:主线 U-Boot(最新稳定版,evb-rk3568 defconfig 基线)+ rkbin DDR blob 拼 idbloader;rkbin 在 `recipes-bsp/rkbin/` 锁版本。
2. **内核**:6.18 LTS submodule;arm64 defconfig + 板级 fragments(`boards/gzdc/dc-a568/config/`);**PREEMPT_RT 首日开启**;console = UART2 @1500000(串口适配器需 CP2102/FT232 级)。
3. **裁剪**:显示/音频**不支持**(明确不需要,非后置);BT、mini-PCIe 后置;WiFi 默认后置(待最终确认);dts 中相关节点一律 disabled。
4. **dts 最小范围**:eMMC、TF、UART2 console、USB(Host + OTG)、GMAC(路数与 PHY 待硬件资料)、HYM8563、DW 看门狗。
5. **wic 分区**:boot 256MB + rootfs A/B 各 4GB + data 剩余(约 7.5GB),ext4,A/B 第一版就进 `marr-sdimage.wks`。
6. **上游 layer**:poky + meta-rockchip + meta-openembedded(kas 锁定);meta-ros 不进 bring-up。
7. **首版镜像**:systemd + ssh + networkd + marr-release;ONNX Runtime 不进首启镜像。
8. **烧录路径**:TF 卡槽在,SD 直写可用——本板三条路径(SD 直写 / maskrom USB / ums)全通,board.yml flash paths 记全集。
9. **CAN(2026-09 定案)**:A568 规格书证实**本板无 CAN**;核心板 EVB 的 CAN1 引出与本板无关。方案维持:USB 适配器走 candleLight/gs_usb(fragment `config/kernel-can.cfg`),`CAN_ROCKCHIP` 不开。驱动器经典 CAN / CAN-FD 之选仍待驱动器侧确认(只影响适配器固件与波特率档)。

## 参考资料与获取(2026-09 已落地本机)

- **厂商 Linux SDK** 已解压至本机 `~/workspace/marr-materials/rk356x-sdk/`(20G,vendor 内核 5.10.226 / U-Boot 2017.09,单提交 rk3568 first commit 20250808)。pinmux 移植参照:`kernel/arch/arm64/boot/dts/rockchip/ztl-YM568-linux.dts`,include 链 `rk3568-evb8-lp4-v10.dtsi → rk3568-evb1-ddr4-v10.dtsi → rk3568-linux.dtsi`;RGMII 延迟、PHY 复位、UART/CAN/RTC 引脚均在上链中,逐条抄录。
- **rkbin blob**(idbloader 组装用):`~/workspace/marr-materials/rk356x-sdk/rkbin/bin/rk35/`——`rk3568_ddr_*_MHz_v1.23.bin`、miniloader、`bl31_v1.44.elf`、`bl32_v2.15.bin`。
- **分区表参考**(厂商 A/B 方案):`~/workspace/marr-materials/rk356x-sdk/device/rockchip/.chips/rk3566_rk3568/parameter-buildroot-fit-ab.txt`,对照我们的 wic 布局。
- **硬件资料**(规格书/原理图):wiki"5. 硬件资料"(提取码 ivc6)——确认 GPIO 引出表、RS485 具体挂在哪路 UART、CAN1 引到哪个连接器。
- **Android 11 SDK**(4.19 内核):未获取,仅在 Linux SDK 信息缺失时再取。
- **厂商预编译镜像 + RKDevTool**:先走通一次厂商镜像的 maskrom 烧录,验证板卡硬件与烧录链路,再上自己的镜像。

## 待确认(⚠ 已全清,以下为上机实测项)

- maskrom VID/PID 实测(board.yml 用);
- PHY 具体型号(`ethtool` 上机一读即知,不阻塞——绑定与地址已定);
- 两个物理网口(RJ45/4P)与 MAC 的对应关系;
- A568 是否 MXM314 SOM 架构(影响电源管理节点细节,不阻塞首启);
- WiFi/BT 模组型号(已后置,不阻塞)。

## 验收标准(全部通过 = 移植完成)

1. UART console 进 shell;
2. eMMC 读写正常,A/B/data 三分区可见可写;
3. TF 卡读写正常;
4. 网口 DHCP 拿到地址,ssh 可登录;
5. USB Host 枚举 U 盘;
6. 硬件看门狗超时触发重启有效;
7. cyclictest 连跑 1 小时无告警,记录基线数据(留作 RT 调优对照);
8. 连续开关机 20 次无异常。

## 任务顺序

0. 下载硬件资料与 Linux SDK,清掉两个 ⚠ 项;用厂商镜像 + RKDevTool 走通一次 maskrom 烧录。
1. 仓库脚手架:meta-marr 最小集、meta-marr-rockchip 机器(dc-a568)、`config/kas/dc-a568.yaml`、kernel submodule(6.18.y)。
2. idbloader + U-Boot(EVB 基线)→ 自写最小 dts → TF 卡启动内核到 console。注意:BootROM 优先从 eMMC 启动,SD 调试期间用 RKDevTool 把 eMMC 的 idbloader 擦掉,避免抢启动。
3. eMMC 启动 + A/B/data wic 分区落地。
4. 网络与 ssh、看门狗、cyclictest 基线。
5. 验收清单逐项打勾,结果回填 board.yml 与本文档。
