# Security

## At-rest encryption

Wiki and artifacts can be encrypted with a local symmetric key:

```bash
adlab-memory keys bootstrap --output .adlab/keys/fernet.key
adlab-memory secure encrypt --key .adlab/keys/fernet.key --path data/wiki
adlab-memory secure decrypt --key .adlab/keys/fernet.key --path data/wiki
```

## Threat model (initial)

- Protect local artifacts from accidental exfiltration.
- Ensure keys are not committed to source control.
- Keep all processing local by default.

## Key lifecycle

- Bootstrap once per environment.
- Rotate by generating a new key and re-encrypting target directories.
- Store keys outside shared repositories and synced plaintext folders.
