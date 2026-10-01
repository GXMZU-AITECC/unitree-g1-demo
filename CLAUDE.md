# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Identity
This is a **Unitree G1 humanoid robot reinforcement learning** tutorial and development project.
**Goal**: Help beginners set up Isaac Lab/Isaac Sim for G1 RL training, maintain environment documentation.

## Host System
- Ubuntu 26.04, AMD Ryzen 7 6800HS, NVIDIA RTX 3080 Ti 16GB, driver **580.159.03** / CUDA 13.2
- 14GB RAM, 300GB NVMe (~238GB free after Isaac Sim)

## Stack
- **Simulation**: Isaac Sim 5.1.0 via Docker NGC (`nvcr.io/nvidia/isaac-sim:5.1.0`, ~23GB)
- **Python**: Miniconda (`env_isaaclab`=3.10, `env_ros`=3.12) — host Python 3.14 NEVER used
- **ROS**: ROS 2 Lyrical Luth (native Ubuntu 26.04, at `/opt/ros/lyrical/`)
- **RL**: RSL-RL (`rsl-rl-lib==5.0.1`, installed to persistent pip_pkgs)
- **GPU**: NVIDIA Container Toolkit 1.19.1
- **Deploy**: C++17, ONNX Runtime 1.22.0, unitree_sdk2 (on G1 robot), DDS middleware

## Directory Layout
```
~/projects/g1-rl/
├── configs/             # 用户参数配置文件 (g1_config.py)
├── workspace/           # Docker mount → /workspace inside container
├── sim/                 # Cloned repos (unitree_rl_lab, unitree_ros, IsaacLab) — gitignored
├── scripts/             # start.sh (training) + deploy.sh (deployment) + setup scripts
├── deploy/              # G1 真机部署工具包 (C++ 控制器源码 + ONNX Runtime 安装脚本)
│   ├── include/         #   Shared C++ headers: FSM, Isaac Lab env wrappers, algorithms
│   ├── g1_29dof/        #   G1 velocity-tracking controller (CMake project → g1_ctrl)
│   │   ├── src/         #     State_RLBase.cpp (velocity RL), State_Mimic.cpp (motion mimic)
│   │   └── config/      #     config.yaml (FSM) + policy/velocity/v0/ (ONNX + deploy.yaml)
│   ├── thirdparty/      #   ONNX Runtime binary (gitignored → downloaded by install script)
│   └── install_onnxruntime.sh
├── 5_deployment/        # Phase 2 tutorials: ONNX export, C++ build, FSM, real robot deployment
├── docs/                # Architecture notes, training logs, failure analysis, hardware profile
├── logs/ models/ data/  # Runtime dirs, gitignored
```

`sim/`, `workspace/`, `models/`, `logs/`, `data/` are runtime artifacts and NOT committed.
`deploy/` IS committed (C++ source code for real-robot deployment).

## Key Commands

```bash
# System setup (one-time)
bash scripts/setup_system.sh         # git/docker/nvidia-ctk/ros2 + docker proxy

# Conda environments
bash scripts/setup_miniconda.sh      # env_isaaclab (3.10) + env_ros (3.12)

# Isaac Sim container
bash scripts/launch_isaac_sim.sh     # interactive shell, mounts workspace + sim repos

# === G1 RL training workflow (core) ===
cd ~/projects/g1-rl

# Install training deps (one-time, or after pip_pkgs cleared)
bash scripts/start.sh install

# 所有训练参数在 configs/g1_config.py 中配置，按功能分为：
#   TrainConfig  — train / train-gui / resume 共用 (task, num_envs, max_iterations, seed)
#   PlayConfig   — play 专用 (task, num_envs)
# 修改后直接生效，不需要环境变量或 CLI 参数

# Headless training (fast, no GUI)
bash scripts/start.sh train

# GUI training (see robots in real-time)
bash scripts/start.sh train-gui

# Resume interrupted training (interactive checkpoint selection)
bash scripts/start.sh resume

# Playback trained model
bash scripts/start.sh play <run_dir> <checkpoint>

# TensorBoard (monitor training curves)
tensorboard --logdir ~/projects/g1-rl/logs/rsl_rl/unitree_g1_29dof_velocity --bind_all --port 6006

# Quick verification
nvidia-smi                           # GPU driver OK (must be 580.x!)
sudo docker run --rm --gpus all nvidia/cuda:12.4.1-base-ubuntu22.04 nvidia-smi  # Docker GPU OK
conda env list                       # 3 environments present
source /opt/ros/lyrical/setup.bash && ros2 -h  # ROS 2 OK

# === G1 real-robot deployment (Phase 2) ===
bash scripts/deploy.sh help          # show deploy commands
bash scripts/deploy.sh export        # interactive ONNX export from training logs
bash scripts/deploy.sh push <ip>     # rsync deploy/ to G1 robot
bash scripts/deploy.sh install       # install ONNX Runtime + check deps
bash scripts/deploy.sh build         # compile C++ controller (on the robot)

# On the robot:
cd ~/g1-rl-deploy/g1_29dof/build
./g1_ctrl --network eth0             # start controller (FSM Passive→FixStand→Velocity via joystick)
```

## Architecture: How Components Connect

```
Docker (Isaac Sim 5.1.0) → /isaac-sim/ (sim platform)
                             /workspace/ ← ~/projects/g1-rl/workspace
                             /sim/      ← ~/projects/g1-rl/sim
Conda env_isaaclab (3.10)  → Isaac Lab RL training (inside Docker)
Conda env_ros (3.12)       → ROS 2 Lyrical Luth (native host)
NVIDIA CTK                  → Docker --gpus all --user 0:0 passthrough
Clash Verge :7897           → Docker daemon HTTP_PROXY + Git SSH ProxyCommand
```

## Critical Docker Configuration

**`--user 0:0` is REQUIRED** in all `docker run` commands. Without it:
- Container runs as `isaac-sim` user (uid=1234), which cannot write to `/root/.cache/*` (700)
- Shader cache, data store, Python node cache all fail with Permission denied
- Result: **black viewport in GUI mode** (HydraEngine rtx fails to create scene renderer)

`start.sh` has this configured: `DOCKER_BASE="docker run --rm --gpus all --user 0:0 ..."`

## rsl-rl-lib 5.0.1 Compatibility Fixes (4 sites, automated)

Do **not** hand-edit these any more. `scripts/apply_sim_fixes.py` does it idempotently;
`start.sh install` runs it, `start.sh train` warns if it is incomplete.

```bash
python3 scripts/apply_sim_fixes.py --sim-root <repo>/sim --check   # exit 0 = all four good
python3 scripts/apply_sim_fixes.py --sim-root <repo>/sim           # apply; second run = all SKIP
```

Per-site rationale, the real upstream state of each anchor (verified 2026-09-30) and the
IsaacLab version precondition are in `docs/upstream-patches.md`. Short version:

1. `unitree_rl_lab/scripts/rsl_rl/cli_args.py` — `parse_rsl_rl_cfg()` must call
   `handle_deprecated_rsl_rl_cfg(cfg, installed_version)`, otherwise the deprecated
   `stochastic=MISSING` field reaches `MLPModel.__init__()` and raises TypeError.
2. `unitree_rl_lab/scripts/rsl_rl/play.py` — rsl-rl 5.x renamed `PPO.policy` → `.actor`
   and dropped `actor_critic`; export via the runner's own
   `export_policy_to_jit()` / `export_policy_to_onnx()` (note the exact names).
3. `IsaacLab/.../isaaclab_rl/rsl_rl/utils.py` — guard `model_cfg.stochastic` with `hasattr`.
   Upstream `develop` still accesses it unguarded as of 2026-09-27.
4. `unitree_rl_lab/scripts/rsl_rl/train.py` — exactly ONE `handle_deprecated_rsl_rl_cfg()`
   call. A fresh clone has zero (also broken); the "two duplicate calls" wording in older
   notes described a hand-patched local copy.

If a site reports `UNMATCHED`, upstream moved: the script prints both the upstream snippet
it fetched and your file's current region. Fix by hand and tell the maintainers.

## User Configuration

**所有用户可调参数**: `configs/g1_config.py` — 按功能划分为 TrainConfig 和 PlayConfig。

- `TrainConfig`: task, num_envs (默认4096), max_iterations (默认50000), seed (默认43，-1=随机)
- `PlayConfig`: task, num_envs (默认32)

修改后直接生效。不要用环境变量 `TRAIN_NUM_ENVS` / `TRAIN_MAX_ITER` / `TRAIN_SEED`（已删除）。

## Terrain/Scene Configuration

Config file: `sim/unitree_rl_lab/source/unitree_rl_lab/unitree_rl_lab/tasks/locomotion/robots/g1/29dof/velocity_env_cfg.py`

- `COBBLESTONE_ROAD_CFG` (line 46): Default terrain gen config (training + play both inherit)
  - `size=(1.0, 1.0)`: Each sub-terrain is 1×1m (compact for quick training)
  - `num_rows=3, num_cols=3`: 3×3 terrain grid
  - `border_width=2.0`: Flat border around terrain (minimal)
  - Total area = `(num_cols × size[1] + 2×border) × (num_rows × size[0] + 2×border)`
- `RobotEnvCfg.scene.num_envs=4096` (line 413): Training env count (overridden by `configs/g1_config.py` TrainConfig.num_envs)
- `RobotPlayEnvCfg` (line 465): Overrides for playback — `num_envs=4`, terrain `6×6`

## Network (China-specific)
This machine sits behind the GFW. Two proxy layers exist:
1. **Docker daemon**: `HTTP_PROXY=http://127.0.0.1:7897` at `/etc/systemd/system/docker.service.d/http-proxy.conf`
2. **Git SSH**: `ProxyCommand nc -X connect -x 127.0.0.1:7897 %h %p` at `~/.ssh/config`

Both depend on Clash Verge (`verge-mihomo`) running on port 7897. If GitHub/Docker Hub are unreachable, check `ss -tlnp | grep 7897` first.

## Dependency Repos (not committed)
- `~/projects/g1-rl/sim/unitree_rl_lab/` — https://github.com/unitreerobotics/unitree_rl_lab
- `~/projects/g1-rl/sim/unitree_ros/` — https://github.com/unitreerobotics/unitree_ros
- `~/projects/g1-rl/sim/IsaacLab/` — https://github.com/isaac-sim/IsaacLab (cloned locally for reference/fixes)

## Deploy Architecture (Phase 2)

### How Training Connects to Deployment
```
Sim Training (Python/Isaac Sim)              Real Robot (C++/ONNX Runtime)
══════════════════════════════              ═══════════════════════════════
train.py → model_N.pt                       
  │                                         
  ├─ torch.onnx.export() → policy.onnx ───→ OrtRunner::act() (C++ ONNX Runtime)
  └─ export_deploy_cfg() → deploy.yaml ──→ ManagerBasedRLEnv (C++ env wrapper)
                                           
Same observation pipeline:                 Same observation pipeline:
  IMU gyro → base_ang_vel                    Real IMU → base_ang_vel (unitree_articulation.h)
  Quat → projected_gravity                   Real IMU quat → projected_gravity
  Sim joint state → joint_pos/vel            Motor encoder → joint_pos/vel (via DDS)
  Joystick → velocity_commands               Joystick → velocity_commands (via DDS)
                                           
Same action pipeline:                      Same action pipeline:
  network output × scale + offset            network output × scale + offset (joint_actions.h)
  → PD controller (sim)                      → PD controller (real motor firmware)
```

### Key Deploy Files
- `deploy/include/isaaclab/algorithms/algorithms.h` — OrtRunner: ONNX Runtime inference, thread-safe
- `deploy/include/unitree_articulation.h` — BaseArticulation: reads IMU + motor state via DDS
- `deploy/include/param.h` — CLI/config loading, policy directory auto-discovery
- `deploy/g1_29dof/src/State_RLBase.cpp` — RL velocity-tracking FSM state
- `deploy/g1_29dof/main.cpp` — Entry point: DDS init, FSM registration, main loop
- `configs/g1_config.py` — DeployConfig (run_name, checkpoint, robot_ip, robot_deploy_path)

### Deployment Pipeline
1. `bash scripts/deploy.sh export` — copies policy.onnx + deploy.yaml from logs/ to deploy/
2. `bash scripts/deploy.sh push <ip>` — rsync deploy/ to robot
3. On robot: compile with cmake/make (needs unitree_sdk2, ONNX Runtime)
4. On robot: `./g1_ctrl --network eth0` — starts DDS, FSM Passive → FixStand → Velocity

### FSM States (joystick control)
- Passive (id=1): motors unpowered, robot is limp
- FixStand (id=2): L2+↑ — motors engaged, standing pose
- Velocity (id=3): R1+X — RL policy takes over velocity tracking via left stick
- L2+B anytime → Passive (emergency stop)

### C++ Build Dependencies
- ONNX Runtime 1.22.0 (downloaded by deploy/install_onnxruntime.sh)
- unitree_sdk2, ddsc/ddscxx, Boost (program_options), yaml-cpp, Eigen3, fmt
- Compiled with C++17, CMake ≥3.12
- **Ubuntu 26.04 > Isaac Sim official support (22.04/24.04)** → Docker is mandatory, never attempt native install
- **Host Python 3.14** → Isaac Sim needs 3.10, always use Conda
- **GPU driver 580.x required** for Isaac Sim 5.1.0 (595.x causes segfault in librtx.scenedb.plugin.so)
- **Docker `--user 0:0` mandatory** — shader/ogn caches fail without root
- **Docker group**: user must be in `docker` group, or use `sudo` for all Docker commands
