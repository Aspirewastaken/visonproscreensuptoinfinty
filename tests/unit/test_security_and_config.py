from __future__ import annotations

from pathlib import Path

from adlab_memory.config import load_pipeline_config
from adlab_memory.security.encryption import decrypt_file, encrypt_file
from adlab_memory.security.keys import ensure_key


def test_config_paths_resolve_relative_to_config_location() -> None:
    config = load_pipeline_config(Path("configs/pipeline.default.yaml"))
    assert config.paths.input_root.is_absolute()
    assert config.paths.wiki_root.is_absolute()
    assert config.model.profile.is_absolute()


def test_encrypt_decrypt_roundtrip(tmp_path: Path) -> None:
    key_path = tmp_path / "key.bin"
    key = ensure_key(key_path)

    source = tmp_path / "sample.txt"
    source.write_text("hello secure world", encoding="utf-8")
    encrypted_path = encrypt_file(source, key)
    assert encrypted_path.exists()

    decrypted_path = decrypt_file(encrypted_path, key)
    assert decrypted_path.exists()
    assert decrypted_path.read_text(encoding="utf-8") == "hello secure world"

