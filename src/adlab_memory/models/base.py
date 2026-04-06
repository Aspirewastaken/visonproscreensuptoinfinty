from __future__ import annotations

from abc import ABC, abstractmethod
from pydantic import BaseModel


class ModelProfile(BaseModel):
    name: str
    backend: str
    model_id: str
    endpoint: str | None = None
    context_window: int = 128_000
    max_output_tokens: int = 1024
    temperature: float = 0.0
    adaptive_chunk: dict[str, float | int | bool] = {}
    fallback_chain: list[str] = []


class ModelBackend(ABC):
    @abstractmethod
    def generate(self, prompt: str, *, profile: ModelProfile) -> str:
        raise NotImplementedError
