# Feature: services need typed lifecycle and identity policy

## Limitation on Kai master (`a7373bd`)

A standard generated service is always a long-running, dynamically allocated user service with one executable, `Restart=on-failure`, and fixed hardening. Kaifile cannot describe a one-shot boot action, a declared machine user, ordering dependencies, readiness, or an idempotent path condition.

## Needed capability

Extend the backend-neutral service model with validated lifecycle concepts:

- long-running or one-shot execution;
- declared user/group or dynamic identity;
- startup ordering and required capabilities;
- restart and completion behavior;
- idempotency/readiness conditions;
- explicit, reviewable hardening presets.

Backends should lower only supported concepts and fail during planning for unsupported combinations. Avoid exposing arbitrary systemd text or shell commands as the portability escape hatch.

## Aion impact

The image must install one SSH key from cloud metadata before SSH login is accepted. Aion currently generates that one-shot unit in its plugin.
