# G1 深度相机 RealSense D435i 使用指南

更新时间：2025-11-17

本文介绍 Unitree G1 头部 RealSense D435i 深度相机的硬件信息、查看数据的方法，以及通过 ROS 和 librealsense SDK 获取深度、彩色、红外和 IMU 数据的基本流程。

## 1. 相机简介

G1 的深度相机安装在机器人头顶，型号为 Intel RealSense D435i。相机包含双目红外相机（global shutter）、激光发射器、RGB 相机（rolling shutter）和 6 轴 IMU。

相机坐标系、深度相机坐标系与机器人中心坐标系之间的变换关系，应以实际安装标定结果为准；使用前请记录外参和坐标轴约定。

官方资料：

- [产品主页](https://www.intelrealsense.com/depth-camera-d435/realsense)
- [入门文档](https://dev.intelrealsense.com/docs/docs-get-started)
- [IntelRealSense GitHub 组织](https://github.com/IntelRealSense)

## 2. 使用前准备

在 G1 的 NX 计算平台上使用 SDK 前，需要先安装 librealsense。确认 USB 连接和设备识别正常后，再启动查看工具或运行自己的程序。

### 2.1 Windows

直接安装或运行 RealSense Viewer。发行版可从 [librealsense Releases](https://github.com/IntelRealSense/librealsense/releases) 获取。

### 2.2 Ubuntu

根据系统版本选择官方安装说明：

- [Ubuntu 18/20/22 LTS 安装说明](https://github.com/IntelRealSense/librealsense/blob/master/doc/installation.md)
- [NVIDIA Jetson 安装说明](https://github.com/IntelRealSense/librealsense/blob/master/doc/installation_jetson.md)
- [Raspberry Pi 安装说明](https://github.com/IntelRealSense/librealsense/blob/master/doc/RaspberryPi3.md)

安装完成后，可在终端运行：

```bash
realsense-viewer
```

在 Viewer 中检查深度、彩色、左右红外和 IMU 流是否正常，并确认设备支持的分辨率和帧率。

## 3. 获取数据

### 3.1 通过 ROS

ROS 驱动位于 [realsense-ros](https://github.com/IntelRealSense/realsense-ros)。按照仓库 README 完成安装和启动后，可以订阅深度图、彩色图、点云和 IMU 话题。适合已经使用 ROS 进行模块编排的项目。

### 3.2 通过 librealsense SDK

SDK 源码位于 [librealsense](https://github.com/IntelRealSense/librealsense)。可参考 SDK 的 `examples` 目录，典型流程如下：

1. 创建 `rs2::context`，枚举并选择设备。
2. 查询传感器和支持的 option，必要时设置曝光、激光功率和视觉预设。
3. 使用 `rs2::config` 配置 depth、infrared、color、gyro 和 accel 流。
4. 启动 `rs2::pipeline`，读取 frameset 和 motion frame。
5. 从 video stream profile 获取宽高、焦距和主点等内参。
6. 按需使用 temporal filter 等后处理，再转换为 OpenCV 图像。

下面是一个最小的 C++ 结构示例（具体分辨率和帧率应按设备能力调整）：

```cpp
#include <librealsense2/rs.hpp>

int main() {
    rs2::pipeline pipe;
    rs2::config cfg;
    cfg.enable_stream(RS2_STREAM_DEPTH);
    cfg.enable_stream(RS2_STREAM_COLOR);
    cfg.enable_stream(RS2_STREAM_GYRO);
    cfg.enable_stream(RS2_STREAM_ACCEL);

    auto profile = pipe.start(cfg);
    for (;;) {
        rs2::frameset frames = pipe.wait_for_frames();
        auto depth = frames.get_depth_frame();
        auto color = frames.get_color_frame();
        // 在这里处理 depth、color 和 IMU 数据。
    }
    pipe.stop();
}
```

读取内参时使用 video stream profile 的 `get_intrinsics()`，可获得 `fx`、`fy`、`ppx`、`ppy` 和畸变参数。实际项目中还应检查帧为空、设备断连和时间戳异常等情况。

## 4. USB 连接注意事项

USB 3.0 连接通常可以提供更多可用的分辨率和帧率组合，RealSense Viewer 会显示当前连接下设备支持的配置。USB 2.0 带宽较低，部分场景需要通过 Hub 转接后才能稳定使用 SDK，且可用帧率和分辨率会与 USB 3.0 不同。

在 G1 NX 平台上使用时，建议：

- 优先使用可靠的 USB 3.0 连接和线缆；
- 先用 `realsense-viewer` 验证设备和流配置，再运行机器人程序；
- 不要直接假设某个分辨率、帧率或 IMU 组合一定受支持；
- 对深度、彩色、红外和 IMU 分别检查时间戳与帧有效性。

## 5. 常见排查顺序

1. 确认相机供电、USB 线缆和连接端口正常。
2. 运行 `realsense-viewer`，确认设备能够枚举。
3. 检查 librealsense 版本与系统架构是否匹配。
4. 降低分辨率或帧率，排除 USB 带宽不足。
5. 在 SDK 程序中打印设备序列号、传感器名称、流 profile 和内参。
6. 如果使用 ROS，再检查驱动节点和对应 topic 是否发布。

## 6. 参考链接

- [librealsense](https://github.com/IntelRealSense/librealsense)
- [realsense-ros](https://github.com/IntelRealSense/realsense-ros)
- [RealSense D435 系列资料](https://www.intelrealsense.com/depth-camera-d435/realsense)
