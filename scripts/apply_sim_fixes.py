#!/usr/bin/env python3
"""apply_sim_fixes.py — idempotent rsl-rl-lib==5.0.1 compatibility patcher for the G1 demo sim tree.

Targets (relative to --sim-root, default ~/projects/g1-rl/sim):
  1. unitree_rl_lab/scripts/rsl_rl/cli_args.py   — parse_rsl_rl_cfg() must call handle_deprecated_rsl_rl_cfg()
  2. unitree_rl_lab/scripts/rsl_rl/play.py       — rsl-rl 5.x export API (PPO.policy->PPO.actor; runner.export_policy_to_jit/_to_onnx)
  3. IsaacLab/source/isaaclab_rl/isaaclab_rl/rsl_rl/utils.py
                                                   — hasattr() guard before model_cfg.stochastic in _update_distribution_cfg()
  4. unitree_rl_lab/scripts/rsl_rl/train.py      — exactly ONE handle_deprecated_rsl_rl_cfg() call (fresh clone has 0,
                                                   double-manual-patched clones have 2; final recorded state is 1)

All anchors were verified against files fetched from the real upstream sources on 2026-09-30:
  https://github.com/unitreerobotics/unitree_rl_lab  (branch main; these 3 scripts unchanged since 2025-06-30 / 2025-10-24 / 2025-11-18)
  https://github.com/isaac-sim/IsaacLab             (branch develop; utils.py variants verified at commits
                                                     47c9f95eea (elif form), 243659ee0a (elif form), 4b1234ba23 / HEAD (and form))
  rsl-rl-lib 5.0.1 sdist from PyPI (released 2026-03-04): PPO has .actor/.critic (no .policy/.actor_critic);
  MLPModel.__init__() takes NO **kwargs; OnPolicyRunner.export_policy_to_jit()/_export_policy_to_onnx() exist.

Modes:
  python apply_sim_fixes.py --sim-root <path>          # apply: SKIP / FIX / UNMATCHED per target
  python apply_sim_fixes.py --sim-root <path> --check  # check only; exit 0 iff all four PASS, else exit 1
"""

from __future__ import annotations

import argparse
import ast
import sys
from pathlib import Path

# --------------------------------------------------------------------------------------------
# Reference snippets that were really fetched from upstream (2026-09-30).
# These are printed as "current upstream" evidence when anchors no longer match anything.
# --------------------------------------------------------------------------------------------

REF = {
    "cli_args.py": {
        "source": (
            "https://raw.githubusercontent.com/unitreerobotics/unitree_rl_lab/main/scripts/rsl_rl/cli_args.py"
            "  (fetched 2026-09-30; file last touched upstream 2025-06-30, commit 419f804827)"
        ),
        "snippet": (
            "    # --- upstream parse_rsl_rl_cfg() tail (unitree_rl_lab@main, lines 55-59) ---\n"
            '    rslrl_cfg: RslRlOnPolicyRunnerCfg = load_cfg_from_registry(task_name, "rsl_rl_cfg_entry_point")\n'
            '    if rslrl_cfg.experiment_name == "":\n'
            '        rslrl_cfg.experiment_name = task_name.lower().replace("-", "_").removesuffix("_play")\n'
            "    rslrl_cfg = update_rsl_rl_cfg(rslrl_cfg, args_cli)\n"
            "    return rslrl_cfg"
        ),
    },
    "play.py": {
        "source": (
            "https://raw.githubusercontent.com/unitreerobotics/unitree_rl_lab/main/scripts/rsl_rl/play.py"
            "  (fetched 2026-09-30; file last touched upstream 2025-10-24, commit 5d1f3dcedf)"
        ),
        "snippet": (
            "    # --- upstream export region (unitree_rl_lab@main play.py, lines 132-152) ---\n"
            "    # extract the neural network module\n"
            "    # we do this in a try-except to maintain backwards compatibility.\n"
            "    try:\n"
            "        # version 2.3 onwards\n"
            "        policy_nn = runner.alg.policy\n"
            "    except AttributeError:\n"
            "        # version 2.2 and below\n"
            "        policy_nn = runner.alg.actor_critic\n"
            "    ...\n"
            '    export_policy_as_jit(policy_nn, normalizer=normalizer, path=export_model_dir, filename="policy.pt")\n'
            '    export_policy_as_onnx(policy_nn, normalizer=normalizer, path=export_model_dir, filename="policy.onnx")'
        ),
    },
    "utils.py": {
        "source": (
            "https://raw.githubusercontent.com/isaac-sim/IsaacLab/develop/source/isaaclab_rl/isaaclab_rl/rsl_rl/utils.py"
            "  (fetched 2026-09-30; also variants at 47c9f95eea L245 / 243659ee0a L247 / 4b1234ba23 L289)"
        ),
        "snippet": (
            "    # --- upstream _update_distribution_cfg() head ---\n"
            "    # develop HEAD (eb4bb3be65, 2026-09-27), line 302:\n"
            "    if model_cfg.distribution_cfg is None and model_cfg.stochastic is True:\n"
            "    # 47c9f95eea (2026-03-05), line 245 / 243659ee0a (2026-09-15), line 247:\n"
            "    elif model_cfg.stochastic is True:  # distribution config is None but stochastic output is requested"
        ),
    },
    "train.py": {
        "source": (
            "https://raw.githubusercontent.com/unitreerobotics/unitree_rl_lab/main/scripts/rsl_rl/train.py"
            "  (fetched 2026-09-30; file last touched upstream 2025-11-18, commit 4e08d96505)"
        ),
        "snippet": (
            "    # --- upstream main() cfg region (unitree_rl_lab@main train.py, lines 124-128) ---\n"
            "    agent_cfg = cli_args.update_rsl_rl_cfg(agent_cfg, args_cli)\n"
            "    env_cfg.scene.num_envs = args_cli.num_envs if args_cli.num_envs is not None else env_cfg.scene.num_envs\n"
            "    agent_cfg.max_iterations = (\n"
            "        args_cli.max_iterations if args_cli.max_iterations is not None else agent_cfg.max_iterations\n"
            "    )"
        ),
    },
}

DRIFT_MESSAGE = "上游已变更，本脚本锚点失效，需人工核对"

# --------------------------------------------------------------------------------------------
# Shared helpers
# --------------------------------------------------------------------------------------------

CALL_NAME = "handle_deprecated_rsl_rl_cfg("


class FileState:
    PASS = "PASS"          # already in the fixed state
    FIX = "FIX"            # unpatched, exact anchor found -> fixable
    UNMATCHED = "UNMATCHED"  # needs fixing but anchor does not match
    MISSING = "MISSING"    # file does not exist


def read_file(path: Path) -> tuple[str, str]:
    """Return (text, newline) preserving the original newline style."""
    raw = path.read_bytes().decode("utf-8")
    nl = "\r\n" if "\r\n" in raw else "\n"
    return raw.replace("\r\n", "\n"), nl


def write_file(path: Path, text: str, nl: str) -> None:
    path.write_bytes((text.replace("\n", nl) if nl == "\r\n" else text).encode("utf-8"))


def count_handler_calls(text: str) -> list[int]:
    """Line numbers (0-based) with a handle_deprecated_rsl_rl_cfg() CALL (imports excluded)."""
    hits = []
    for i, line in enumerate(text.split("\n")):
        s = line.strip()
        if CALL_NAME in s and not s.startswith(("import ", "from ")):
            hits.append(i)
    return hits


def make_handler_block(var: str) -> list[str]:
    """Insertion block: call handle_deprecated_rsl_rl_cfg on `var` (function-local imports,
    because these scripts are imported before the Isaac app launches). Verified API:
    isaaclab_rl/rsl_rl/utils.py defines handle_deprecated_rsl_rl_cfg(agent_cfg, installed_version)."""
    return [
        "",
        "    # handle deprecated rsl-rl configurations for the installed rsl-rl version",
        "    # (rsl-rl-lib >= 5.0.0: strips the deprecated `stochastic`/`init_noise_std`/... fields,",
        "    #  otherwise MLPModel.__init__() rejects them when the cfg dict is expanded)",
        "    import importlib.metadata",
        "",
        "    from isaaclab_rl.rsl_rl.utils import handle_deprecated_rsl_rl_cfg",
        "",
        f"    {var} = handle_deprecated_rsl_rl_cfg({var}, importlib.metadata.version(\"rsl-rl-lib\"))",
    ]


def dedupe_calls(text: str) -> tuple[str, bool]:
    """Remove repeated identical handle_deprecated_rsl_rl_cfg() CALL lines, keeping the first.
    Returns (new_text, changed). Refuses (changed=False) when the duplicate calls differ."""
    lines = text.split("\n")
    call_idx = count_handler_calls(text)
    if len(call_idx) < 2:
        return text, False
    first = lines[call_idx[0]].rstrip()
    if any(lines[i].rstrip() != first for i in call_idx[1:]):
        return text, False
    drop = set(call_idx[1:])
    return "\n".join(l for i, l in enumerate(lines) if i not in drop), True


# --------------------------------------------------------------------------------------------
# Target 1: unitree_rl_lab/scripts/rsl_rl/cli_args.py
# --------------------------------------------------------------------------------------------

CLI_ANCHOR = [
    "    rslrl_cfg = update_rsl_rl_cfg(rslrl_cfg, args_cli)",
    "    return rslrl_cfg",
]


def cli_args_state(text: str) -> str:
    calls = count_handler_calls(text)
    if len(calls) == 1:
        return FileState.PASS
    if len(calls) >= 2:
        deduped, ok = dedupe_calls(text)
        return FileState.FIX if ok else FileState.UNMATCHED
    idx = text.split("\n").index(CLI_ANCHOR[0]) if CLI_ANCHOR[0] in text.split("\n") else -1
    if idx >= 0 and text.split("\n")[idx + 1] == CLI_ANCHOR[1]:
        return FileState.FIX
    return FileState.UNMATCHED


def cli_args_fix(text: str) -> str:
    lines = text.split("\n")
    try:
        idx = lines.index(CLI_ANCHOR[0])
    except ValueError:
        raise ValueError("anchor not found: rslrl_cfg = update_rsl_rl_cfg(rslrl_cfg, args_cli)")
    if lines[idx + 1] != CLI_ANCHOR[1]:
        raise ValueError("anchor drift: return rslrl_cfg not immediately after update_rsl_rl_cfg call")
    new_lines = lines[: idx + 1] + make_handler_block("rslrl_cfg") + lines[idx + 1:]
    return "\n".join(new_lines)


# --------------------------------------------------------------------------------------------
# Target 2: unitree_rl_lab/scripts/rsl_rl/play.py
# --------------------------------------------------------------------------------------------

PLAY_START = "    # extract the neural network module"
PLAY_END_PREFIX = "    export_policy_as_onnx(policy_nn"
PLAY_LEGACY_MARKER = "        policy_nn = runner.alg.actor_critic"
PLAY_NEW_MARKER = "runner.export_policy_to_jit("
PLAY_OLD_IMPORT = (
    "from isaaclab_rl.rsl_rl import RslRlOnPolicyRunnerCfg, RslRlVecEnvWrapper,"
    " export_policy_as_jit, export_policy_as_onnx"
)
PLAY_NEW_IMPORT = "from isaaclab_rl.rsl_rl import RslRlOnPolicyRunnerCfg, RslRlVecEnvWrapper"

PLAY_NEW_BLOCK = [
    "    # export policy to onnx/jit using the rsl-rl >= 5.0 built-in exporters (rsl-rl-lib==5.0.1).",
    "    # rsl-rl 5.x renamed PPO.policy -> PPO.actor and removed PPO.actor_critic entirely; the",
    "    # runner's exporters already bundle the obs normalizer into the exported model.",
    '    export_model_dir = os.path.join(os.path.dirname(resume_path), "exported")',
    '    runner.export_policy_to_jit(path=export_model_dir, filename="policy.pt")',
    '    runner.export_policy_to_onnx(path=export_model_dir, filename="policy.onnx")',
]


def play_state(text: str) -> str:
    if PLAY_NEW_MARKER in text:
        return FileState.PASS
    if play_region_bounds(text) is not None:
        return FileState.FIX
    return FileState.UNMATCHED  # legacy marker/region not found in any known shape


def play_region_bounds(text: str) -> tuple[int, int] | None:
    lines = text.split("\n")
    try:
        start = lines.index(PLAY_START)
    except ValueError:
        return None
    end = -1
    for i in range(start, min(start + 40, len(lines))):
        if lines[i].startswith(PLAY_END_PREFIX):
            end = i
            break
    if end < 0:
        return None
    if PLAY_LEGACY_MARKER not in "\n".join(lines[start:end + 1]):
        return None
    return start, end


def play_fix(text: str) -> str:
    bounds = play_region_bounds(text)
    if bounds is None:
        raise ValueError("anchor not found: legacy export region (# extract the neural network module ...)")
    start, end = bounds
    lines = text.split("\n")
    new_lines = lines[:start] + PLAY_NEW_BLOCK + lines[end + 1:]
    # tidy the now-unused manual-export import (independently; keep going if it differs)
    new_lines = [PLAY_NEW_IMPORT if l == PLAY_OLD_IMPORT else l for l in new_lines]
    return "\n".join(new_lines)


# --------------------------------------------------------------------------------------------
# Target 3: IsaacLab source/isaaclab_rl/isaaclab_rl/rsl_rl/utils.py
# --------------------------------------------------------------------------------------------

UTILS_FUNC = "def _update_distribution_cfg("
UTILS_GUARD = 'hasattr(model_cfg, "stochastic") and model_cfg.stochastic is True'
# exact unguarded variants verified in fetched upstream (leading 4 spaces):
UTILS_VARIANT_A = '    elif model_cfg.stochastic is True:'                 # 47c9f95eea L245, 243659ee0a L247
UTILS_VARIANT_B = '    if model_cfg.distribution_cfg is None and model_cfg.stochastic is True:'  # develop HEAD L302


def _utils_cond_lines(text: str) -> list[int]:
    """Lines inside _update_distribution_cfg() that evaluate `model_cfg.stochastic is True`."""
    lines = text.split("\n")
    try:
        fidx = next(i for i, l in enumerate(lines) if l.startswith(UTILS_FUNC))
    except StopIteration:
        return []
    out = []
    for i in range(fidx + 1, len(lines)):
        l = lines[i]
        if l and not l.startswith((" ", "\t", "#")) and not l.isspace():
            break  # left the function body
        if "model_cfg.stochastic is True" in l:
            out.append(i)
    return out


def _utils_func_body(text: str) -> str:
    lines = text.split("\n")
    try:
        fidx = next(i for i, l in enumerate(lines) if l.startswith(UTILS_FUNC))
    except StopIteration:
        return ""
    body = []
    for i in range(fidx + 1, len(lines)):
        l = lines[i]
        if l and not l.startswith((" ", "\t", "#")) and not l.isspace():
            break
        body.append(l)
    return "\n".join(body)


def utils_state(text: str) -> str:
    cond = _utils_cond_lines(text)
    if not cond:
        if UTILS_FUNC in text:
            body = _utils_func_body(text)
            if "model_cfg.stochastic" in body.replace(UTILS_GUARD, ""):
                # unguarded-ish stochastic access survives in some form we do not recognise -> drift
                return FileState.UNMATCHED
            # function no longer touches model_cfg.stochastic at all -> legacy path removed upstream
            return FileState.PASS
        return FileState.UNMATCHED
    lines = text.split("\n")
    if all(UTILS_GUARD in lines[i] for i in cond):
        return FileState.PASS
    if all(
        lines[i].strip().startswith(UTILS_VARIANT_A.strip())
        or lines[i].strip() == UTILS_VARIANT_B.strip()
        for i in cond
    ):
        # unguarded but exactly one of the two verified variants (trailing comments allowed)
        return FileState.FIX
    return FileState.UNMATCHED


def utils_fix(text: str) -> str:
    cond = _utils_cond_lines(text)
    if not cond:
        raise ValueError("anchor not found: no `model_cfg.stochastic is True` condition in _update_distribution_cfg")
    lines = text.split("\n")
    changed = 0
    for i in cond:
        s = lines[i].strip()
        if UTILS_GUARD in lines[i]:
            continue
        comment = ""
        k = s.find(":")  # first colon terminates the condition; anything after it (e.g. variant A's trailing comment) is kept
        if k >= 0:
            comment = s[k + 1:]
        indent = lines[i][: len(lines[i]) - len(lines[i].lstrip())]
        if s.startswith(UTILS_VARIANT_A.strip()):
            lines[i] = f'{indent}elif {UTILS_GUARD}:{comment}'
        elif s == UTILS_VARIANT_B.strip():
            lines[i] = f'{indent}if model_cfg.distribution_cfg is None and {UTILS_GUARD}:'
        else:
            raise ValueError(f"anchor drift at utils.py line {i + 1}: {lines[i]!r}")
        changed += 1
    if not changed:
        raise ValueError("no unguarded stochastic condition to fix")
    return "\n".join(lines)


# --------------------------------------------------------------------------------------------
# Target 4: unitree_rl_lab/scripts/rsl_rl/train.py
# --------------------------------------------------------------------------------------------

TRAIN_ANCHOR = "    agent_cfg = cli_args.update_rsl_rl_cfg(agent_cfg, args_cli)"
TRAIN_ANCHOR_END = [
    "    agent_cfg.max_iterations = (",
    "        args_cli.max_iterations if args_cli.max_iterations is not None else agent_cfg.max_iterations",
    "    )",
]


def train_state(text: str) -> str:
    calls = count_handler_calls(text)
    if len(calls) == 1:
        return FileState.PASS
    if len(calls) >= 2:
        _, ok = dedupe_calls(text)
        return FileState.FIX if ok else FileState.UNMATCHED
    # zero calls: needed on rsl-rl 5.x (agent_cfg.to_dict() is expanded into MLPModel)
    lines = text.split("\n")
    try:
        idx = lines.index(TRAIN_ANCHOR)
    except ValueError:
        return FileState.UNMATCHED
    block = lines[idx + 2: idx + 5]
    return FileState.FIX if block == TRAIN_ANCHOR_END else FileState.UNMATCHED


def train_fix(text: str) -> str:
    calls = count_handler_calls(text)
    if len(calls) >= 2:
        new_text, ok = dedupe_calls(text)
        if not ok:
            raise ValueError("duplicate handle_deprecated_rsl_rl_cfg() calls are not identical - manual dedup needed")
        return new_text
    lines = text.split("\n")
    try:
        idx = lines.index(TRAIN_ANCHOR)
    except ValueError:
        raise ValueError(f"anchor not found: {TRAIN_ANCHOR!r}")
    end = idx + 5  # insert after the full agent_cfg.max_iterations = (...) block (lines idx+2..idx+4)
    if lines[idx + 2: idx + 5] != TRAIN_ANCHOR_END:
        raise ValueError("anchor drift: agent_cfg.max_iterations block not where expected")
    return "\n".join(lines[:end] + make_handler_block("agent_cfg") + lines[end:])


# --------------------------------------------------------------------------------------------
# Driver
# --------------------------------------------------------------------------------------------

TARGETS = [
    {
        "id": 1,
        "name": "cli_args.py",
        "rel": "unitree_rl_lab/scripts/rsl_rl/cli_args.py",
        "where": "parse_rsl_rl_cfg()",
        "state": cli_args_state,
        "fix": cli_args_fix,
        "manual": (
            "在 parse_rsl_rl_cfg() 中、`rslrl_cfg = update_rsl_rl_cfg(rslrl_cfg, args_cli)` 之后、"
            "`return rslrl_cfg` 之前插入(函数内局部导入,因为该模块在 Isaac app 启动前被 import):\n"
            "        import importlib.metadata\n"
            "        from isaaclab_rl.rsl_rl.utils import handle_deprecated_rsl_rl_cfg\n"
            "        rslrl_cfg = handle_deprecated_rsl_rl_cfg(rslrl_cfg, importlib.metadata.version(\"rsl-rl-lib\"))"
        ),
    },
    {
        "id": 2,
        "name": "play.py",
        "rel": "unitree_rl_lab/scripts/rsl_rl/play.py",
        "where": "main() 导出区段",
        "state": play_state,
        "fix": play_fix,
        "manual": (
            "删除 `# extract the neural network module` 起、至 `export_policy_as_onnx(policy_nn, ...)` 止的整段"
            "(rsl-rl 5.x 已把 PPO.policy 改名 PPO.actor 并删除 actor_critic,该段必然 AttributeError),"
            "改为使用 rsl-rl 5.0.1 内置导出器(方法实名 export_policy_to_onnx,不是 AGENTS.md 写的 export_policy_onnx):\n"
            '        export_model_dir = os.path.join(os.path.dirname(resume_path), "exported")\n'
            '        runner.export_policy_to_jit(path=export_model_dir, filename="policy.pt")\n'
            '        runner.export_policy_to_onnx(path=export_model_dir, filename="policy.onnx")\n'
            "并把顶部 `from isaaclab_rl.rsl_rl import ... export_policy_as_jit, export_policy_as_onnx` 中的两个导出函数移除。"
        ),
    },
    {
        "id": 3,
        "name": "utils.py",
        "rel": "IsaacLab/source/isaaclab_rl/isaaclab_rl/rsl_rl/utils.py",
        "where": "_update_distribution_cfg()",
        "state": utils_state,
        "fix": utils_fix,
        "manual": (
            "在 _update_distribution_cfg() 中给 model_cfg.stochastic 加 hasattr 守卫:\n"
            "        elif model_cfg.stochastic is True:  ->  elif hasattr(model_cfg, \"stochastic\") and model_cfg.stochastic is True:\n"
            "或(develop 新写法):\n"
            "        if model_cfg.distribution_cfg is None and model_cfg.stochastic is True:\n"
            "     -> if model_cfg.distribution_cfg is None and hasattr(model_cfg, \"stochastic\") and model_cfg.stochastic is True:\n"
            "(函数末尾会 delattr 掉 stochastic,第二次调用本函数时裸访问会 AttributeError)"
        ),
    },
    {
        "id": 4,
        "name": "train.py",
        "rel": "unitree_rl_lab/scripts/rsl_rl/train.py",
        "where": "main()",
        "state": train_state,
        "fix": train_fix,
        "manual": (
            "确保 main() 中恰好有一次 handle_deprecated_rsl_rl_cfg() 调用(记述里的\"两处重复删一处\";全新 clone 是 0 次,"
            "同样需要修,因为 agent_cfg.to_dict() 同样会把 stochastic 展开进 MLPModel.__init__):\n"
            "        import importlib.metadata\n"
            "        from isaaclab_rl.rsl_rl.utils import handle_deprecated_rsl_rl_cfg\n"
            "        agent_cfg = handle_deprecated_rsl_rl_cfg(agent_cfg, importlib.metadata.version(\"rsl-rl-lib\"))\n"
            "插入位置:`agent_cfg = cli_args.update_rsl_rl_cfg(agent_cfg, args_cli)` 与其后的 max_iterations 块之后。"
        ),
    },
]


def process(target, sim_root: Path, check_only: bool) -> str:
    path = sim_root / target["rel"]
    label = f"[{target['id']}/4] {target['name']} ({target['rel']})"
    if not path.is_file():
        print(f"{label}: MISSING — 文件不存在，检查 --sim-root 是否指向含 unitree_rl_lab/ 与 IsaacLab/ 的 sim 目录")
        return FileState.MISSING
    text, nl = read_file(path)
    try:
        state = target["state"](text)
    except Exception as e:  # state detection itself broke -> treat as drift
        state = FileState.UNMATCHED
        print(f"{label}: state detection error: {e}")

    if state == FileState.PASS:
        print(f"{label}: {'PASS' if check_only else 'SKIP'} — 已处于修好的状态")
        return FileState.PASS if check_only else "SKIP"

    if state == FileState.FIX and not check_only:
        try:
            new_text = target["fix"](text)
        except Exception as e:
            print(f"{label}: UNMATCHED — 锚点部分失效: {e}")
            print_drift(target, text)
            return FileState.UNMATCHED
        try:
            ast.parse(new_text)
        except SyntaxError as e:
            print(f"{label}: ERROR — 修改后语法检查失败，已回滚不写盘: {e}")
            return "ERROR"
        write_file(path, new_text, nl)
        print(f"{label}: FIX — 已修改 {target['where']} 并通过 ast.parse 语法检查")
        return FileState.FIX

    if check_only and state == FileState.FIX:
        print(f"{label}: FIX — 锚点匹配，可以修（--check 模式未改动）")
        return FileState.FIX

    print(f"{label}: UNMATCHED — 需要修但锚点匹配不上")
    print(f"    文件: {path}")
    print(f"    函数: {target['where']}")
    print(f"    需要改成: {target['manual']}")
    print_drift(target, text)
    return FileState.UNMATCHED


def print_drift(target, text: str) -> None:
    print(f"    !! {DRIFT_MESSAGE}")
    ref = REF[target["name"]]
    print(f"    参考上游来源: {ref['source']}")
    for line in ref["snippet"].split("\n"):
        print(f"    | {line}")
    lines = text.split("\n")
    kw = {1: "update_rsl_rl_cfg", 2: "export_policy", 3: "stochastic is True", 4: "update_rsl_rl_cfg"}[target["id"]]
    hits = [i for i, l in enumerate(lines) if kw in l][:3]
    if hits:
        print("    --- 当前文件中相关片段（带行号） ---")
        for i in hits:
            for j in range(max(0, i - 2), min(len(lines), i + 4)):
                print(f"    {j + 1:>5}: {lines[j]}")
            print("    ...")
    else:
        print("    (当前文件中连关键字都搜不到，改动面较大，必须人工核对)")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Idempotent rsl-rl 5.0.1 compatibility patcher (see module docstring)")
    ap.add_argument("--sim-root", default="~/projects/g1-rl/sim",
                    help="sim 根目录，内含 unitree_rl_lab/ 与 IsaacLab/（默认 ~/projects/g1-rl/sim）")
    ap.add_argument("--check", action="store_true", help="只检查不改动；四个目标全 PASS 时 exit 0，否则 exit 1")
    args = ap.parse_args(argv)

    sim_root = Path(args.sim_root).expanduser().resolve()
    if not sim_root.is_dir():
        print(f"sim root 不存在: {sim_root}")
        return 1
    print(f"sim root: {sim_root}  mode: {'check' if args.check else 'apply'}")

    # 版本前提自检：本补丁集要打进去的调用依赖 isaaclab_rl.rsl_rl.utils.handle_deprecated_rsl_rl_cfg()。
    # 这个函数只在较新的 IsaacLab 里存在（v2.3.x 连 rsl_rl/utils.py 都没有）。先探一下，
    # 免得四处补丁都"成功"了、真跑训练时才炸出一个新手看不懂的 ImportError。
    il_utils = sim_root / "IsaacLab" / "source" / "isaaclab_rl" / "isaaclab_rl" / "rsl_rl" / "utils.py"
    if il_utils.is_file():
        probe = il_utils.read_text(encoding="utf-8", errors="replace")
        if "def handle_deprecated_rsl_rl_cfg" not in probe:
            print(f"!! {il_utils}")
            print("   这个 IsaacLab 版本里没有 handle_deprecated_rsl_rl_cfg()，本补丁集依赖它（v2.3.x 没有这个函数）。")
            print("   先按 1.5 用默认分支克隆 IsaacLab，或换成含该函数的版本，再回来跑本脚本。")
            return 1

    results = [process(t, sim_root, args.check) for t in TARGETS]
    print(f"\n汇总: " + ", ".join(f"{t['name']}={r}" for t, r in zip(TARGETS, results)))
    if args.check:
        all_pass = all(r == FileState.PASS for r in results)
        print("check 结果: " + ("全部 PASS (exit 0)" if all_pass else "存在未通过项 (exit 1)"))
        return 0 if all_pass else 1
    all_ok = all(r in (FileState.PASS, FileState.FIX, "SKIP") for r in results)
    print("apply 结果: " + ("完成 (exit 0)" if all_ok else "存在 UNMATCHED/MISSING/ERROR，需人工处理 (exit 1)"))
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
