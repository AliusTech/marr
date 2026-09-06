# DC_A568 Linux Bring-up 清单

> 相关文档:[repo-layout.md](repo-layout.md)(工程目录) · [distro-scope.md](distro-scope.md)(组件范围)。本文是首板 Linux 移植的执行清单:板卡事实、已定决策、参考资料、待确认项、验收标准、任务顺序。实测结果随时回填。

## 板卡事实

定昌电子(与智通利为同一家公司)DC_A568 一体板(RK3568,4×A55,4GB 内存 + 16GB eMMC,DC 12V)。

> **资料口径(2026-09 澄清)**:目前手上的 Linux SDK(wiki 同源)是**核心板家族(C568/YM568)的配套资料**,不含 A568 一体板专属 dts——SDK 全树唯一的定制板型即 `ztl-YM568-linux.dts`。因此下述外设事实是**核心板/EVB 参照**,其中"核心板侧"项在 A568 基于同款 SOM 时大概率沿用,"载板侧"项必须以 A568 专属资料或实测为准(尤其产品页"百兆"与 EVB 千兆 RTL8211F 的矛盾,可能正是两块板载板设计不同所致)。

**核心板侧(若 A568 = 该 SOM + 载板,则大概率沿用)**:PMIC RK809、vdd_cpu TCS4525(i2c0@0x1c)、eMMC = `&sdhci`、DDR 初始化(rkbin ddr v1.23)、bl31 v1.44。

**载板侧(DC-A568-V06 规格书 2025-07-11 已确认,PDF 在 `~/marr-materials/`)**:

- **网口:双路 10/100M 百兆**(RJ45 + 4P 座,百兆变压器 T±/R± 定义)——**与核心板 EVB 的千兆 RTL8211F/RGMII 是不同设计,移植时网口节点不可照抄核心板 dts**;PHY 芯片型号规格书未标,待安卓固件 dts 或原理图;
- **串口映射(全定)**:调试 = UART2;串口 1 = ttyS1、串口 3 = ttyS3(两路共用一座,默认 TTL,可选贴 RS232);**串口 4 = ttyS4,默认 TTL,可选贴 RS485**——RS485 对应 uart4,非核心板 dts 暗示的 uart5;
- **CAN:无**(规格书全文零提及)——A568 不引出 CAN,CAN 方案维持 USB 适配器(gs_usb),悬案关闭;
- USB:5 Host + 1 OTG,**对外供电总上限 3A**(机器人供电预算需计入);
- 存储:eMMC 8/16/32/64/128G 可选(本板 16G),LPDDR4X 1-8G,TF ≤128G;
- GPIO(5 IO 座):GPIO1_A1(上拉默认)、GPIO3_A6(下拉选配)、GPIO3_A3(IO5)等;触摸/屏相关脚(GPIO0_B5/B6、GPIO4_C6)属显示域,随显示一起 disabled;
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

- **厂商 Linux SDK** 已解压至本机 `~/rk356x-sdk/`(20G,vendor 内核 5.10.226 / U-Boot 2017.09,单提交 rk3568 first commit 20250808)。pinmux 移植参照:`kernel/arch/arm64/boot/dts/rockchip/ztl-YM568-linux.dts`,include 链 `rk3568-evb8-lp4-v10.dtsi → rk3568-evb1-ddr4-v10.dtsi → rk3568-linux.dtsi`;RGMII 延迟、PHY 复位、UART/CAN/RTC 引脚均在上链中,逐条抄录。
- **rkbin blob**(idbloader 组装用):`~/rk356x-sdk/rkbin/bin/rk35/`——`rk3568_ddr_*_MHz_v1.23.bin`、miniloader、`bl31_v1.44.elf`、`bl32_v2.15.bin`。
- **分区表参考**(厂商 A/B 方案):`~/rk356x-sdk/device/rockchip/.chips/rk3566_rk3568/parameter-buildroot-fit-ab.txt`,对照我们的 wic 布局。
- **硬件资料**(规格书/原理图):wiki"5. 硬件资料"(提取码 ivc6)——确认 GPIO 引出表、RS485 具体挂在哪路 UART、CAN1 引到哪个连接器。
- **Android 11 SDK**(4.19 内核):未获取,仅在 Linux SDK 信息缺失时再取。
- **厂商预编译镜像 + RKDevTool**:先走通一次厂商镜像的 maskrom 烧录,验证板卡硬件与烧录链路,再上自己的镜像。

## 待确认(⚠ = 阻塞 A568 dts)

- ⚠ **百兆 PHY 型号与接法**(RMII 还是 RGMII 降速)——规格书未标,途径:A568 安卓固件解包出 dts,或向定昌要原理图;
- ⚠ 串口 1/3/4 的 pinctrl 引脚组(m1 还是 m0)——同样从安卓固件 dts 取;
- A568 是否基于 MXM314 核心板(SOM)架构——影响 PMIC/DDR 等 SOM 侧事实沿用与否(不阻塞首启,影响电源管理节点);
- maskrom VID/PID 实测(board.yml 用);
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
