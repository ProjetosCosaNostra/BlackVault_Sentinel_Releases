# BlackGold Global Control Plane

This repository participates in the BlackGold ecosystem.

Read first:
- `.blackgold/control-plane.json`
- `https://github.com/ProjetosCosaNostra/CosaNostra-AI/blob/main/control-plane/AGENT_ENTRYPOINT.md`
- `https://github.com/ProjetosCosaNostra/CosaNostra-AI/blob/main/control-plane/CURRENT_TRUTH.json`

Global execution invariants:
- Never open visible CMD windows for project automation.
- Prefer hidden/background execution.
- Preserve required Gradle/build/script subprocesses.
- Consult the canonical Control Plane before changing automation behavior.
- Do not reimplement global ecosystem configuration locally.

Remote Windows execution:
- Desktop Commander is optional and must never block project progress.
- If local Windows execution is required, use the BlackGold GitHub Runner transport.
- Discover the private control repository by reading `BLACKGOLD_RUNNER_CONTROL.json`.
- Queue only controlled jobs supported by the canonical runner schema.
- Use GitHub for code changes; use the runner for sync, Gradle, ADB, emulator, tests and logs.
