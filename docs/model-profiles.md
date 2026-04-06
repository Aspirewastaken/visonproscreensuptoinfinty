# Model Profiles

Profiles are YAML files loaded by `adlab_memory.models.profile_resolver`.

## `configs/models/minimax_m2_7_reap.yaml`

Primary profile intended for local REAP-optimized runtime.

Includes:

- model id
- backend type (`mock`, `openai_compatible`)
- context window
- max output tokens
- fallback chain
- adaptive chunk behavior

## `configs/models/fallback_qwen_reap.yaml`

Fallback profile for degraded mode and testing.

## Notes

The runner is backend-agnostic. Real deployment can point to:

- local HTTP OpenAI-compatible endpoint,
- custom local model service,
- or mock backend for deterministic tests.
