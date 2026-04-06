from __future__ import annotations

import json
from dataclasses import dataclass, field
from urllib import request

from adlab_memory.models.base import ModelBackend, ModelProfile


class MockBackend(ModelBackend):
    def generate(self, prompt: str, *, profile: ModelProfile) -> str:
        lines = [line.strip() for line in prompt.splitlines() if line.strip()]
        excerpt = " ".join(lines[-6:])[:400]
        return f"[{profile.model_id}] {excerpt}"


class OpenAICompatibleBackend(ModelBackend):
    def generate(self, prompt: str, *, profile: ModelProfile) -> str:
        if not profile.endpoint:
            raise ValueError("endpoint is required for openai_compatible backend")
        body = {
            "model": profile.model_id,
            "messages": [{"role": "user", "content": prompt}],
            "temperature": profile.temperature,
            "max_tokens": profile.max_output_tokens,
        }
        req = request.Request(
            profile.endpoint,
            data=json.dumps(body).encode("utf-8"),
            headers={"Content-Type": "application/json"},
            method="POST",
        )
        with request.urlopen(req, timeout=30) as response:
            payload = json.loads(response.read().decode("utf-8"))
        choices = payload.get("choices", [])
        if not choices:
            return ""
        message = choices[0].get("message", {})
        return str(message.get("content", ""))


@dataclass(slots=True)
class LocalModelRunner:
    profile: ModelProfile
    backend: ModelBackend = field(init=False)

    def __post_init__(self) -> None:
        if self.profile.backend == "openai_compatible":
            self.backend: ModelBackend = OpenAICompatibleBackend()
        else:
            self.backend = MockBackend()

    def generate(self, prompt: str) -> str:
        return self.backend.generate(prompt, profile=self.profile)
