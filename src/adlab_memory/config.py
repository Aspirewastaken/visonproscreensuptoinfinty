from __future__ import annotations

from pathlib import Path
from typing import Literal

import yaml
from pydantic import BaseModel, Field


class PathsConfig(BaseModel):
    input_root: Path
    normalized_root: Path
    wiki_root: Path
    state_root: Path
    checkpoints_root: Path


class IngestConfig(BaseModel):
    providers: list[str] = Field(default_factory=list)
    include_globs: list[str] = Field(default_factory=lambda: ["*.json"])


class CompileConfig(BaseModel):
    chunk_target_tokens: int = 1200
    chunk_overlap_tokens: int = 120
    max_batch_size: int = 20
    prioritize: Literal["newest_first", "oldest_first"] = "newest_first"


class ModelRef(BaseModel):
    profile: Path


class MissionConfig(BaseModel):
    retries: int = 2
    quarantine_failed_batches: bool = True
    save_every_batches: int = 5


class PipelineConfig(BaseModel):
    paths: PathsConfig
    ingest: IngestConfig
    compile: CompileConfig
    model: ModelRef
    mission: MissionConfig

    @classmethod
    def from_yaml(cls, path: Path) -> "PipelineConfig":
        payload = yaml.safe_load(path.read_text())
        config = cls.model_validate(payload)
        return resolve_relative_paths(config, base_dir=path.parent)


def resolve_relative_paths(config: PipelineConfig, *, base_dir: Path) -> PipelineConfig:
    paths = config.paths
    for name in ("input_root", "normalized_root", "wiki_root", "state_root", "checkpoints_root"):
        value = getattr(paths, name)
        if not value.is_absolute():
            setattr(paths, name, (base_dir / value).resolve())

    if not config.model.profile.is_absolute():
        config.model.profile = (base_dir / config.model.profile).resolve()
    return config


def load_pipeline_config(path: Path) -> PipelineConfig:
    return PipelineConfig.from_yaml(path)
