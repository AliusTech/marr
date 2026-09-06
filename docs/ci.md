# marr CI/CD 设计(GitHub Actions)

> 相关文档:[repo-layout.md](repo-layout.md)(工程目录) · index.json 契约归 sdk/manager(其设计文档迁入 `sdk/manager/docs/`)

一条总原则:**本地与 CI 同一条构建路径**(kas-container)。CI 做的是编排、缓存与发布,不引入任何只在 CI 里存在的构建逻辑。

## 总览:两个 workflow,一条公共门槛

| workflow | 触发路径 | 职责 |
|---|---|---|
| `distro.yml` | `boards/**`、`meta-marr/**`、`meta-marr-rockchip/**`(新 BSP 层加入时补一行)、`config/**`、`kernel`(含 submodule 指针变更) | 校验 → 构建镜像 → 发布镜像与 index.json |
| `manager.yml` | `sdk/**` | 测试 → 发布各平台二进制与索引生成器镜像 |

两个 workflow 互不触发、互不阻塞;`validate` 作业是 distro 一切构建的前置门槛。

## distro 流水线

### validate(每次都跑,分钟级,GH hosted)

1. board.yml 的 JSON Schema 校验(`boards/schema/board.schema.json`);
2. 机器 ↔ 板目录一致性:每台 MACHINE 解析到唯一的 `boards/<厂家>/<型号>/`,dts、config、patches 被内核 recipe 实际引用;
3. 内核 submodule 工作区零本地提交校验;
4. kas yaml 静态检查(引用的 layer 与 MACHINE 存在);
5. 关键组件版本唯一性:onnxruntime 等全树单一版本,且与 `marr-versions.inc` 的锁定一致。

### build(矩阵 = 板卡自动发现)

- **矩阵发现**:先用一个 discovery 作业列出 `boards/*/*/board.yml`,输出 matrix——新板进仓自动纳入 CI,不改 workflow。
- **PR 流**:validate + 只构建**基线板**(首期 dc-a568,后续由 board.yml 的 `ci.baseline` 字段标记);带 `full-ci` 标签的 PR 才构建全矩阵。产物挂 workflow artifact,保留 14 天,不发 Release。
- **main 流**:全矩阵构建,产物同样走 artifact;构建过程为 DL_DIR/SSTATE 贡献缓存。
- **tag 流**(`v*`,建议 calver,如 `v2026.09.0`,与 DISTRO_VERSION 对齐):全矩阵构建 → 进入 release 作业。

### 构建环境与缓存

- 统一用 `kas-container` 执行,镜像 **digest 锁定**;`git submodule update --init kernel/` 是前置步骤。
- runner 分工:validate 与 release 用 GH hosted;**构建作业跑自建 runner**(Yocto 全量需要 ≳8 核 / 32GB 内存 / 200GB 盘,自建 runner 常驻 DL_DIR 与 SSTATE 目录,增量构建的收益远大于任何托管缓存)。过渡期可用 GH large runner,但没有常驻盘。
- 并发控制:同 ref 的新提交取消旧构建(concurrency 按 workflow+ref 分组);tag 流不取消,必跑完。

### 发布与 index.json

release 作业(仅 tag 流;整个 workflow 默认 `contents: read`,只有此作业提升为 `write`):

1. 汇总本 tag 全部 `<board>-<version>.wic.zst` + sha256(+ bmap)与**构建清单**(内核 submodule commit、各 layer 锁定版本、kas 版本、onnxruntime 等锁定组件版本)——构建可追溯到指针;
2. 调用**索引生成器**:`sdk/manager/schema` 发布的 OCI 镜像 `ghcr.io/<org>/marr-index-gen@sha256:…`(**digest 锁定**;manager 发版时更新)。输入本仓全部 Release 与 `boards/` 元数据,**全量重生成** index.json——不做增量合并,杜绝索引漂移;
3. 镜像与 index.json 挂到该 tag 的 GitHub Release;index.json 同时提交到 **`dist` 分支**(该分支只放 index.json 与分版本元数据),烧录工具的默认源就是这个稳定 URL:`https://raw.githubusercontent.com/<org>/marr/dist/index.json`。

## manager 流水线

- PR / main:三平台矩阵(Linux x86_64 与 aarch64、macOS、Windows)跑 `cargo fmt --check` + `clippy` + `test`;
- tag `manager-v*`:构建发布各平台二进制(按 manager 自己的版本号,与发行版镜像的 `v*` 命名空间互不冲突),并构建推送 `marr-index-gen` 镜像,供 distro 流水线锁定引用;
- manager 的发版节奏完全独立,不等镜像构建。

## 权限与安全

- 两个 workflow 顶部声明最小权限(`contents: read`),仅 release 作业按需提升;外部 PR 拿不到 secret;
- 发布产物一律附构建清单(内核 commit、layer 版本、kas 版本),链路回到 submodule 指针。

## 分阶段落地

- **P1**:validate + 基线板 `workflow_dispatch` 手动构建 + artifact 下载,先证明"本地 = CI"。
- **P2**:矩阵自动发现、main/tag 流、自建 runner 常驻缓存、`dist` 分支索引通道、`marr-index-gen` 镜像化。
- **P3**:定时巡检上游 LTS 新版本(指针可升级时自动开 issue/PR)、构建清单与来源证明完备化。
