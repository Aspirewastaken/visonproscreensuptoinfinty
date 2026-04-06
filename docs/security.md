# Security

## At-rest encryption

Wiki and artifacts can be encrypted with a local symmetric key:

```bash
adlab-memory keys bootstrap --output .adlab/keys/local.key
adlab-memory encrypt --key-file .adlab/keys/local.key --input-path data/wiki/example.md
adlab-memory decrypt --key-file .adlab/keys/local.key --input-path data/wiki/example.md.enc
```

## Threat model (initial)

- Protect local artifacts from accidental exfiltration.
- Ensure keys are not committed to source control.
- Keep all processing local by default.

## Key lifecycle

- Bootstrap once per environment.
- Rotate by generating a new key and re-encrypting target directories.
- Store keys outside shared repositories and synced plaintext folders.
