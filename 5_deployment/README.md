# 🟣 真机部署

> 你已经训练出了一个能走路的 AI。现在，按官方流程一步步把它送进真正的机器人身体里。

---

## 官方部署流程

宇树官方的部署流程是 **4 步**，不是 3 步：

```
Train ──→ Sim2Sim ──→ Sim2Real
  ↑                      ↑
训练模型         先在 MuJoCo 仿真里验证，
                确认模型跑稳了，再上真机
```

> ⚠️ **为什么要 Sim2Sim**：仿真和真机之间有差距（sim-to-real gap）。但 Isaac Sim（训练用）和 MuJoCo（验证用）是两个不同的物理引擎。如果模型 **在两个仿真器里都能走路**，说明策略足够鲁棒，可以上真机。如果连 MuJoCo 都走不稳，真机肯定也不行——别浪费时间。

---

## 前提条件

在开始这一章之前，你应该：
- ✅ 跑过至少一次训练，知道自己训练出来的模型在 `logs/` 下的哪个目录
- ✅ 有一台能接触到的 G1 机器人（实验室里的，或者你自己的）

---

## 📖 教程列表

| # | 教程 | 回答什么问题 |
|---|------|------------|
| [5.1](5.1_deploy_architecture.md) | 部署全景图 | 仿真到真机是怎么连起来的？ONNX、DDS、FSM 都是什么？ |
| [5.2](5.2_connect_to_robot.md) | 连接机器人 | SSH 是什么？怎么从你的电脑连到机器人？IP 在哪查？ |
| [5.3](5.3_model_export.md) | 导出 ONNX 模型 | 把 .pt 模型转成机器人能读的 .onnx 格式 |
| [5.4](5.4_sim2sim_validation.md) | 🔬 Sim2Sim：MuJoCo 验证 | **上真机之前**，先在 MuJoCo 仿真里跑一遍模型 |
| [5.5](5.5_deploy_code_setup.md) | 部署代码准备 | 把 C++ 代码从 sim/ 拷到 deploy/，准备编译 |
| [5.6](5.6_build_on_robot.md) | 在机器人上编译 | 把 C++ 代码变成可运行的程序 |
| [5.7](5.7_run_on_robot.md) | 在机器人上运行 | 手柄怎么按？状态怎么切？怎么安全地停下来？ |
| [5.8](5.8_troubleshooting.md) | 排错速查 | 机器人不动？报错了？查这张表 |
| [5.9](5.9_how_it_works.md) | 源码深度解读 | 每一行 C++ 代码在干什么（给想深入的人看） |
| [5.10](5.10_mimic_controller.md) | 附加：动作模仿 | 让机器人跳舞 —— Mimic 的原理和启用方法 |

---

## 🚀 走通全链路（一张图）

```
你的电脑                        G1 机器人
════════                        ════════

1. bash scripts/deploy.sh export
   从训练日志复制 ONNX 到 deploy/

2. 🔬 Sim2Sim 验证（MuJoCo）
   ./unitree_mujoco              ← 启动 MuJoCo 仿真
   ./g1_ctrl                     ← 控制器跑同一个 ONNX 模型
   确认在 MuJoCo 里能走路 ──→

3. bash scripts/deploy.sh push 192.168.1.100
   通过网络传到机器人 ──────────►  4. SSH 连上去
                                    cd ~/g1-rl-deploy
                                    bash install_onnxruntime.sh
                                    cd g1_29dof/build
                                    cmake .. && make -j

                                   5. ./g1_ctrl --network eth0
                                      L2+↑ → 站立 → R1+X → 走路！
```

---

## 本章要用到的命令

在你电脑上：
```bash
bash scripts/deploy.sh export            # 导出模型

# Sim2Sim 验证（MuJoCo）
cd ~/projects/g1-rl/sim/unitree_mujoco/simulate/build
./unitree_mujoco                          # 启动仿真
cd ~/projects/g1-rl/deploy/g1_29dof/build
./g1_ctrl                                 # 跑 RL 策略

# 推到真机
bash scripts/deploy.sh push <机器人IP>    # 传代码到机器人
```

在机器人上（SSH 连过去之后）：
```bash
cd ~/g1-rl-deploy
bash install_onnxruntime.sh              # 装 ONNX Runtime（只需一次）
export ONNXRUNTIME_ROOT=~/g1-rl-deploy/thirdparty/onnxruntime-linux-x64-1.22.0
cd g1_29dof && mkdir -p build && cd build
cmake .. && make -j                       # 编译
./g1_ctrl --network eth0                  # 运行！
```
