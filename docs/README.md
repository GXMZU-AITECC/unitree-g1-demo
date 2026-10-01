# 项目文档

> 训练实战记录、架构讨论、问题分析。按主题分文件，方便查找。

## 📖 文档索引

| 文档 | 内容 | 适合 |
|------|------|------|
| [training-log.md](training-log.md) | 每次训练的配置参数、GPU 利用率、结果 | 想复现某个训练配置 |
| [hardware-profile.md](hardware-profile.md) | RTX 3080 + 14G RAM 实测数据：envs 甜点、显存消耗 | 搞不清自己硬件能跑几个环境 |
| [failure-analysis.md](failure-analysis.md) | 训练 NaN 崩溃深度分析：reward 惩罚、terrain curriculum、explosion chain | 训练崩了、机器人不动 |
| [architecture-notes.md](architecture-notes.md) | CLI 参数流、start.sh 设计决策、参数覆盖链 | 好奇"改了配置为什么不生效" |
| [reward-design.md](reward-design.md) | 18个 reward term 全景表、权重分析、推荐调整 | 想调 reward 权重 |
| [troubleshooting.md](troubleshooting.md) | 常见报错速查（补充教程 3.7） | 遇到报错来这里搜 |
| [upstream-patches.md](upstream-patches.md) | `sim/` 里那四处上游兼容补丁：改什么、怎么判过没过、版本前提 | `install` 报补丁没打全、或换了机器 |

## 🔗 其他资源

- 教程：从 [0_getting_started/](../0_getting_started/) 到 [5_deployment/](../5_deployment/) 的六层渐进式教程
- 成果展示：[showcase/](../showcase/) — GIF 和训练截图
- 主 README：[../README.md](../README.md)
