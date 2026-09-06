# DC_A568 Linux Bring-up 清单

> 相关文档:[repo-layout.md](repo-layout.md)(工程目录) · [distro-scope.md](distro-scope.md)(组件范围)。本文是首板 Linux 移植的执行清单:板卡事实、已定决策、参考资料、待确认项、验收标准、任务顺序。实测结果随时回填。

## 板卡事实

定昌电子(与智通利为同一家公司)DC_A568 一体板(RK3568,4×A55,4GB 内存 + 16GB eMMC,DC 12V)。

> **资料口径(2026-09 澄清)**:目前手上的 Linux SDK(wiki 同源)是**核心板家族(C568/YM568)的配套资料**,不含 A568 一体板专属 dts——SDK 全树唯一的定制板型即 `ztl-YM568-linux.dts`。因此下述外设事实是**核心板/EVB 参照**,其中"核心板侧"项在 A568 基于同款 SOM 时大概率沿用,"载板侧"项必须以 A568 专属资料或实测为准(尤其产品页"百兆"与 EVB 千兆 RTL8211F 的矛盾,可能正是两块板载板设计不同所致)。

**核心板侧(若 A568 = 该 SOM + 载板,则大概率沿用)**:PMIC RK809、vdd_cpu TCS4525(i2c0@0x1c)、eMMC = `&sdhci`、DDR 初始化(rkbin ddr v1.23)、bl31 v1.44。

**载板侧(参照 EVB dts,A568 待逐项确认)**:

- 网口:gmac0/gmac1 = RGMII + RTL8211F(千兆),RGMII 延迟 gmac0 tx=0x3c/rx=0x2f、gmac1 tx=0x4f/rx=0x26,PHY 复位 GPIO2_D3/D1——**A568 产品页标"百兆",载板 PHY 可能不同,待原理图**;
- CAN:SoC CAN1(can1m1 = GPIO4_C2/C3)EVB 已启用——**A568 载板是否焊收发器待确认**;
- UART:调试 UART2(m0,1500000);UART3/4/5 = TTL/RS232/RS485 三路(m1),RS485 方向脚 GPIO3_A6——**对应关系与引出待确认(产品页称 3 TTL + 1 调试)**;
- RTC:HYM8563 @ i2c5 0x51,中断 GPIO0_D3;
- TF = `&sdmmc0`;USB Host 5V 使能 GPIO1_A4;mini-PCIe 3V3 GPIO3_A3、风扇 GPIO3_C4、功放 GPIO3_C5;
- 厂商文档:<http://wikicn.gzdcsmt.com/wendang_id_59.html>(C568 家族)。

## 已定决策(bring-up 范围)

1. **Bootloader**:主线 U-Boot(最新稳定版,evb-rk3568 defconfig 基线)+ rkbin DDR blob 拼 idbloader;rkbin 在 `recipes-bsp/rkbin/` 锁版本。
2. **内核**:6.18 LTS submodule;arm64 defconfig + 板级 fragments(`boards/gzdc/dc-a568/config/`);**PREEMPT_RT 首日开启**;console = UART2 @1500000(串口适配器需 CP2102/FT232 级)。
3. **裁剪**:显示/音频**不支持**(明确不需要,非后置);BT、mini-PCIe 后置;WiFi 默认后置(待最终确认);dts 中相关节点一律 disabled。
4. **dts 最小范围**:eMMC、TF、UART2 console、USB(Host + OTG)、GMAC(路数与 PHY 待硬件资料)、HYM8563、DW 看门狗。
5. **wic 分区**:boot 256MB + rootfs A/B 各 4GB + data 剩余(约 7.5GB),ext4,A/B 第一版就进 `marr-sdimage.wks`。
6. **上游 layer**:poky + meta-rockchip + meta-openembedded(kas 锁定);meta-ros 不进 bring-up。
7. **首版镜像**:systemd + ssh + networkd + marr-release;ONNX Runtime 不进首启镜像。
8. **烧录路径**:TF 卡槽在,SD 直写可用——本板三条路径(SD 直写 / maskrom USB / ums)全通,board.yml flash paths 记全集。
9. **CAN(2026-09,待重审)**:现行决定为 USB 适配器走 candleLight/gs_usb(fragment `config/kernel-can.cfg`),`CAN_ROCKCHIP` 不开。核心板 EVB dts 证实 SoC CAN1 可引出(can1m1 = GPIO4_C2/C3),**但 A568 载板是否焊收发器待确认**——若确认有,建议改"原生 CAN1 为主、USB 适配器仅调试",fragment 加 `CAN_ROCKCHIP=y`。驱动器经典 CAN / CAN-FD 之选仍悬而未决。

## 参考资料与获取(2026-09 已落地本机)

- **厂商 Linux SDK** 已解压至本机 `~/rk356x-sdk/`(20G,vendor 内核 5.10.226 / U-Boot 2017.09,单提交 rk3568 first commit 20250808)。pinmux 移植参照:`kernel/arch/arm64/boot/dts/rockchip/ztl-YM568-linux.dts`,include 链 `rk3568-evb8-lp4-v10.dtsi → rk3568-evb1-ddr4-v10.dtsi → rk3568-linux.dtsi`;RGMII 延迟、PHY 复位、UART/CAN/RTC 引脚均在上链中,逐条抄录。
- **rkbin blob**(idbloader 组装用):`~/rk356x-sdk/rkbin/bin/rk35/`——`rk3568_ddr_*_MHz_v1.23.bin`、miniloader、`bl31_v1.44.elf`、`bl32_v2.15.bin`。
- **分区表参考**(厂商 A/B 方案):`~/rk356x-sdk/device/rockchip/.chips/rk3566_rk3568/parameter-buildroot-fit-ab.txt`,对照我们的 wic 布局。
- **硬件资料**(规格书/原理图):wiki"5. 硬件资料"(提取码 ivc6)——确认 GPIO 引出表、RS485 具体挂在哪路 UART、CAN1 引到哪个连接器。
- **Android 11 SDK**(4.19 内核):未获取,仅在 Linux SDK 信息缺失时再取。
- **厂商预编译镜像 + RKDevTool**:先走通一次厂商镜像的 maskrom 烧录,验证板卡硬件与烧录链路,再上自己的镜像。

## 待确认(⚠ = 阻塞 A568 dts)

- ⚠ **A568 一体板是否基于 C568 核心板**(板上有无 SOM,或为单板设计)——决定核心板侧事实能否沿用,问定昌或看板;
- ⚠ **A568 专属资料**:规格书/原理图,或其 Android 固件包内的 dts(A568 是安卓一体板,定制 dts 大概率在安卓包里;注意 wiki 的 `ztl_c56x_11os` 安卓 SDK 也是 C56X 家族,非 A568);
- ⚠ 载板 PHY 实际型号与路数(百兆/千兆);
- ⚠ A568 载板 CAN1 是否焊收发器;
- RS485 对应哪路 UART(方向脚 GPIO3_A6 亦待证实);
- maskrom VID/PID 实测(board.yml 用);
- WiFi/BT 模组型号(已后置,不阻塞);
- A568 专属 GPIO 命名表(规格书内)。

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
