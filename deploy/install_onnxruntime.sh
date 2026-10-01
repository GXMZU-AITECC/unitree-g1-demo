#!/bin/bash
# =============================================================================
# ONNX Runtime 安装脚本
# =============================================================================
# 用于在 G1 机器人上（或本地开发机）下载 ONNX Runtime 1.22.0 预编译包。
#
# 使用方式：
#   bash deploy/install_onnxruntime.sh            # 自动下载
#   ONNXRUNTIME_ROOT=/path/to/existing bash ...   # 跳过下载，直接用你指定的路径
#
# 如果你的机器无法访问 GitHub，先在能上网的机器上下载 .tgz，
# 解压到 deploy/thirdparty/onnxruntime-linux-x64-1.22.0/，
# 然后设置 ONNXRUNTIME_ROOT 指向那个目录即可。
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
THIRDPARTY_DIR="${SCRIPT_DIR}/thirdparty"
ONNX_VER="1.22.0"
ONNX_DIR="onnxruntime-linux-x64-${ONNX_VER}"
ONNX_TGZ="onnxruntime-linux-x64-${ONNX_VER}.tgz"
ONNX_URL="https://github.com/microsoft/onnxruntime/releases/download/v${ONNX_VER}/${ONNX_TGZ}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# ── 如果用户已经指定了 ONNXRUNTIME_ROOT ──────────────────────────────────
if [[ -n "${ONNXRUNTIME_ROOT:-}" ]]; then
    if [[ -f "${ONNXRUNTIME_ROOT}/lib/libonnxruntime.so.${ONNX_VER}" ]]; then
        echo -e "${GREEN}✓ ONNX Runtime found at:${NC} ${ONNXRUNTIME_ROOT}"
        echo ""
        echo "  To build with this path after this shell session:"
        echo "  export ONNXRUNTIME_ROOT=${ONNXRUNTIME_ROOT}"
        exit 0
    else
        echo -e "${RED}✗ ONNXRUNTIME_ROOT 已设置但路径无效:${NC} ${ONNXRUNTIME_ROOT}"
        echo "  找不到: ${ONNXRUNTIME_ROOT}/lib/libonnxruntime.so.${ONNX_VER}"
        exit 1
    fi
fi

# ── 检查是否已经安装 ───────────────────────────────────────────────────────
TARGET_DIR="${THIRDPARTY_DIR}/${ONNX_DIR}"
if [[ -f "${TARGET_DIR}/lib/libonnxruntime.so.${ONNX_VER}" ]]; then
    echo -e "${GREEN}✓ ONNX Runtime 已安装在:${NC} ${TARGET_DIR}"
    echo ""
    echo "  编译前请设置环境变量："
    echo "  export ONNXRUNTIME_ROOT=${TARGET_DIR}"
    exit 0
fi

# ── 下载 ─────────────────────────────────────────────────────────────────────
echo -e "${YELLOW}=== 下载 ONNX Runtime ${ONNX_VER} ===${NC}"
echo "  URL: ${ONNX_URL}"
echo "  目标: ${THIRDPARTY_DIR}"
echo ""

cd "${THIRDPARTY_DIR}"

# 如果 .tgz 已经存在就跳过下载
if [[ ! -f "${ONNX_TGZ}" ]]; then
    if command -v wget &>/dev/null; then
        wget --show-progress "${ONNX_URL}" || {
            echo -e "${RED}✗ 下载失败。请检查网络连接。${NC}"
            echo "  如果机器人没有互联网，请在其他机器上下载 ${ONNX_URL}"
            echo "  解压到: ${TARGET_DIR}"
            exit 1
        }
    elif command -v curl &>/dev/null; then
        curl -L -O "${ONNX_URL}" || {
            echo -e "${RED}✗ 下载失败。请检查网络连接。${NC}"
            exit 1
        }
    else
        echo -e "${RED}✗ 本机没有 wget 或 curl，无法下载。${NC}"
        echo "  请在能上网的机器上下载：${ONNX_URL}"
        echo "  然后解压到: ${TARGET_DIR}"
        exit 1
    fi
else
    echo "  .tgz 已存在，跳过下载。"
fi

# ── 解压 ─────────────────────────────────────────────────────────────────────
echo ""
echo -e "${YELLOW}=== 解压 ONNX Runtime ===${NC}"
tar xzf "${ONNX_TGZ}"
# 清理 tgz（节省空间）
rm -f "${ONNX_TGZ}"

# ── 验证 ─────────────────────────────────────────────────────────────────────
if [[ -f "${TARGET_DIR}/lib/libonnxruntime.so.${ONNX_VER}" ]]; then
    echo ""
    echo -e "${GREEN}✓ ONNX Runtime ${ONNX_VER} 安装完成！${NC}"
    echo "  路径: ${TARGET_DIR}"
    echo ""
    echo "  ──────────────────────────────────────────"
    echo "  请设置以下环境变量（可写入 ~/.bashrc）："
    echo ""
    echo "  export ONNXRUNTIME_ROOT=${TARGET_DIR}"
    echo "  ──────────────────────────────────────────"
else
    echo -e "${RED}✗ 解压后找不到 libonnxruntime.so.${ONNX_VER}${NC}"
    echo "  请检查解压结果：${TARGET_DIR}"
    exit 1
fi
