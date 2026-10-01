#!/bin/bash
# =============================================================================
# G1 RL Training Launcher — v3.0
# =============================================================================
# Architecture:
#   - Config file (configs/g1_config.py) is the SOURCE OF TRUTH
#   - ALL user-adjustable parameters live in that config file
#   - CLI arguments are no longer used for num_envs/max_iterations/seed
#   - Interactive menus auto-discover available models
#
# Quick start:
#   bash scripts/start.sh train              # training from config defaults
#   bash scripts/start.sh train-gui          # training + live 3D view
#   bash scripts/start.sh play               # auto-lists checkpoints
#   bash scripts/start.sh resume             # resume interrupted training
#
# To change parameters:
#   编辑 configs/g1_config.py，修改后直接生效
#   不需要设环境变量，不需要 CLI 传参
# =============================================================================
set -euo pipefail

# ── User-overridable defaults ─────────────────────────────────────────────
# All training/play parameters are in configs/g1_config.py
# TRAIN_TASK — only used to pass a different task to the Python scripts
#              (default is read from config file)
TRAIN_TASK="${TRAIN_TASK:-}"

# ── Docker / paths ────────────────────────────────────────────────────────
# 项目根目录 = 本脚本所在目录的上一级。仓库克隆到哪里都行，
# 不再要求固定放在 ~/projects/g1-rl。想放到别处可以设 G1_RL_ROOT。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="${G1_RL_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
IMAGE="nvcr.io/nvidia/isaac-sim:5.1.0"
SIM_DIR="${PROJ_DIR}/sim"
CACHE_DIR="${HOME}/.cache/isaac-sim"
LOG_DIR="${PROJ_DIR}/logs"
PIP_PKGS_DIR="${CACHE_DIR}/pip_pkgs"
CONFIGS_DIR="${PROJ_DIR}/configs"
PIP_MIRROR="https://pypi.tuna.tsinghua.edu.cn/simple"

EXTRA_PYTHONPATH="/sim/IsaacLab/source/isaaclab:/sim/IsaacLab/source/isaaclab_rl:/sim/IsaacLab/source/isaaclab_tasks:/isaac-sim/pip_pkgs:/sim/unitree_rl_lab/source/unitree_rl_lab:/configs"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# ── One-time setup ────────────────────────────────────────────────────────
mkdir -p "${CACHE_DIR}"/{kit,ov,pip,glcache,computecache,logs,data,documents}
mkdir -p "${PIP_PKGS_DIR}"
mkdir -p "${LOG_DIR}"

# ── Preflight：依赖仓库与配置文件先到位 ──────────────────────────────────
# 以前这些路径写死在 ~/projects/g1-rl，克隆到别处时 Docker 会静默挂载一个
# 空目录，最后报的是容器里 ModuleNotFoundError: g1_config —— 新手无从下手。
# 现在直接把缺什么、去哪儿补，说清楚。
MODE="${1:-menu}"
require_sim() {
    local missing=() soft=0
    [[ "${MODE}" == "menu" ]] && soft=1
    [[ -d "${SIM_DIR}/unitree_rl_lab" ]] || missing+=("unitree_rl_lab")
    [[ -d "${SIM_DIR}/IsaacLab" ]]       || missing+=("IsaacLab")
    [[ -f "${CONFIGS_DIR}/g1_config.py" ]] || missing+=("configs/g1_config.py(不在仓库里？确认你在仓库目录内执行)")
    (( ${#missing[@]} )) || return 0
    echo -e "${RED}缺少：${missing[*]}${NC}"
    echo "项目目录：${PROJ_DIR}（可用 G1_RL_ROOT 覆盖）"
    echo "补齐办法（教程 1.5）："
    echo "  mkdir -p ${SIM_DIR} && cd ${SIM_DIR}"
    echo "  git clone https://github.com/unitreerobotics/unitree_rl_lab.git"
    echo "  git clone https://github.com/isaac-sim/IsaacLab.git"
    if (( soft )); then
        echo -e "${YELLOW}（只是看菜单，不拦你；真要跑训练前必须先补齐）${NC}"
        return 0
    fi
    return 1
}
require_sim

# ── 上游兼容补丁（rsl-rl-lib 5.0.1）──────────────────────────────────────
# sim/ 里那几个上游脚本必须改 4 处才能在 rsl-rl 5.0.1 上跑起来，逐条取证见
# docs/upstream-patches.md。以前只写在文档里让人手工改，重克隆一次就全丢。
SIM_FIXER="${SCRIPT_DIR}/apply_sim_fixes.py"
host_python() { command -v python3 >/dev/null 2>&1 && echo python3 || echo python; }

apply_sim_fixes() {
    local py; py="$(host_python)"
    if [[ ! -f "${SIM_FIXER}" ]]; then
        echo -e "${YELLOW}找不到 ${SIM_FIXER}，跳过上游补丁。${NC}"; return 0
    fi
    echo "Step 3: 上游兼容补丁（rsl-rl-lib 5.0.1）..."
    "${py}" "${SIM_FIXER}" --sim-root "${SIM_DIR}" \
        || { echo -e "${RED}补丁没打全，按上面每条的提示人工核对后重试。${NC}"; return 1; }
    "${py}" "${SIM_FIXER}" --sim-root "${SIM_DIR}" --check \
        || { echo -e "${RED}补丁复验未通过（--check 仍报未通过项）。${NC}"; return 1; }
}

warn_sim_fixes() {
    local py; py="$(host_python)"
    [[ -f "${SIM_FIXER}" ]] || return 0
    if ! "${py}" "${SIM_FIXER}" --sim-root "${SIM_DIR}" --check >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠ sim/ 的上游补丁不完整，这一跑大概率会崩（'PPO' object has no attribute 'policy'"
        echo -e "   或 TypeError: unexpected keyword argument 'stochastic'）。一行修好：${NC}"
        echo -e "   ${CYAN}python3 scripts/apply_sim_fixes.py --sim-root ${SIM_DIR}${NC}"
    fi
}

DOCKER_BASE="docker run --rm --gpus all --user 0:0 \
  -e ACCEPT_EULA=Y -e OMNI_KIT_ACCEPT_EULA=YES -e OMNI_KIT_ALLOW_ROOT=1 \
  -e PRIVACY_CONSENT=Y \
  -e GIT_PYTHON_REFRESH=quiet \
  --shm-size=8g --network=host \
  -v /usr/bin/git:/usr/bin/git:ro \
  -v ${CACHE_DIR}/kit:/isaac-sim/kit/cache:rw \
  -v ${CACHE_DIR}/ov:/root/.cache/ov:rw \
  -v ${CACHE_DIR}/pip:/root/.cache/pip:rw \
  -v ${CACHE_DIR}/glcache:/root/.cache/nvidia/GLCache:rw \
  -v ${CACHE_DIR}/computecache:/root/.nv/ComputeCache:rw \
  -v ${CACHE_DIR}/logs:/root/.nvidia-omniverse/logs:rw \
  -v ${CACHE_DIR}/data:/root/.local/share/ov/data:rw \
  -v ${PIP_PKGS_DIR}:/isaac-sim/pip_pkgs:rw \
  -v ${CONFIGS_DIR}:/configs:ro \
  -v ${SIM_DIR}:/sim:rw \
  -v ${LOG_DIR}:/isaac-sim/logs:rw"

ENV_WRAPPER="export GIT_PYTHON_REFRESH=quiet \
  && source /isaac-sim/setup_python_env.sh \
  && export CARB_APP_PATH=/isaac-sim/kit \
  && export ISAAC_PATH=/isaac-sim \
  && export EXP_PATH=/isaac-sim/apps \
  && export LD_PRELOAD=/isaac-sim/kit/libcarb.so \
  && export RESOURCE_NAME=IsaacSim \
  && export PYTHONPATH=\${PYTHONPATH}:${EXTRA_PYTHONPATH}"

# ── Helpers: run Python inside Docker ─────────────────────────────────────
run_python() {
    ${DOCKER_BASE} \
        --entrypoint bash "${IMAGE}" \
        -c "${ENV_WRAPPER} && /isaac-sim/kit/python/bin/python3 $@" 2>&1
}

run_python_gui() {
    xhost +local: 2>/dev/null
    ${DOCKER_BASE} \
        -e "DISPLAY=${DISPLAY}" \
        -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
        -v "${HOME}/.Xauthority:/root/.Xauthority:ro" \
        --entrypoint bash "${IMAGE}" \
        -c "${ENV_WRAPPER} && /isaac-sim/kit/python/bin/python3 $@" 2>&1
}

launch_tensorboard() {
    local port=6006
    local logdir="${LOG_DIR}/rsl_rl/unitree_g1_29dof_velocity"
    while true; do
        if ss -tlnp "sport = :${port}" 2>/dev/null | grep -q ":${port}"; then
            echo -e "${YELLOW}Port ${port} in use.${NC}"
            if (( port == 6006 )); then
                echo -n "  Kill old TensorBoard and retry? [Y/n] "
                read -r yn
                if [[ "${yn:-y}" =~ ^[Yy]$ ]]; then
                    fuser -k "${port}/tcp" 2>/dev/null || true
                    sleep 1
                    continue
                fi
            fi
            ((port++))
            echo "  Trying port ${port}..."
        else
            echo "http://localhost:${port}"
            tensorboard --logdir "${logdir}" --bind_all --port "${port}" 2>&1 | grep -v "^NOTE:" | grep -v "^TensorFlow" || true
            break
        fi
    done
}
# ── list_runs: discover available training runs ───────────────────────────
list_runs() {
    local log_root="${LOG_DIR}/rsl_rl/unitree_g1_29dof_velocity"
    if [[ ! -d "${log_root}" ]]; then
        echo -e "${RED}No training runs found in ${log_root}${NC}" >&2
        return 1
    fi
    local runs=()
    while IFS= read -r d; do
        runs+=("$(basename "$d")")
    done < <(ls -1dt "${log_root}"/*/ 2>/dev/null)
    echo "${runs[@]}"
}

# ── list_checkpoints: list model files in a run dir ───────────────────────
list_checkpoints() {
    local run_dir="${1}"
    local log_root="${LOG_DIR}/rsl_rl/unitree_g1_29dof_velocity/${run_dir}"
    if [[ ! -d "${log_root}" ]]; then
        echo -e "${RED}Run directory not found: ${log_root}${NC}"
        return 1
    fi
    ls -1t "${log_root}"/model_*.pt 2>/dev/null | while read -r f; do
        basename "$f"
    done
}

# ── select_run: interactive run selection ─────────────────────────────────
select_run() {
    local log_root="${LOG_DIR}/rsl_rl/unitree_g1_29dof_velocity"
    if [[ ! -d "${log_root}" ]]; then
        echo -e "${RED}No training runs found.${NC}" >&2
        return 1
    fi
    local runs=()
    while IFS= read -r d; do
        runs+=("$(basename "$d")")
    done < <(ls -1dt "${log_root}"/*/ 2>/dev/null)

    if [[ ${#runs[@]} -eq 0 ]]; then
        echo -e "${RED}No training runs found.${NC}" >&2
        return 1
    fi

    echo "" >&2
    echo -e "${BLUE}=== Available Training Runs ===${NC}" >&2
    local i=1
    for r in "${runs[@]}"; do
        local ckpt_count=$(ls -1 "${log_root}/${r}"/model_*.pt 2>/dev/null | wc -l)
        echo -e "  ${GREEN}${i}${NC} -> ${CYAN}${r}${NC}  (${ckpt_count} checkpoints)" >&2
        ((i++))
    done
    echo "" >&2

    local choice
    while true; do
        echo -n "  Select run (1-${#runs[@]}): " >&2
        read -r choice
        if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#runs[@]} )); then
            echo "${runs[$((choice - 1))]}"
            return 0
        fi
        echo -e "  ${RED}Invalid choice, try again.${NC}" >&2
    done
}

# ── select_checkpoint: interactive checkpoint selection ───────────────────
select_checkpoint() {
    local run_name="${1}"
    local log_root="${LOG_DIR}/rsl_rl/unitree_g1_29dof_velocity/${run_name}"
    local ckpts=()
    while IFS= read -r f; do
        ckpts+=("$(basename "$f")")
    done < <(ls -1t "${log_root}"/model_*.pt 2>/dev/null)

    if [[ ${#ckpts[@]} -eq 0 ]]; then
        echo -e "${RED}No checkpoints found in ${run_name}${NC}" >&2
        return 1
    fi

    local show_n=20
    if (( ${#ckpts[@]} < show_n )); then show_n=${#ckpts[@]}; fi

    echo "" >&2
    echo -e "${BLUE}=== Checkpoints in ${CYAN}${run_name}${BLUE} ===${NC}" >&2
    echo -e "  (showing most recent ${show_n} of ${#ckpts[@]} total)" >&2
    local i=1
    while (( i <= show_n )); do
        echo -e "  ${GREEN}${i}${NC} -> ${ckpts[$((i - 1))]}" >&2
        ((i++))
    done
    echo "" >&2

    local choice
    while true; do
        echo -n "  Select checkpoint (1-${show_n}): " >&2
        read -r choice
        if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= show_n )); then
            echo "${ckpts[$((choice - 1))]}"
            return 0
        fi
        echo -e "  ${RED}Invalid choice, try again.${NC}" >&2
    done
}

# =============================================================================
# Commands
# =============================================================================

install() {
    echo -e "${GREEN}=== Installing training dependencies (persistent) ===${NC}"
    echo "Packages go to: ${PIP_PKGS_DIR}"
    echo ""

    ${DOCKER_BASE} --entrypoint bash "${IMAGE}" -c "
set -e
source /isaac-sim/setup_python_env.sh
export CARB_APP_PATH=/isaac-sim/kit
export ISAAC_PATH=/isaac-sim
export EXP_PATH=/isaac-sim/apps
export LD_PRELOAD=/isaac-sim/kit/libcarb.so
export PYTHONPATH=\${PYTHONPATH}:${EXTRA_PYTHONPATH}
export PATH=/isaac-sim/kit/python/bin:\$PATH

echo 'Step 0: Cleaning any conflicting pip isaaclab...'
rm -rf /isaac-sim/pip_pkgs/isaaclab /isaac-sim/pip_pkgs/isaaclab*.dist-info 2>/dev/null || true

echo 'Step 1: Installing gymnasium + rsl-rl-lib==5.0.1 + argcomplete...'
python3 -m pip install --target /isaac-sim/pip_pkgs -i ${PIP_MIRROR} gymnasium rsl-rl-lib==5.0.1 argcomplete 2>&1 | tail -3

echo 'Step 2: Linking unitree_rl_lab...'
echo '/sim/unitree_rl_lab/source/unitree_rl_lab' > /isaac-sim/pip_pkgs/unitree_rl_lab.pth

echo ''
echo 'Packages on disk:'
ls /isaac-sim/pip_pkgs/ | head -20
echo ''
echo 'All dependencies installed.'
" 2>&1

    echo ""
    apply_sim_fixes || return 1
    echo -e "${GREEN}Install complete.${NC}"
}

train() {
    echo -e "${GREEN}=== G1 RL Training (headless) ===${NC}"
    echo -e "Params from: ${CYAN}configs/g1_config.py${NC} (TrainConfig)"
    echo ""
    warn_sim_fixes
    local task_arg=""
    [[ -n "${TRAIN_TASK:-}" ]] && task_arg="--task ${TRAIN_TASK}"
    run_python "/sim/unitree_rl_lab/scripts/rsl_rl/train.py ${task_arg} --headless"
    echo -e "${GREEN}Done. Models: ${LOG_DIR}/rsl_rl/unitree_g1_29dof_velocity/${NC}"
}

train_gui() {
    echo -e "${GREEN}=== G1 RL Training (GUI) ===${NC}"
    echo -e "Params from: ${CYAN}configs/g1_config.py${NC} (TrainConfig)"
    echo -e "${YELLOW}Opening Isaac Sim 3D — close window or Ctrl+C to stop.${NC}"
    local task_arg=""
    [[ -n "${TRAIN_TASK:-}" ]] && task_arg="--task ${TRAIN_TASK}"
    run_python_gui "/sim/unitree_rl_lab/scripts/rsl_rl/train.py ${task_arg}"
    echo -e "${GREEN}Done. Models: ${LOG_DIR}/rsl_rl/unitree_g1_29dof_velocity/${NC}"
}

resume() {
    # Pick run and checkpoint interactively
    local run_name=$(select_run) || return 1
    local checkpoint=$(select_checkpoint "${run_name}") || return 1

    echo ""
    echo -e "${GREEN}=== Resuming Training ===${NC}"
    echo "Run:        ${run_name}"
    echo "Checkpoint: ${checkpoint}"
    echo -e "Params from: ${CYAN}configs/g1_config.py${NC} (TrainConfig)"
    echo ""
    local task_arg=""
    [[ -n "${TRAIN_TASK:-}" ]] && task_arg="--task ${TRAIN_TASK}"
    run_python "/sim/unitree_rl_lab/scripts/rsl_rl/train.py \
        ${task_arg} --headless \
        --resume \
        --load_run ${run_name} \
        --checkpoint ${checkpoint}"
    echo -e "${GREEN}Done.${NC}"
}

play() {
    local run_name="${1:-}"
    local checkpoint="${2:-}"

    # If no args, interactive selection
    if [[ -z "${run_name}" ]] || [[ "${run_name}" == "none" ]]; then
        run_name=$(select_run) || return 1
    fi
    if [[ -z "${checkpoint}" ]] || [[ "${checkpoint}" == "none" ]]; then
        checkpoint=$(select_checkpoint "${run_name}") || return 1
    fi

    echo ""
    echo -e "${GREEN}=== Playback ===${NC}"
    echo "Run:        ${run_name}"
    echo "Checkpoint: ${checkpoint}"
    echo -e "Params from: ${CYAN}configs/g1_config.py${NC} (PlayConfig)"
    echo -e "${YELLOW}Opening Isaac Sim 3D — close window or Ctrl+C to stop.${NC}"
    echo ""
    # play.py uses retrieve_file_path(checkpoint) which needs an absolute path
    local ckpt_path="/isaac-sim/logs/rsl_rl/unitree_g1_29dof_velocity/${run_name}/${checkpoint}"
    local task_arg=""
    [[ -n "${TRAIN_TASK:-}" ]] && task_arg="--task ${TRAIN_TASK}"
    run_python_gui "/sim/unitree_rl_lab/scripts/rsl_rl/play.py \
        ${task_arg} \
        --checkpoint ${ckpt_path}"
    echo -e "${GREEN}Done.${NC}"
}

visualize() {
    echo -e "${GREEN}=== G1 Visualization ===${NC}"
    echo "Opening Isaac Sim 3D editor..."
    xhost +local: 2>/dev/null
    ${DOCKER_BASE} \
        -e "DISPLAY=${DISPLAY}" \
        -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
        -v "${HOME}/.Xauthority:/root/.Xauthority:ro" \
        --entrypoint /isaac-sim/runapp.sh "${IMAGE}"
    echo -e "${GREEN}GUI closed.${NC}"
}

shell() {
    echo -e "${GREEN}=== Interactive Shell ===${NC}"
    echo "python3 ready after: source /isaac-sim/setup_python_env.sh"
    ${DOCKER_BASE} -it \
        -e "PYTHONPATH=\${PYTHONPATH}:${EXTRA_PYTHONPATH}" \
        -e "EXP_PATH=/sim/IsaacLab/apps" \
        --entrypoint bash "${IMAGE}"
}

# =============================================================================
# Main
# =============================================================================
case "${1:-menu}" in
    install|i)             install ;;
    visualize|gui|vis|v)   visualize ;;
    train|t)               train ;;
    train-gui|tg)          train_gui ;;
    resume|r)              resume ;;
    play|p)                play "${2:-}" "${3:-}" ;;
    shell|s|bash|sh)       shell ;;
    tensorboard|tb)
        echo -e "${GREEN}=== TensorBoard ===${NC}"
        launch_tensorboard
        ;;
    menu|m|"")
        echo ""
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║     G1 RL Training Launcher v3.0        ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${GREEN}1${NC}  train          RL training (headless)"
        echo -e "  ${GREEN}2${NC}  train-gui      RL training + live 3D view"
        echo -e "  ${GREEN}3${NC}  resume         Resume interrupted training"
        echo -e "  ${GREEN}4${NC}  play           Playback trained model"
        echo -e "  ${GREEN}5${NC}  visualize      3D GUI - explore the scene"
        echo -e "  ${GREEN}6${NC}  shell          Interactive container shell"
        echo -e "  ${GREEN}7${NC}  install        Install dependencies (run once first!)"
        echo -e "  ${GREEN}8${NC}  tensorboard    Monitor training curves"
        echo ""
        echo -e "  ${CYAN}Config:${NC} ${YELLOW}configs/g1_config.py${NC}"
        echo -e "  ${CYAN}Edit:${NC}  修改上面的文件来调整参数 (num_envs, max_iter, seed…)"
        echo ""
        echo -e "  ${YELLOW}Usage:${NC} bash scripts/start.sh train"
        echo -e "  ${YELLOW}Play:${NC}  bash scripts/start.sh play"
        echo ""
        echo -n "  Choice (1-8): "
        read -r choice
        case "${choice}" in
            1|train|t)               train ;;
            2|train-gui|tg)          train_gui ;;
            3|resume|r)              resume ;;
            4|play|p)                play "" ""  ;;
            5|visualize|gui|vis|v)  visualize ;;
            6|shell|s|bash|sh)       shell ;;
            7|install|i)             install ;;
            8|tensorboard|tb)       launch_tensorboard ;;
            *) echo -e "${RED}Unknown: ${choice}${NC}" ;;
        esac
        ;;
    *)
        echo "Usage: bash scripts/start.sh [train|train-gui|resume|play|visualize|shell|install|tensorboard]"
        echo ""
        echo "所有训练/回放参数在 configs/g1_config.py 中配置，按功能分为："
        echo "  TrainConfig  — train / train-gui / resume 共用"
        echo "  PlayConfig   — play 专用"
        echo ""
        echo "环境变量（可选）："
        echo "  TRAIN_TASK=Unitree-G1-29dof-Velocity  # 覆盖默认任务名"
        echo ""
        echo "Examples:"
        echo "  bash scripts/start.sh train              # 用 configs/g1_config.py 中的参数训练"
        echo "  bash scripts/start.sh play               # 交互式选择模型回放"
        echo "  bash scripts/start.sh resume             # 从 checkpoint 继续训练"
        exit 1 ;;
esac
