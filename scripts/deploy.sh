#!/bin/bash
# =============================================================================
# G1 Deployment Helper — v1.0
# =============================================================================
# Architecture:
#   - 训练在 Docker 容器内完成，模型导出到 logs/
#   - 本脚本帮你把导出的 ONNX + deploy.yaml 复制到 deploy/g1_29dof/config/policy/
#   - 然后推送到 G1 机器人上编译运行
#
# Quick start:
#   bash scripts/deploy.sh export              # 交互式选择 run + checkpoint
#   bash scripts/deploy.sh export <run> <ckpt> # 指定参数导出
#   bash scripts/deploy.sh install             # 安装 ONNX Runtime
#   bash scripts/deploy.sh build               # 编译 C++ 控制器
#   bash scripts/deploy.sh push <robot_ip>     # 推送到机器人
# =============================================================================
set -euo pipefail

# 项目根目录 = 本脚本所在目录的上一级；克隆到哪里都行，可用 G1_RL_ROOT 覆盖。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="${G1_RL_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
LOG_DIR="${PROJ_DIR}/logs/rsl_rl/unitree_g1_29dof_velocity"
DEPLOY_DIR="${PROJ_DIR}/deploy"
POLICY_DIR="${DEPLOY_DIR}/g1_29dof/config/policy/velocity/v0"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

# ── 读取 configs/deploy_config.py 的默认值 ──────────────────────────────────
load_defaults() {
    if [[ -f "${PROJ_DIR}/configs/g1_config.py" ]]; then
        RUN_NAME=$(python3 -c "
import sys; sys.path.insert(0, '${PROJ_DIR}/configs')
from g1_config import G1_CONFIG
print(getattr(G1_CONFIG.deploy, 'run_name', ''))
" 2>/dev/null || echo "")
        CKPT=$(python3 -c "
import sys; sys.path.insert(0, '${PROJ_DIR}/configs')
from g1_config import G1_CONFIG
print(getattr(G1_CONFIG.deploy, 'checkpoint', ''))
" 2>/dev/null || echo "")
        ROBOT_IP=$(python3 -c "
import sys; sys.path.insert(0, '${PROJ_DIR}/configs')
from g1_config import G1_CONFIG
print(getattr(G1_CONFIG.deploy, 'robot_ip', ''))
" 2>/dev/null || echo "")
        ROBOT_PATH=$(python3 -c "
import sys; sys.path.insert(0, '${PROJ_DIR}/configs')
from g1_config import G1_CONFIG
print(getattr(G1_CONFIG.deploy, 'robot_deploy_path', '~/g1-rl-deploy'))
" 2>/dev/null || echo "~/g1-rl-deploy")
    else
        RUN_NAME=""
        CKPT=""
        ROBOT_IP=""
        ROBOT_PATH="~/g1-rl-deploy"
    fi
}

# ── list_runs: discover available training runs ───────────────────────────
list_runs() {
    if [[ ! -d "${LOG_DIR}" ]]; then
        echo -e "${RED}No training runs found in ${LOG_DIR}${NC}" >&2
        return 1
    fi
    local runs=()
    while IFS= read -r d; do
        runs+=("$(basename "$d")")
    done < <(ls -1dt "${LOG_DIR}"/*/ 2>/dev/null)
    echo "${runs[@]}"
}

# ── list_checkpoints: list model files in a run dir ───────────────────────
list_checkpoints() {
    local run_dir="${1}"
    local full_dir="${LOG_DIR}/${run_dir}"
    if [[ ! -d "${full_dir}" ]]; then
        echo -e "${RED}Run directory not found: ${full_dir}${NC}" >&2
        return 1
    fi
    ls -1t "${full_dir}"/model_*.pt 2>/dev/null | while read -r f; do
        basename "$f"
    done
}

# ── select_run: interactive run selection ─────────────────────────────────
select_run() {
    if [[ ! -d "${LOG_DIR}" ]]; then
        echo -e "${RED}No training runs found.${NC}" >&2
        return 1
    fi
    local runs=()
    while IFS= read -r d; do
        runs+=("$(basename "$d")")
    done < <(ls -1dt "${LOG_DIR}"/*/ 2>/dev/null)

    if [[ ${#runs[@]} -eq 0 ]]; then
        echo -e "${RED}No training runs found.${NC}" >&2
        return 1
    fi

    echo "" >&2
    echo -e "${BLUE}=== 可用的训练 Run ===${NC}" >&2
    local i=1
    for r in "${runs[@]}"; do
        local ckpt_count=$(ls -1 "${LOG_DIR}/${r}"/model_*.pt 2>/dev/null | wc -l)
        local has_exported=""
        if [[ -f "${LOG_DIR}/${r}/exported/policy.onnx" ]]; then
            has_exported=" [已导出ONNX]"
        fi
        echo -e "  ${GREEN}${i}${NC} -> ${CYAN}${r}${NC}  (${ckpt_count} checkpoints)${YELLOW}${has_exported}${NC}" >&2
        ((i++))
    done
    echo "" >&2

    local choice
    while true; do
        echo -n "  选择 (1-${#runs[@]}): " >&2
        read -r choice
        if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#runs[@]} )); then
            echo "${runs[$((choice - 1))]}"
            return 0
        fi
        echo -e "  ${RED}无效选择，重试。${NC}" >&2
    done
}

# ── select_checkpoint: interactive checkpoint selection ───────────────────
select_checkpoint() {
    local run_name="${1}"
    local full_dir="${LOG_DIR}/${run_name}"
    local ckpts=()
    while IFS= read -r f; do
        ckpts+=("$(basename "$f" .pt)")
    done < <(ls -1t "${full_dir}"/model_*.pt 2>/dev/null)

    if [[ ${#ckpts[@]} -eq 0 ]]; then
        echo -e "${RED}No checkpoints found.${NC}" >&2
        return 1
    fi

    local show_n=20
    if (( ${#ckpts[@]} < show_n )); then show_n=${#ckpts[@]}; fi

    echo "" >&2
    echo -e "${BLUE}=== ${CYAN}${run_name}${BLUE} 的 Checkpoints ===${NC}" >&2
    echo -e "  (显示最近 ${show_n} 个，共 ${#ckpts[@]} 个)" >&2
    local i=1
    while (( i <= show_n )); do
        echo -e "  ${GREEN}${i}${NC} -> ${ckpts[$((i - 1))]}" >&2
        ((i++))
    done
    echo "" >&2

    local choice
    while true; do
        echo -n "  选择 (1-${show_n}): " >&2
        read -r choice
        if [[ "${choice}" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= show_n )); then
            echo "${ckpts[$((choice - 1))]}"
            return 0
        fi
        echo -e "  ${RED}无效选择，重试。${NC}" >&2
    done
}

# =============================================================================
# Commands
# =============================================================================

export_cmd() {
    load_defaults
    local run_name="${1:-${RUN_NAME:-}}"
    local checkpoint="${2:-${CKPT:-}}"

    # Interactive selection if not provided
    if [[ -z "${run_name}" ]]; then
        run_name=$(select_run) || return 1
    fi
    if [[ -z "${checkpoint}" ]]; then
        checkpoint=$(select_checkpoint "${run_name}") || return 1
    fi

    local run_dir="${LOG_DIR}/${run_name}"
    local exported_dir="${run_dir}/exported"

    echo ""
    echo -e "${GREEN}=== 导出模型 ===${NC}"
    echo "Run:        ${run_name}"
    echo "Checkpoint: ${checkpoint}"

    # If exported/ doesn't exist yet, try to export from checkpoint
    if [[ ! -f "${exported_dir}/policy.onnx" ]]; then
        echo -e "${YELLOW}尚未导出 ONNX，正在从 checkpoint 导出...${NC}"
        echo ""
        echo "  需要在 Docker 容器内运行 export。请使用："
        echo ""
        echo -e "  ${CYAN}bash scripts/start.sh play ${run_name} ${checkpoint}.pt${NC}"
        echo ""
        echo "  play 命令会自动导出 ONNX 模型到 exported/ 目录。"
        echo "  运行完成后，再次执行 deploy.sh export。"
        return 1
    fi

    # Copy ONNX model
    mkdir -p "${POLICY_DIR}/exported"
    cp -v "${exported_dir}/policy.onnx" "${POLICY_DIR}/exported/policy.onnx"

    # Copy deploy.yaml
    local params_dir="${run_dir}/params"
    if [[ -f "${params_dir}/deploy.yaml" ]]; then
        mkdir -p "${POLICY_DIR}/params"
        cp -v "${params_dir}/deploy.yaml" "${POLICY_DIR}/params/deploy.yaml"
    else
        echo -e "${YELLOW}⚠ deploy.yaml 不在 params/，尝试从 config/policy/ 复制...${NC}"
    fi

    echo ""
    echo -e "${GREEN}✓ 导出完成！${NC}"
    echo "  ONNX 模型: ${POLICY_DIR}/exported/policy.onnx"
    echo "  部署配置:  ${POLICY_DIR}/params/deploy.yaml"
    echo ""
    echo "  下一步："
    echo "    1. 推送到机器人: bash scripts/deploy.sh push <robot_ip>"
    echo "    2. 或直接编译:    bash scripts/deploy.sh build"
}

install_cmd() {
    echo -e "${GREEN}=== 安装 ONNX Runtime ===${NC}"
    echo ""
    bash "${DEPLOY_DIR}/install_onnxruntime.sh"
    echo ""
    echo -e "${GREEN}✓ ONNX Runtime 安装完成。${NC}"
    echo ""
    echo "检查编译依赖项…"

    local missing=()
    for dep in cmake make g++; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "${YELLOW}缺少以下编译工具: ${missing[*]}${NC}"
        echo "  安装命令: sudo apt install ${missing[*]}"
    else
        echo -e "${GREEN}✓ 编译工具 (cmake, make, g++) 已安装${NC}"
    fi

    # Check ONNX Runtime
    local onnx_root="${ONNXRUNTIME_ROOT:-${DEPLOY_DIR}/thirdparty/onnxruntime-linux-x64-1.22.0}"
    if [[ -f "${onnx_root}/lib/libonnxruntime.so.1.22.0" ]]; then
        echo -e "${GREEN}✓ ONNX Runtime 已就绪: ${onnx_root}${NC}"
    else
        echo -e "${YELLOW}⚠ ONNX Runtime not found, run: bash deploy/install_onnxruntime.sh${NC}"
    fi
}

build_cmd() {
    echo -e "${GREEN}=== 编译 G1 控制器 ===${NC}"
    local build_dir="${DEPLOY_DIR}/g1_29dof/build"

    # Set ONNXRUNTIME_ROOT if not set
    if [[ -z "${ONNXRUNTIME_ROOT:-}" ]]; then
        local default_onnx="${DEPLOY_DIR}/thirdparty/onnxruntime-linux-x64-1.22.0"
        if [[ -f "${default_onnx}/lib/libonnxruntime.so.1.22.0" ]]; then
            export ONNXRUNTIME_ROOT="${default_onnx}"
        else
            echo -e "${RED}ONNX Runtime 未安装。请先运行: bash deploy/install_onnxruntime.sh${NC}"
            return 1
        fi
    fi
    echo "ONNX Runtime: ${ONNXRUNTIME_ROOT}"

    mkdir -p "${build_dir}"
    cd "${build_dir}"

    echo ""
    echo "Running cmake..."
    cmake .. -DCMAKE_BUILD_TYPE=Release

    echo ""
    echo "Running make..."
    make -j$(nproc 2>/dev/null || echo 4)

    if [[ -f "${build_dir}/g1_ctrl" ]]; then
        echo ""
        echo -e "${GREEN}✓ 编译成功！${NC}"
        echo "  二进制文件: ${build_dir}/g1_ctrl"
        echo ""
        echo "  运行方式（在机器人上）："
        echo "  cd $(dirname "${build_dir}")"
        echo "  ./build/g1_ctrl --network eth0"
    else
        echo -e "${RED}✗ 编译失败，请检查错误信息。${NC}"
        return 1
    fi
}

push_cmd() {
    local robot_ip="${1:-}"
    load_defaults
    if [[ -z "${robot_ip}" ]]; then
        robot_ip="${ROBOT_IP:-}"
    fi
    if [[ -z "${robot_ip}" ]]; then
        echo -e "${RED}请指定机器人 IP: bash scripts/deploy.sh push 192.168.123.161${NC}"
        return 1
    fi
    local robot_path="${ROBOT_PATH:-~/g1-rl-deploy}"

    echo -e "${GREEN}=== 推送到机器人 ===${NC}"
    echo "  机器人 IP: ${robot_ip}"
    echo "  目标路径:  ${robot_path}"
    echo ""

    # Check policy exists
    if [[ ! -f "${POLICY_DIR}/exported/policy.onnx" ]]; then
        echo -e "${YELLOW}⚠ 尚未导出模型。请先运行: bash scripts/deploy.sh export${NC}"
        read -rp "  是否继续只推送代码？ [y/N] " yn
        if [[ ! "${yn}" =~ ^[Yy]$ ]]; then
            return 0
        fi
    fi

    # rsync the full deploy directory (excluding thirdparty binaries, build artifacts)
    echo "正在 rsync deploy/ 到机器人…"
    rsync -avz --progress \
        --exclude 'thirdparty/onnxruntime-linux-x64-*' \
        --exclude 'g1_29dof/build/' \
        --exclude '__pycache__/' \
        "${DEPLOY_DIR}/" "${robot_ip}:${robot_path}/"

    echo ""
    echo -e "${GREEN}✓ 推送完成！${NC}"
    echo ""
    echo "  在机器人上执行："
    echo "  ssh ${robot_ip}"
    echo "  cd ${robot_path}"
    echo "  bash install_onnxruntime.sh"
    echo "  cd g1_29dof && mkdir -p build && cd build"
    echo "  cmake .. && make -j"
    echo "  ./g1_ctrl --network eth0"
}

# =============================================================================
# Main
# =============================================================================
case "${1:-help}" in
    export|e)
        export_cmd "${2:-}" "${3:-}"
        ;;
    install|i)
        install_cmd
        ;;
    build|b)
        build_cmd
        ;;
    push|p)
        push_cmd "${2:-}"
        ;;
    help|h|-h|--help|*)
        echo ""
        echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
        echo -e "${BLUE}║     G1 Deployment Helper v1.0           ║${NC}"
        echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "  ${GREEN}export${NC}    从训练日志导出 ONNX 模型到 deploy/"
        echo -e "  ${GREEN}install${NC}   安装 ONNX Runtime + 检查编译依赖"
        echo -e "  ${GREEN}build${NC}     编译 C++ 控制器 (在机器人上执行)"
        echo -e "  ${GREEN}push${NC}      推送 deploy/ 到机器人"
        echo ""
        echo -e "  ${CYAN}Config:${NC} ${YELLOW}configs/g1_config.py${NC} (DeployConfig)"
        echo ""
        echo -e "  ${YELLOW}Usage examples:${NC}"
        echo "    bash scripts/deploy.sh export                          # 交互式导出"
        echo "    bash scripts/deploy.sh export 2026-06-24_09-29-56 model_18100  # 指定参数"
        echo "    bash scripts/deploy.sh push 192.168.123.161             # 推送到机器人"
        echo "    bash scripts/deploy.sh install                          # 安装依赖"
        echo "    bash scripts/deploy.sh build                            # 编译"
        echo ""
        ;;
esac
