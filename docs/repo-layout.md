# marr 工程目录设计(独立发行版)

> 相关文档:[board-support.md](board-support.md)(板卡管理) · [sdk/manager/docs/flash-tool.md](../sdk/manager/docs/flash-tool.md)(烧录工具设计,属 manager 项目)

## 定位

> marr — Delivering motor intelligence learned in simulation to the cerebellum of real machines. In memory of David Marr (1945–1980).

marr 项目把仿真中习得的运动智能交付到真实机器的"小脑"——低层运动控制硬件。本仓库是 marr 的**独立 Linux 发行版**:自有发行版配置与镜像目标,交付物是各适配工控板的**整卡 GPT 镜像文件**(wic 格式,含 bootloader、sha256)。镜像烧好,小脑即就绪。

**为什么是 Linux**:小脑在本地跑学到的策略,推理运行时(ONNX Runtime)与 Rockchip NPU 工具链只有 Linux 生态可用;镜像化交付、OTA、与"大脑"侧的 ROS 2/DDS 通信也都是 Linux 形态。实时性按控制环频率分层:1ms 级运动环用主线 PREEMPT_RT(6.12 起已并入主线,我们锁定的 LTS 天然可用);≥10kHz 电流环不属于 A 核上任何 OS 的领域,需要时以 Rockchip AMP(RT-Thread 独占一核、OpenAMP 通信)或伴生 MCU 解决,该固件作为镜像内容打包进发行版,不推翻本架构。

硬件策略:**不自研板**。作为开源项目,marr 适配并长期维护市面上保有量较大的工控板;多 SoC 是既定方向——当前只有 Rockchip,后续会引入其他 SoC 家族。因此仓库主体按"SoC 无关的发行版层(`meta-marr`)+ 每 SoC 家族一个 BSP 层(当前的 `meta-marr-rockchip`、未来的 `meta-marr-<soc>`)"切分,发行版层永不感知具体 SoC。

主机侧的板卡管理与烧录工具(对标 NVIDIA SDK Manager)是本仓 `sdk/manager` 下的**独立项目**——"独立"体现在目录、构建栈、流水线三重隔离,而非另立仓库;它与发行版以 CI 发布的 `index.json` 为唯一契约。用户视角的核心问题"**这块板支持到什么程度**"由 `boards/` 单点描述,经索引呈现在工具里(见下文 boards/ 与 sdk/manager 两节)。

## 技术选型:Yocto/OE + kas

"独立发行版、多板卡、上游可锁定、CI 可复现"这组需求落在 Yocto 上:

- 发行版身份由 `conf/distro/marr.conf` 定义(`DISTRO = "marr"`、版本、编译策略),产出自带 `/etc/os-release`;
- 多板卡 = 多 `MACHINE`,同一套 distro 配置覆盖所有机器;
- 上游(openembedded-core、meta-rockchip 等)按 revision 锁定,发行版的"独立"体现为:上游只是原料,版本与内容由本仓决定;
- 构建入口用 **kas**:layer 组合、机器、目标写在 `config/kas/*.yaml`,`kas-container` 本地与 CI 同一条路,不再自写 Dockerfile/环境脚本。

> 选型记录(2026-09):曾认真评估过两条替代路线,最终仍定 Yocto。**Debian/Ubuntu 基座**(mmdebstrap + apt + 自编内核,即 Jetson 产品形态与 Armbian 模式):生态最快,但发行版身份依附 Debian、基线由上游定,与"独立发行版"定位冲突;**Buildroot**:上手快,但本质是"每板一个固件生成器",无包管理、增量升级弱。Yocto 的代价(学习曲线陡、首次构建小时级、需要自建 runner)由 ci.md 的缓存策略对冲。若未来被迫降级,顶层 `boards/`、`config/`、CI 的结构可以保留。

## 顶层布局

```text
marr/
├── README.md
├── .gitignore                # 忽略一切构建产物:image/out/、*.img、下载缓存等
│
├── meta-marr/                # ① 发行版层:发行版身份与自有内容
│   ├── conf/
│   │   ├── layer.conf
│   │   ├── distro/marr.conf  # DISTRO=marr:名称、DISTRO_VERSION、安全/许可策略
│   │   └── include/marr-versions.inc     # 关键组件版本统一锁定(onnxruntime、ros2/cyclone 等)
│   ├── recipes-core/
│   │   ├── images/marr-image.bb          # 默认镜像目标(FSTYPE=wic)
│   │   └── marr-release/                 # /etc/os-release、/etc/marr-release 标识
│   ├── recipes-support/onnxruntime/      # ONNX Runtime 推理运行时(全发行版唯一版本)
│   └── recipes-*/           # 其余自有软件包(marr 运行时组件,按类别建 recipes-*)
│
├── meta-marr-rockchip/       # ② BSP 层:机器、内核、bootloader、分区布局
│   ├── conf/machine/
│   │   ├── include/rk3568.inc            # SoC 级公共配置(RK3568;新 SoC 加新 .inc)
│   │   └── dc-a568.conf                  # MACHINE 名 == board-id(见下文)
│   ├── recipes-kernel/linux/             # 内核 recipe:externalsrc 接根 kernel/ submodule,
│   │                                     #   dts/config/patches 自 boards/<vendor>/<model>/ 注入
│   ├── recipes-bsp/u-boot/               # U-Boot
│   ├── recipes-bsp/rkbin/                # Rockchip 二进制 blob(idbloader 等)
│   └── wic/marr-sdimage.wks              # 整卡 GPT 分区布局(所有板共用的模板放这,差异走机器覆盖)
│
├── config/
│   └── kas/                  # ③ 构建描述(唯一入口)
│       ├── marr-base.yaml    # 公共:上游 layer 锁定(poky、meta-rockchip…)、DL_DIR/SSTATE
│       └── dc-a568.yaml        # 每板:MACHINE + 目标(marr-image)
│
├── boards/                   # ④ 板卡目录:厂家/型号两级;支持情况 + 板级硬件描述
│   ├── schema/board.schema.json
│   └── <vendor>/<model>/     # 首板:gzdc/dc-a568(定昌 DC_A568);型号目录名 == board-id == MACHINE
│       ├── board.yml         # 支持状态、烧录路径可用性、VID/PID、显示名、文档链接
│       ├── dts/              # 板级设备树(主线缺失或不准时才自维护;优先用内核树内的)
│       ├── config/           # 内核配置片段(defconfig / fragment)
│       └── patches/          # 板级内核补丁(升 LTS 时清退重审)
│
├── kernel/                   # ⑤ Linux 内核源:git submodule 指向上游最新 LTS tag
│                             #   指针即版本;树内零本地提交,定制全走 boards/ 的补丁
│
├── scripts/                  # ⑥ bring-up 阶段的手工构建脚本(env.sh 公共环境 + kernel 配置/编译/打包)
│                             #   限载纪律:默认 -j6 + nice;Yocto 就绪后降级为快速重编/调试工具
│
├── sdk/                      # ⑦ 主机侧工具项目的家(当前只有 manager)
│   └── manager/              # 对标 NVIDIA SDK Manager:板卡管理与烧录
│       ├── Cargo.toml        # 独立 Cargo workspace,不与发行版构建耦合
│       ├── crates/           # manager-cli(薄壳) / manager-core(核心,零特权 I/O)
│       │                     # manager-writer-blkdev / manager-writer-rockchip(ImageWriter 实现)
│       ├── gui/              # Phase 3:Tauri 向导
│       ├── schema/           # index.json 契约 schema + 生成器(发行版 CI 锁版本调用)
│       └── docs/flash-tool.md # 烧录工具设计(自根 docs/ 迁入)
│
├── .github/workflows/        # ⑧ distro.yml + manager.yml:两条互不阻塞的流水线,详见 docs/ci.md
│
└── docs/
    ├── board-support.md      # 板卡管理设计
    └── repo-layout.md        # 本文档
```

与旧版"板卡支持仓"设计的映射:根文件系统定制从 `image/rootfs/` overlay 目录改为 OE 惯例的 recipe + FILES;分区模板 `image/partition/` 变为 `wic/*.wks`;`image/Dockerfile + build.py` 被 kas 取代;新增的 `meta-*` 两层是发行版的主体。

## meta-marr:发行版层

只放"与具体 SoC 无关"的内容:distro 配置、镜像目标、自有软件包。判断标准:**引入下一个 SoC 家族时,这个层必须原样不动**——新家族 = 新增一个 `meta-marr-<soc>` BSP 层 + 该家族的机器配置与 kas 文件,仅此而已。

**ONNX Runtime 版本统一管理**:策略推理运行时是全发行版共享的关键组件,版本只在一处定义——`conf/distro/include/marr-versions.inc` 声明 `PREFERRED_VERSION_onnxruntime`,树内只保留**一个**版本的 recipe(上游源码 tarball 构建,不 fork;首期 CPU 推理走 XNNPACK/NEON,RK3568 NPU 的 RKNN 路线后续单独评估)。升级 = 一次显式替换 recipe 并同步 versions.inc 的提交,与内核 submodule 指针同一纪律;板级 bbappend 只准加配置、不准换版本,CI 校验全树版本唯一。当前版本写入 `/etc/marr-release` 与构建清单,并经 `index.json` 对外发布——大脑侧据此对齐模型的 opset 兼容性。**ROS 2 + Cyclone DDS 同此机制管理**(通信栈选型与完整组件清单见 [distro-scope.md](distro-scope.md))。

## meta-marr-rockchip:BSP 层

- **机器名即 board-id**(kebab-case,首板 `dc-a568`),全链路一致:机器配置、kas 文件、`boards/` 目录、镜像文件名、`index.json` 条目。
- SoC 级公共配置进 `conf/machine/include/*.inc`,单板配置只写差异,不许复制粘贴。
- 与上游 meta-rockchip 的关系:起步时机器配置尽量继承上游 MACHINE,本层只放差异与覆盖。内核已定为上游 LTS(submodule,见下节),不再有主线/vendor 之分;确需 vendor 特性时以板级补丁回补。
- 整卡镜像的分区布局在 `wic/marr-sdimage.wks`;烧录工具三条路径(SD 直写 / maskrom USB / ums)烧的都是它,本仓不产出"分区散件"。

## config/kas:构建入口

- `marr-base.yaml` 锁定跨 SoC 的公共上游(oe-core/poky)——这是"独立发行版"对上游的边界;本仓自有 layer 以相对路径引入。SoC 家族相关的上游(如 meta-rockchip)在家族首板的 kas yaml 里引入并锁定,新家族不得改动 base 的既有锁定。
- 每板一个 yaml(机器 + 镜像目标),本地 `kas-container build config/kas/<board>.yaml` 与 CI 完全同一条路。
- kas 只管 layer;内核源不走 kas——构建前 `git submodule update --init kernel/`(本地与 CI 同一步骤)。
- 下载与共享状态目录(DL_DIR/SSTATE_DIR)在 base yaml 里指到仓库外,避免误入库。

## boards/:板卡目录(厂家/型号)

用户视角的核心问题是"**这块板支持到什么程度**"。答案只在 board.yml 一处维护:总体状态(`stable` / `beta` / `planned`)、分项可用性(烧录路径 SD 直写 / maskrom / ums 各自是否可用、已知问题链接)、内核版本,连同显示名、VID/PID、存储布局提示。这些内容经 `index.json` 呈现:manager 的 `boards list` 第一屏就是支持情况,官网下载页同源;README 不再手写支持矩阵,避免双写漂移。收录哪块板也是显式决策:**只进市面上保有量较大、上游(内核/U-Boot)支持较好的工控板**——`planned` 表示已列入适配计划,`beta` 起才有镜像产出,`stable` 意味着烧录三条路径与回归全过。

目录组织为 `boards/<厂家>/<型号>/` 两级。厂家是板卡的制造方,目录名用厂家简称的小写(定昌电子 `gzdc/`,首板型号 `dc-a568/`:官方型号 DC_A568,RK3568 一体板,4GB 内存 + 16GB eMMC,目录名取型号的 kebab-case;将来 `radxa/`、`firefly/` 一类同理)。型号目录名即 board-id,也是 MACHINE 名,跨厂家全局唯一。

型号目录是**板级硬件事实的家**:`dts/`(板级设备树,原则见下)、`config/`(内核配置片段)、`patches/`(板级内核补丁,升 LTS 时清退重审)。dts 的原则是**优先用内核树内现成的**:市面保有量大的板,主线通常已收录其板级 dts 与 SoC 级 dtsi,此时 `dts/` 留空,机器 conf 直接指向树内设备树;只有主线缺失或不准确的板(如小厂板 DC_A568)才在 `dts/` 自行维护板级设备树,并尽可能向上游提交、争取清空。machine conf 只声明 Yocto 侧变量并指明自己对应的 board 目录;CI 校验每台机器都解析到唯一存在的 `<厂家>/<型号>`,且 dts、config、patches 被内核 recipe 实际引用。

## kernel:内核源(git submodule)

内核用**上游 mainline 的最新 LTS 分支**,以 submodule 引入(`git submodule update --init kernel/`),策略四条(落仓参考:2026-09 时最新 LTS 为 6.18 系列,首版指针取当时最新的 6.18.y):

- **指针即版本**:submodule 指向的 commit 就是本发行版的内核版本,recipe 不写 SRCREV。升 LTS 是一次显式移动指针的提交,同时清退各板 `patches/`、跑全板回归。
- **树内零本地提交**:submodule 永远指向上游 tag。所有定制只以板级 dts/config/patches 叠加;一旦内核树里出现本地提交,它就悄悄变成了 fork,指针随之失去意义——CI 校验内核工作区干净。
- **单一内核树服务全部 SoC 家族**:这是选 mainline LTS 的本意;个别特性确需 vendor 树时以补丁回补,不引入第二棵树。
- **接线方式**:meta-marr-rockchip 的内核 recipe 用 `externalsrc` 指向 `${MARR_ROOT}/kernel/`;`${MARR_ROOT}` 由 layer.conf 定义,机器 conf 声明自己对应的 `boards/<厂家>/<型号>/`,dts、config、patches 经 FILESEXTRAPATHS 从那里注入。

## sdk/manager:板卡管理与烧录工具

对标 NVIDIA SDK Manager 的独立项目:浏览板卡支持情况、选版本、下载校验、烧录、复位。交互与协议细节见其自己的 [flash-tool.md](../sdk/manager/docs/flash-tool.md),这里只定它与仓库的关系:

- **独立项目,同仓隔离**:发行版构建栈(Yocto/Python/Docker)与 manager(Rust)零依赖;manager 有自己的 Cargo workspace、版本号与二进制发布节奏,CI 按路径过滤,manager 发版不被镜像构建阻塞,反之亦然。
- **数据驱动,不硬编码板卡**:manager 只认识 `index.json`;哪块板、什么状态、哪些烧录路径可用,全部来自数据。新增板卡 = `boards/` 加目录 + CI 出索引,manager 零改动。
- **契约归 manager 持有**:`sdk/manager/schema/` 是 index.json 的 schema 与生成器的唯一住所,发行版 CI 锁定版本调用——同一仓库让契约只有一个家,两侧不会各持一份漂移。
- 未来其他主机侧工具(如首启 provision)同样以 `sdk/<项目>` 进入,互不纠缠。

## CI 与发布

CI 按路径过滤成两条互不阻塞的流水线。**发行版流水线**(boards/、meta-*、config/、kernel/ 变更触发):board.yml schema 校验、机器与 board 目录一致性校验、内核 submodule 工作区零本地提交校验 → `kas-container build` → 产物为 `<board>-<version>.wic.zst` + sha256(+ bmap)→ 调用 `sdk/manager/schema` 发布的索引生成器(锁定版本)更新 `index.json` → 全部挂到 GitHub Release。**manager 流水线**(sdk/ 变更触发):构建并发布各平台二进制,按 manager 自己的版本号走,不被镜像构建牵连。`index.json` 必须自足(支持状态、烧录路径提示、VID/PID、内核与 ONNX Runtime 版本)。workflow 文件、触发矩阵、缓存与 runner 策略、发布通道的完整设计见 [ci.md](ci.md)。

## 设计原则

1. **一个仓库,两个项目,一个契约**:发行版(Yocto/Python 栈)与 sdk/manager(Rust 栈)在目录、构建栈、流水线上三重隔离,唯一接口是 `index.json`;新增板卡只改 boards/ 数据,不改 manager 代码。
2. **单一事实源,分域维护**:硬件构建事实只在 machine conf,对外发布事实只在 board.yml,CI 保证两者不漂移。
3. **上游即原料**:上游 layer 一律 kas 锁版本;对上游的修改在本仓 layer 里以覆盖/追加表达,不 fork 整层。内核同理:`kernel/` submodule 指向上游 LTS tag,树内零本地提交,定制只以板级 dts/config/patches 叠加。
4. **产物不入库**:仓库只含配方与代码;`build*/`、`downloads/`、`sstate-cache/`、镜像、`index.json` 一律 ignore。
5. **目录随实现生长**:不预建空目录;每个 recipes-* 目录在被真实 recipe 使用时才创建,类别名沿用 OE 惯例(`recipes-core` / `-bsp` / `-kernel` / `-devtools` / `-support` 等),不自造新类别。

## 下一步(Phase 1 脚手架)

`meta-marr` 最小集(distro conf + marr-image + marr-release)、`meta-marr-rockchip` 的 DC_A568 机器配置(rk3568,优先继承上游 meta-rockchip)、`config/kas/dc-a568.yaml`、`kernel/` submodule 接入最新 LTS、`boards/schema` + 首板 `boards/gzdc/dc-a568/`(board.yml 含支持状态字段,dts/config/patches 首版)、CI 双流水线骨架。首版镜像从最小可启动集起步,自有运行时组件随后按 recipe 逐个进入 `meta-marr`。

`sdk/manager` 同步起步:core + cli 最小可用(`boards list` / `releases` / `flash --img --to sd:<dev>`),index.json 首版 schema 与生成器一并交付。工具可先吃一份手写样例索引开发,不等镜像流水线就绪。
