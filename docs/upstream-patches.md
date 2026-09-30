# 上游兼容补丁（rsl-rl-lib 5.0.1）

> `sim/` 里的三个上游脚本 + IsaacLab 的兼容层，不改这四处就跑不起来。
> 别再手工改了：`python3 scripts/apply_sim_fixes.py` 一行搞定，加 `--check` 只看不动。

## 怎么判过没过

```bash
python3 scripts/apply_sim_fixes.py --sim-root <你的仓库>/sim --check   # exit 0 = 四处全在修好的状态
python3 scripts/apply_sim_fixes.py --sim-root <你的仓库>/sim           # 打补丁；跑第二遍全 SKIP
```

`bash scripts/start.sh install` 会自动做这两步；`train` 只提醒不拦你。
每个目标只会是四种结果之一：`PASS`（已修好）/ `FIX`（改了并通过语法检查）/ `SKIP`（幂等跳过）/ `UNMATCHED`（上游变了，脚本会把它拉到的上游原文和你的文件片段一起打出来，让人对着改）。

没修好的症状，认这两个就够：

| 崩在哪 | 报错 | 对应第几处 |
|---|---|---|
| 一开始训练就崩 | `TypeError: MLPModel.__init__() got an unexpected keyword argument 'stochastic'` | 1 / 4 |
| `play` 导出模型时崩 | `'PPO' object has no attribute 'policy'` | 2 |

## 四处分别是什么（2026-09-30 逐条对着上游原文核过）

| # | 文件 | 要改成什么 | 上游现状（实测） |
|---|---|---|---|
| 1 | `unitree_rl_lab/scripts/rsl_rl/cli_args.py` `parse_rsl_rl_cfg()` | 调 `handle_deprecated_rsl_rl_cfg(cfg, 已装版本)`，把 5.x 不认的 `stochastic` 字段去掉 | `main` 分支**从来没调用过**（该文件自 2025-06-30 未再改动），所以要修 |
| 2 | `unitree_rl_lab/scripts/rsl_rl/play.py` 导出段 | 用 `runner.export_policy_to_jit()` / `runner.export_policy_to_onnx()`；rsl-rl 5.x 里 `PPO.policy` 已改名 `.actor`、`PPO.actor_critic` 删除 | `main` 分支仍在用旧的 `export_policy_as_jit/as_onnx`（5.0.1 里这俩函数已经不存在），所以要修 |
| 3 | `IsaacLab/.../isaaclab_rl/rsl_rl/utils.py` `_update_distribution_cfg()` | 访问 `model_cfg.stochastic` 之前先 `hasattr` 兜一层 | 上游 `develop` HEAD 到 2026-09-27 仍是裸访问（`if model_cfg.distribution_cfg is None and model_cfg.stochastic is True:`），所以要修 |
| 4 | `unitree_rl_lab/scripts/rsl_rl/train.py` `main()` | 保证 `handle_deprecated_rsl_rl_cfg()` **恰好调用一次** | 上游是 **0 次**（0 次同样会崩，走的是同一条 `to_dict() → **kwargs` 的路）。老教程记的"删掉重复的那一次"是针对手工改过两遍的本机文件，新克隆用不上 |

## 一个版本前提，别踩

补丁 1 和 4 要调的 `handle_deprecated_rsl_rl_cfg()` 本身来自 IsaacLab。
**IsaacLab `v2.3.x` 里连 `isaaclab_rl/rsl_rl/utils.py` 这个文件都没有**（`unitree_rl_lab` 的 README 徽章写的是 IsaacLab 2.3.0，那是它自己没跟上 5.x 时的老搭配），所以：

- 按 1.5 的做法克隆 IsaacLab 默认分支即可，脚本会先探一下这个函数在不在，不在就直接拒绝往下打，免得你四处"补丁成功"、真训练时才崩一个看不懂的 `ImportError`。
- 你用的 IsaacLab / unitree_rl_lab 具体是哪个 commit，记在自己的小本本上。上游哪天改了这几处，脚本会报 `UNMATCHED` 而不是硬改。
