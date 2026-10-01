# 宇树 G1 机器人 — 从打开终端到训出会走路的 AI

> 一个面向**零基础**学生的强化学习实战教程。
>
> 不需要机器学习背景。不需要懂 Linux。打开终端，跟着走——我们一路摸排过来的。

<p align="center">
  <img src="showcase/gifs/小幅行走(20260624-4096envs-182ckpts-18100.pt).gif" alt="G1 小幅行走 — 4096 envs, 182 ckpts" width="480">
</p>

---

## 这是什么？

这是一个**真实的项目实战记录**，不是一个教科书。

我们在 Ubuntu 26.04 上从零搭建了 Unitree G1 人形机器人的强化学习训练环境。期间遇到了：
- 🖥️ **终端怎么用**（连 `cd` 都不会的时候）
- 🐳 **Docker 到底是什么**（菜谱 vs 厨房）
- 📝 **Git 能管什么、不能管什么**（为什么 GitHub 不能传 23GB 的镜像）
- 🐍 **Python/NumPy/PyTorch**（从"`print` hello"到搭神经网络）
- 🔧 **GPU 驱动版本**（580 能跑，595 崩了——查了一下午的 bug）
- 🤖 **强化学习到底是什么**（训狗的类比，5 分钟看懂）
- 🚀 **G1 训练实操**（从 `bash scripts/start.sh train` 到看到机器人走路）



---

## 🚀 三步跑起来

```bash
# 1. 拿到菜谱
git clone git@github.com:GXMZU-AITECC/unitree-g1-demo.git ~/projects/g1-rl
cd ~/projects/g1-rl

# 2. 搭厨房（拉取 Isaac Sim 镜像，23GB，首次约 30 分钟；国内代理下可能更久）
# 国内用户先看 1_environment/1.6_proxy_setup.md 配代理！

# 3. 训练！
bash scripts/start.sh install   # 只做一次
bash scripts/start.sh train     # 开始训练
```

---

## 📖 学习路线

**按你遇到问题的顺序排列，不是按教科书章节目录排列。**

| # | 章节 | 你在这里学到什么 | 适合 |
|---|------|-----------------|------|
| 🟢 | [0_getting_started/](0_getting_started/) | 终端怎么用、Git 是什么、RL 训狗类比、你的电脑能不能跑 | **所有人从这开始** |
| 🔵 | [1_environment/](1_environment/) | apt/pip/docker pull 三种装软件方式、Docker 本质、GPU 驱动、代理 | 配环境碰到问题来看 |
| 🟡 | [2_fundamentals/](2_fundamentals/) | Python+NumPy 速览、Jupyter 怎么用、Q-Learning→DQN、PyTorch 搭网络、bash 脚本怎么读 | 想看代码怎么写的 |
| 🟠 | [3_g1_project/](3_g1_project/) | 项目架构全景图、逐行读 start.sh、训练输出解读、配置参数调优、回放与导出 | 跑训练时碰到问题来看 |
| 🔴 | [4_advanced/](4_advanced/) | Git 多人协作、Docker 镜像构建与推送、VS Code 一键环境、多机部署 | 要做比赛/团队协作时看 |
| 🟣 | [5_deployment/](5_deployment/) | ONNX 导出、C++ 编译、FSM 状态机、dDS 通信、真机部署实战 | 部署到真机时看 |

---

## 🗺️ 项目结构

```
unitree-g1/
├── 0_getting_started/     # 🟢 新手第一站：终端、Git、RL是什么、硬件
├── 1_environment/         # 🔵 搭环境：包管理器、Docker、GPU驱动、代理
├── 2_fundamentals/        # 🟡 基础实操：Python、Jupyter、RL算法、PyTorch、bash
├── 3_g1_project/          # 🟠 项目实战：架构、start.sh解读、训练、配置
├── 4_advanced/            # 🔴 拓展：Git协作、Docker深入、竞赛部署
├── 5_deployment/          # 🟣 真机部署：ONNX导出、C++编译、FSM状态机
├── notebooks/             # 📓 交互式 Python Notebook（填空式学习）
├── showcase/              # 🏆 成果展示：训练GIF、截图（文件名即描述）
├── docs/                  # 📋 项目文档：训练记录、硬件实测、失败分析、架构笔记
├── scripts/               # 🔧 一键脚本（start.sh 训练 / deploy.sh 部署）
├── deploy/                # 🤖 真机部署工具包（C++ 源码、ONNX Runtime 脚本）
├── docker/                # 🐳 Dockerfile + compose 配置
├── .devcontainer/         # 🖥️ VS Code 开发容器
└── sim/                   # 🔬 依赖仓库（gitignored，每台机器自行克隆）
```

---

## 🔧 常用命令

```bash
# ── 仿真训练 ──
bash scripts/start.sh                    # 交互式菜单
bash scripts/start.sh install            # 安装依赖（首次）
bash scripts/start.sh train              # 无头训练
bash scripts/start.sh train-gui          # 带 3D 画面训练
bash scripts/start.sh play <run> <ckpt>  # 回放模型
tensorboard --logdir ~/projects/g1-rl/logs/rsl_rl/unitree_g1_29dof_velocity --bind_all --port 6006

# ── 真机部署 ──
bash scripts/deploy.sh export            # 导出 ONNX 模型
bash scripts/deploy.sh push <robot_ip>   # 推送到 G1 机器人
bash scripts/deploy.sh install           # 安装 ONNX Runtime
bash scripts/deploy.sh build             # 编译 C++ 控制器
```

---

## ⚠️ 两个硬性要求

- **NVIDIA 显卡**（RTX 3060+），AMD/Intel 核显/GTX 都不行
- **驱动 580.x**（595 会导致 Isaac Sim 崩溃）

---

## 🤔 常见问题

| 问题 | 答案 |
|------|------|
| **Git 能管环境吗？** | 不能。Git 管菜谱（代码），Docker 管厨房（环境）。[详解→](0_getting_started/0.3_github_and_git.md) |
| **为什么有 3 种装软件的命令？** | apt 管系统软件，pip 管 Python 包，docker pull 管完整环境。[详解→](1_environment/1.1_package_managers.md) |
| **看不懂训练输出？** | [3.2_第一次训练](3_g1_project/3.2_first_train.md) |
| **3D 视口黑屏？** | 容器需要 `--user 0:0`。[详解→](1_environment/1.4_nvidia_driver_gpu.md) |
| **`docker pull` 超时？** | 在国内需要配代理。[1.6_代理配置](1_environment/1.6_proxy_setup.md) |
| **报错了？** | [3.7_报错速查](3_g1_project/3.7_troubleshooting.md) |

---

## ⚙️ 技术栈

| 组件 | 版本 | 干什么用 |
|------|------|----------|
| Ubuntu | 26.04 | 你的操作系统 |
| Docker | 29.1+ | 在容器里跑 Isaac Sim |
| Isaac Sim | 5.1.0 (NGC) | NVIDIA 机器人物理仿真引擎 |
| Python | 3.10 (Docker 容器内置) | Isaac Sim 自带，不需要自己装 |
| RSL-RL | 5.0.1 | ETH 的 PPO 算法实现 |
| PyTorch | (Isaac Sim 内置) | 神经网络框架 |
| ONNX Runtime | 1.22.0 | C++ 模型推理引擎（真机部署用） |
| ROS 2 | Lyrical Luth | 实机部署（可选） |

---

## 📚 参考资料

- [Unitree 官方 RL 训练库](https://github.com/unitreerobotics/unitree_rl_lab)
- [NVIDIA Isaac Sim 文档](https://docs.isaacsim.omniverse.nvidia.com/)
- [OpenAI Spinning Up — RL 入门经典](https://spinningup.openai.com/)

---

> 我们从"终端是什么"开始，一路摸到了 G1 会走路。你也可以。
