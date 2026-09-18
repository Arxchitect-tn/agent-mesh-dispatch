# agent-mesh-dispatch

A small routing layer for a multi-agent mesh: one entry point that maps a **role name** to a
concrete agent CLI, plus a three-stage review pipeline.

## Components

- `dispatch.sh` — the entry point. Routes `agent <role> <task>` to the right container/CLI, and
  runs `review <task>` as a pipeline: **write → review → final review**, with the model used at
  each stage configurable in `review.conf`.
- `n8n-forced-command.sh` — an SSH forced-command wrapper that lets an automation container
  (n8n) trigger a strict allow-list of actions over a restricted key. The automation side holds
  no Docker socket and no host mounts; the whitelist is root-owned and lives on the target.
- `review.conf` — stage-by-stage model selection, so the pipeline can be retargeted without
  editing the script.

## Design notes

Worth stealing if you're building something similar:

- **One agent, one name.** An alias that points at the same agent under two names is a bug
  waiting to happen — you end up debugging the wrong role. The role map is the single source
  of truth.
- **API keys over interactive OAuth** for anything unattended. OAuth tokens expire and silently
  break scheduled runs; a key fails loudly and predictably.
- **Sandbox bypass is only acceptable when the container is the sandbox** — no Docker socket,
  no host mounts, its own home directory. The flags belong to that context and nowhere else.
- **Whitelist anchoring is fiddly.** An SSH node that prefixes `cd / ;` to every command will be
  denied by a naive allow-list — and the caller may still report success, because success only
  means the command ran. Match the real invocation, not the one you assumed.
- **Logic lives in versioned scripts, not in the scheduler.** The automation layer stays
  model-free and auditable; scheduling is just a trigger.

## Layout

    dispatch.sh              role routing + review pipeline
    n8n-forced-command.sh    restricted-key allow-list wrapper
    review.conf              per-stage model configuration
