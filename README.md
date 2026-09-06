# marr

> Delivering motor intelligence learned in simulation to the cerebellum of real machines.
> In memory of David Marr (1945–1980).

marr delivers motor intelligence learned in simulation to the "cerebellum" of real machines — the low-level motion-control hardware. This repository is the marr independent Linux distribution (Yocto/OE): it builds whole-disk GPT images for the industrial boards it supports. Flash the image, and the cerebellum is ready.

- **Hardware**: no in-house boards — marr adapts and maintains industrial boards with a large installed base. Multiple SoC families are on the roadmap (one BSP layer per family).
- **Kernel**: latest upstream LTS, vendored as a git submodule (`kernel/`), zero fork. Board-level dts, kernel config fragments, and patches live under `boards/<vendor>/<model>/`.
- **Runtime**: ONNX Runtime for policy inference — built from upstream source, pinned to a single distro-wide version (`meta-marr/conf/include/marr-versions.inc`), published via `index.json`.
- **Comms**: ROS 2 + Cyclone DDS for brain ↔ cerebellum communication, version-pinned the same way.
- **Build entry point**: `git submodule update --init kernel/`, then `kas-container build config/kas/<board>.yaml` — the exact same path locally and in CI.
- **Deliverables**: CI publishes `<board>-<version>.wic.zst` + sha256 and generates `index.json` for the flashing tool.

## Repository map

| Path | Contents |
|---|---|
| `meta-marr/` | Distro layer: distro config, image targets, first-party packages (SoC-agnostic) |
| `meta-marr-rockchip/` | Rockchip BSP layer: machines, kernel, bootloader, partition layout |
| `config/kas/` | Build descriptions: upstream pinning + one YAML per board |
| `kernel/` | Linux kernel source (submodule pinned to the latest upstream LTS, zero local commits) |
| `boards/` | Board directories (vendor/model): board.yml support status + board-level dts, kernel config, patches |
| `sdk/manager/` | Board management & flashing tool (NVIDIA SDK Manager counterpart, separate project) |
| `docs/` | Design docs: [repo-layout.md](docs/repo-layout.md) (repository layout), [distro-scope.md](docs/distro-scope.md) (component scope), [ci.md](docs/ci.md) (CI/CD), [bringup-dc-a568.md](docs/bringup-dc-a568.md) (first-board Linux bring-up) — in Chinese |

## Status

Design phase. The flashing tool (`sdk/manager`) and the distro share a single contract: the CI-generated `index.json`. The tool is data-driven with no hard-coded boards; support status — which board, which state, which flash paths work — is maintained in one place under `boards/`. board-support.md will be synced in later; flash-tool.md (flashing tool design) will move to `sdk/manager/docs/`.
