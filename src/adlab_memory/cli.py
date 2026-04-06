from __future__ import annotations

import argparse
import json
from dataclasses import asdict, is_dataclass
from pathlib import Path

from adlab_memory.config import load_pipeline_config
from adlab_memory.ingest.registry import ingest_exports
from adlab_memory.mcp.server import MCPMemoryServer
from adlab_memory.orchestration.mission import MissionResult, MissionRunner, mission_audit
from adlab_memory.security.encryption import decrypt_file, encrypt_file
from adlab_memory.security.keys import ensure_key


def _cmd_ingest(args: argparse.Namespace) -> int:
    cfg = load_pipeline_config(Path(args.config))
    events, manifest = ingest_exports(
        input_root=cfg.paths.input_root,
        normalized_root=cfg.paths.normalized_root,
        providers=cfg.ingest.providers,
        include_globs=cfg.ingest.include_globs,
    )
    print(f"ingested_messages={len(events)}")
    print(f"manifest={cfg.paths.normalized_root / 'manifest.json'}")
    return 0


def _cmd_compile(args: argparse.Namespace) -> int:
    cfg = load_pipeline_config(Path(args.config))
    runner = MissionRunner(cfg)
    result = runner.start()
    print(json.dumps(_jsonable_result(result), indent=2))
    return 0


def _cmd_mission_start(args: argparse.Namespace) -> int:
    cfg = load_pipeline_config(Path(args.config))
    runner = MissionRunner(cfg)
    result = runner.start()
    print(json.dumps(_jsonable_result(result), indent=2))
    return 0


def _cmd_mission_resume(args: argparse.Namespace) -> int:
    cfg = load_pipeline_config(Path(args.config))
    runner = MissionRunner(cfg)
    result = runner.resume()
    print(json.dumps(_jsonable_result(result), indent=2))
    return 0


def _cmd_mission_status(args: argparse.Namespace) -> int:
    cfg = load_pipeline_config(Path(args.config))
    runner = MissionRunner(cfg)
    state = runner.status()
    print(json.dumps(_jsonable_result(state), indent=2))
    return 0


def _cmd_mission_audit(args: argparse.Namespace) -> int:
    state_path = Path(args.state) if args.state else load_pipeline_config(Path(args.config)).paths.state_root / "mission_state.json"
    print(mission_audit(state_path))
    return 0


def _cmd_mcp_tools(args: argparse.Namespace) -> int:
    cfg = load_pipeline_config(Path(args.config))
    server = MCPMemoryServer(cfg.paths.wiki_root)
    if args.json:
        print(server.to_json())
    else:
        print("\n".join(tool["name"] for tool in server.describe_tools()))
    return 0


def _cmd_encrypt(args: argparse.Namespace) -> int:
    key = ensure_key(Path(args.key_file))
    output_path = encrypt_file(Path(args.input_path), key)
    print(f"encrypted={output_path}")
    return 0


def _cmd_decrypt(args: argparse.Namespace) -> int:
    key = ensure_key(Path(args.key_file))
    output_path = decrypt_file(Path(args.input_path), key)
    print(f"decrypted={output_path}")
    return 0


def _cmd_keys_bootstrap(args: argparse.Namespace) -> int:
    key = ensure_key(Path(args.output))
    print(f"key_path={Path(args.output)}")
    print(f"key_bytes={len(key)}")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="adlab-memory",
        description="MiniMax M2.7 REAP optimized local memory/wiki pipeline",
    )
    parser.add_argument(
        "--config",
        default="configs/pipeline.default.yaml",
        help="Path to pipeline config file",
    )

    sub = parser.add_subparsers(dest="command", required=True)

    ingest = sub.add_parser("ingest", help="Ingest provider exports")
    ingest.add_argument("--input-dir", required=True, help="Directory with provider exports")
    ingest.set_defaults(func=_cmd_ingest)

    compile_cmd = sub.add_parser("compile", help="Compile one batch into wiki")
    compile_cmd.set_defaults(func=_cmd_compile)

    mission = sub.add_parser("mission", help="Mission orchestrator")
    mission_sub = mission.add_subparsers(dest="mission_cmd", required=True)
    m_start = mission_sub.add_parser("start", help="Start mission")
    m_start.set_defaults(func=_cmd_mission_start)
    m_resume = mission_sub.add_parser("resume", help="Resume mission")
    m_resume.set_defaults(func=_cmd_mission_resume)
    m_status = mission_sub.add_parser("status", help="Show mission status")
    m_status.set_defaults(func=_cmd_mission_status)
    m_audit = mission_sub.add_parser("audit", help="Show mission audit")
    m_audit.add_argument("--state", default="", help="Optional explicit mission state file path")
    m_audit.set_defaults(func=_cmd_mission_audit)

    mcp_tools = sub.add_parser("mcp-tools", help="List MCP tool names")
    mcp_tools.add_argument("--json", action="store_true", help="Print full tool JSON schema")
    mcp_tools.set_defaults(func=_cmd_mcp_tools)

    encrypt = sub.add_parser("encrypt", help="Encrypt a file")
    encrypt.add_argument("--input-path", required=True)
    encrypt.add_argument("--key-file", required=True)
    encrypt.set_defaults(func=_cmd_encrypt)

    decrypt = sub.add_parser("decrypt", help="Decrypt a file")
    decrypt.add_argument("--input-path", required=True)
    decrypt.add_argument("--key-file", required=True)
    decrypt.set_defaults(func=_cmd_decrypt)

    keys = sub.add_parser("keys", help="Key management")
    keys_sub = keys.add_subparsers(dest="keys_cmd", required=True)
    keys_bootstrap = keys_sub.add_parser("bootstrap", help="Create key if absent")
    keys_bootstrap.add_argument("--output", required=True, help="Destination key file path")
    keys_bootstrap.set_defaults(func=_cmd_keys_bootstrap)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())


def _jsonable_result(value: object) -> object:
    if value is None:
        return None
    if isinstance(value, Path):
        return str(value)
    if is_dataclass(value):
        dumped = asdict(value)
        return _jsonable_result(dumped)
    if isinstance(value, dict):
        return {str(k): _jsonable_result(v) for k, v in value.items()}
    if isinstance(value, list):
        return [_jsonable_result(item) for item in value]
    return value
