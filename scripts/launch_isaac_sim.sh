#!/bin/bash
# =============================================================================
# G1 RL Training — Isaac Sim 5.1.0 Launcher
# Usage:
#   bash scripts/launch_isaac_sim.sh          — Interactive shell
#   bash scripts/launch_isaac_sim.sh verify   — Auto G1 29-DOF verification
#   bash scripts/launch_isaac_sim.sh gui      — GUI mode (3D viewer on your display!)
# =============================================================================
set -euo pipefail

IMAGE="nvcr.io/nvidia/isaac-sim:5.1.0"
CONTAINER_NAME="isaac-sim-g1"
CACHE_DIR="$HOME/.cache/isaac-sim"
# 项目根目录 = 本脚本所在目录的上一级；克隆到哪里都行，可用 G1_RL_ROOT 覆盖。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="${G1_RL_ROOT:-$(cd "${SCRIPT_DIR}/.." && pwd)}"
WORKSPACE_DIR="${PROJ_DIR}/workspace"
SIM_REPO_DIR="${PROJ_DIR}/sim"
MODE="${1:-shell}"

mkdir -p "$CACHE_DIR"/{kit,ov,pip,glcache,computecache,logs,data,documents}

# ---- GUI mode — 3D viewer directly on your Linux desktop ----
if [ "$MODE" = "gui" ]; then
    echo "=== Isaac Sim GUI Mode ==="
    echo "Opening 3D viewer on your display..."
    xhost +local: 2>/dev/null

    docker run --name "$CONTAINER_NAME" \
      --rm --gpus all \
      -e "ACCEPT_EULA=Y" \
      -e "PRIVACY_CONSENT=Y" \
      -e "OMNI_KIT_ACCEPT_EULA=YES" \
      -e "OMNI_KIT_ALLOW_ROOT=1" \
      -e "DISPLAY=$DISPLAY" \
      -v /tmp/.X11-unix:/tmp/.X11-unix:rw \
      -v "$HOME/.Xauthority:/root/.Xauthority:ro" \
      --shm-size=8g --network=host \
      -v "$CACHE_DIR"/kit:/isaac-sim/kit/cache:rw \
      -v "$CACHE_DIR"/ov:/root/.cache/ov:rw \
      -v "$CACHE_DIR"/pip:/root/.cache/pip:rw \
      -v "$CACHE_DIR"/glcache:/root/.cache/nvidia/GLCache:rw \
      -v "$CACHE_DIR"/computecache:/root/.nv/ComputeCache:rw \
      -v "$CACHE_DIR"/logs:/root/.nvidia-omniverse/logs:rw \
      -v "$CACHE_DIR"/data:/root/.local/share/ov/data:rw \
      -v "$CACHE_DIR"/documents:/root/Documents:rw \
      -v "$WORKSPACE_DIR:/workspace:rw" \
      -v "$SIM_REPO_DIR:/sim:rw" \
      --entrypoint /isaac-sim/runapp.sh \
      "$IMAGE"

# ---- Auto verification mode — headless G1 physics sim ----
elif [ "$MODE" = "verify" ]; then
    echo "=== G1 29-DOF Verification ==="
    docker run --rm --gpus all \
      -e "ACCEPT_EULA=Y" \
      -e "OMNI_KIT_ACCEPT_EULA=YES" \
      -e "OMNI_KIT_ALLOW_ROOT=1" \
      --shm-size=8g --network=host \
      -v "$SIM_REPO_DIR:/sim:ro" \
      --entrypoint /isaac-sim/python.sh \
      "$IMAGE" -c '
import sys,os
os.environ["OMNI_KIT_ACCEPT_EULA"]="YES";os.environ["OMNI_KIT_ALLOW_ROOT"]="1"
from isaacsim import SimulationApp
app=SimulationApp({"renderer":"RaytracedLighting","headless":True})
import omni.usd,omni.kit.commands
from omni.isaac.core import World
from pxr import Gf,Sdf,UsdPhysics,PhysicsSchemaTools,PhysxSchema

w=World(stage_units_in_meters=1.0)
u="/sim/unitree_ros/robots/g1_description/g1_29dof_rev_1_0.urdf"
s,c=omni.kit.commands.execute("URDFCreateImportConfig")
c.merge_fixed_joints=False;c.fix_base=False
s,p=omni.kit.commands.execute("URDFParseAndImportFile",urdf_path=u,import_config=c,get_articulation_root=True)

st=omni.usd.get_context().get_stage()
sc=UsdPhysics.Scene.Define(st,Sdf.Path("/physicsScene"))
sc.CreateGravityDirectionAttr().Set(Gf.Vec3f(0,0,-1))
sc.CreateGravityMagnitudeAttr().Set(9.81)
PhysxSchema.PhysxSceneAPI.Apply(st.GetPrimAtPath("/physicsScene"))
px=PhysxSchema.PhysxSceneAPI.Get(st,"/physicsScene")
px.CreateEnableGPUDynamicsAttr(False)
PhysicsSchemaTools.addGroundPlane(st,"/groundPlane","Z",1500,Gf.Vec3f(0,0,-0.25),Gf.Vec3f(0.5))

w.reset()
import time;t0=time.time()
N=600
for i in range(N):
    w.step(render=False)
dt=time.time()-t0

import torch;x=torch.randn(1000,1000).cuda();_=x@x.T
sys.stderr.write("\n"+"="*60+"\n")
sys.stderr.write("  G1 29-DOF SIMULATION\n")
sys.stderr.write(f"  Steps: {N} in {dt:.1f}s = {N/dt:.0f} fps\n")
sys.stderr.write(f"  GPU: {torch.cuda.get_device_name(0)}\n")
sys.stderr.write(f"  PyTorch: {torch.__version__}\n")
sys.stderr.write("  ✅ All OK\n")
sys.stderr.write("="*60+"\n\n")
app.close()
' 2>&1 | grep -E "G1|Steps:|GPU:|PyTorch|=====|All OK" || true

# ---- Interactive shell mode ----
else
    echo "=== Isaac Sim 5.1.0 Container ==="
    echo "Container:  $CONTAINER_NAME"
    echo "Workspace:  $WORKSPACE_DIR → /workspace"
    echo "Sim repos:  $SIM_REPO_DIR → /sim"
    echo ""
    echo "Inside container:"
    echo "  source /isaac-sim/setup_python_env.sh"
    echo "  /isaac-sim/python.sh -c 'import torch; print(torch.cuda.get_device_name(0))'"
    echo "  /isaac-sim/runapp.sh   # launch GUI (from interactive shell)"

    docker run --name "$CONTAINER_NAME" \
      --entrypoint bash -it --gpus all \
      -e "ACCEPT_EULA=Y" \
      -e "PRIVACY_CONSENT=Y" \
      -e "OMNI_KIT_ACCEPT_EULA=YES" \
      -e "OMNI_KIT_ALLOW_ROOT=1" \
      --rm --network=host \
      --shm-size=8g \
      -v "$CACHE_DIR"/kit:/isaac-sim/kit/cache:rw \
      -v "$CACHE_DIR"/ov:/root/.cache/ov:rw \
      -v "$CACHE_DIR"/pip:/root/.cache/pip:rw \
      -v "$CACHE_DIR"/glcache:/root/.cache/nvidia/GLCache:rw \
      -v "$CACHE_DIR"/computecache:/root/.nv/ComputeCache:rw \
      -v "$CACHE_DIR"/logs:/root/.nvidia-omniverse/logs:rw \
      -v "$CACHE_DIR"/data:/root/.local/share/ov/data:rw \
      -v "$CACHE_DIR"/documents:/root/Documents:rw \
      -v "$WORKSPACE_DIR:/workspace:rw" \
      -v "$SIM_REPO_DIR:/sim:rw" \
      "$IMAGE"
fi
