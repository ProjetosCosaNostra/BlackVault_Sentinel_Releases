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
