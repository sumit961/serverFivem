# CM repository validator

Run from the repository root:

```powershell
python tools/cm-validate/validate.py
```

The command is read-only. It checks active resources, manifest file references, hard dependencies and cycles, `server.cfg` ordering/duplicates, duplicate ACE/principal statements, expected documentation, and registry freshness. Missing assets documented in `PRIVATE_ASSETS.md` are warnings so secret-free CI can run without paid/private files.

Exit code is non-zero when an actionable static error is found. Warnings identify conditions that require review but do not fail validation.
