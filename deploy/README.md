# deploy/ — G1 机器人真机部署工具包

## 这个目录里有什么？

| 目录/文件 | 用途 |
|-----------|------|
| `include/` | 共享的 C++ 头文件（FSM 状态机、Isaac Lab 环境封装、ONNX Runtime 推理器） |
| `g1_29dof/` | G1 29-DOF 速度跟踪控制器（CMake 项目，在机器人上编译运行） |
| `thirdparty/` | ONNX Runtime 预编译库（gitignored，通过脚本下载） |
| `install_onnxruntime.sh` | 一键下载安装 ONNX Runtime 1.22.0 |

## 怎么用？

```bash
# 第一步：导出你训练好的模型
bash scripts/deploy.sh export

# 第二步：安装 ONNX Runtime（在机器人上执行）
bash deploy/install_onnxruntime.sh

# 第三步：编译控制器（在机器人上执行）
bash scripts/deploy.sh build

# 第四步：推送到机器人
bash scripts/deploy.sh push 192.168.123.161
```

## 前提条件

- **在机器人上**编译需要：`unitree_sdk2`、`cmake`、`yaml-cpp`、`eigen3`、`boost`
- 详细教程见 [5_deployment/](../5_deployment/README.md)

## 文件来源说明

`include/` 和 `g1_29dof/src/` 等 C++ 源码来自 Unitree 官方的 [unitree_rl_lab](https://github.com/unitreerobotics/unitree_rl_lab) 仓库的 `deploy/` 目录。
本项目只复制了 G1-29dof 相关的部分，并做了以下改动：
- **CMakeLists.txt**：ONNX Runtime 路径改用环境变量 `ONNXRUNTIME_ROOT`
- **config.yaml**：默认禁用 Mimic（动作模仿）模式，只保留 Velocity（速度跟踪）FSM
