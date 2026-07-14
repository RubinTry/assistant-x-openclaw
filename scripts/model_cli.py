#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
模型表 CLI —— Control Center 用它读写 model_table.json，**不依赖助手是否启动**。

模型配置本就是"生成 model_table.json"的独立步骤，助手启动时再读它。因此这里
走子进程（Control Center 用 venv Python 调本脚本），加解密仍在 Python 一侧完成，
与助手主程序解耦：助手没跑也能配。

用法（结果统一 JSON 打到 stdout；成功 exit 0，出错 exit 1 并打 {"error": ...}）：
  model_cli.py list
  model_cli.py validate   < payload.json     # {id} 或 {base_url,model,api_key}
  model_cli.py upsert      < payload.json     # 完整条目（含明文 api_key）
  model_cli.py delete      < payload.json     # {id}
  model_cli.py current     < payload.json     # {id}
  model_cli.py agent-current < payload.json   # {id}

含密文/明文 key 的入参一律走 stdin，避免出现在进程 argv（ps 可见）里。
"""

import json
import os
import sys

# 让本脚本能 import src/ 下的 model_store / model_probe
_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(_ROOT, "src"))

import model_store  # noqa: E402


def _read_stdin_json() -> dict:
    raw = sys.stdin.read()
    if not raw or not raw.strip():
        return {}
    return json.loads(raw)


def _emit(obj) -> None:
    sys.stdout.write(json.dumps(obj, ensure_ascii=False))
    sys.stdout.flush()


def _fail(msg: str, code: int = 1) -> None:
    _emit({"error": str(msg)})
    sys.exit(code)


def main(argv) -> None:
    if not argv:
        _fail("usage: model_cli.py <list|validate|upsert|delete|current>")
    cmd = argv[0]

    try:
        if cmd == "list":
            _emit(model_store.list_models())

        elif cmd == "upsert":
            entry = model_store.upsert_model(_read_stdin_json())
            _emit({"entry": entry})

        elif cmd == "delete":
            body = _read_stdin_json()
            _emit(model_store.delete_model((body.get("id") or "").strip()))

        elif cmd == "current":
            body = _read_stdin_json()
            _emit(model_store.set_current((body.get("id") or "").strip()))

        elif cmd == "agent-current":
            body = _read_stdin_json()
            _emit(model_store.set_agent_current((body.get("id") or "").strip()))

        elif cmd == "validate":
            import model_probe
            body = _read_stdin_json()
            entry_id = (body.get("id") or "").strip()
            if entry_id:
                dec = model_store.get_decrypted(entry_id)
                if dec is None:
                    _fail(f"模型 {entry_id} 不存在或解密失败")
                base_url, model, api_key = dec["base_url"], dec["model"], dec["api_key"]
                provider = dec.get("provider") or ""
            else:
                base_url = (body.get("base_url") or "").strip()
                model = (body.get("model") or "").strip()
                provider = (body.get("provider") or "").strip()
                api_key = body.get("api_key") or ""
                api_key_source_id = (body.get("api_key_source_id") or "").strip()
                if not api_key and api_key_source_id:
                    source = model_store.get_decrypted(api_key_source_id)
                    if source is None:
                        _fail(f"模型 {api_key_source_id} 不存在或解密失败")
                    api_key = source.get("api_key") or ""
                is_codex = model_probe.is_codex_provider(provider)
                if not model or (not is_codex and (not base_url or not api_key)):
                    _fail("校验需要 base_url、model、api_key（或已存条目的 id）；openai-codex 不需要 api_key")
            _emit({"result": model_probe.probe_model(
                base_url, model, api_key, provider=provider,
            )})

        else:
            _fail(f"未知命令: {cmd}")

    except KeyError as e:
        _fail(str(e))
    except ValueError as e:
        _fail(str(e))
    except json.JSONDecodeError as e:
        _fail(f"入参 JSON 解析失败: {e}")
    except Exception as e:  # noqa: BLE001 — CLI 兜底，任何异常转成 {error}
        _fail(f"model store failed: {e}")


if __name__ == "__main__":
    main(sys.argv[1:])
