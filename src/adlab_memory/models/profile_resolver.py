from __future__ import annotations

from pathlib import Path

import yaml

from adlab_memory.models.base import ModelProfile


def load_model_profile(path: Path) -> ModelProfile:
    payload = yaml.safe_load(path.read_text())
    return ModelProfile.model_validate(payload)
