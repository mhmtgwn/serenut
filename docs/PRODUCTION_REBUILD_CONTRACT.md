# Serenut OS — Production Rebuild Contract

## Decision

Serenut will operate with one production path per responsibility. Legacy
paths are not to be made compatible with new paths; they are migrated, gated,
and removed after their replacement passes acceptance tests.

## Canonical ownership

| Responsibility | Canonical owner | Explicitly retired |
| --- | --- | --- |
| Authentication and sessions | Server `users` + `sessions` | Local credentials as a source of truth |
| Device activation and licensing | Server `device_activations` | Server `devices` as a licensing/device source |
| Device identity | Client `serenut_device_id` + server activation id | `device_uuid`, `nutopiano_device_id`, `sync_v4_device_id` |
| Device online state | Authenticated heartbeat / client-health, with a documented TTL | Inference from an unrelated 12-hour license check |
| Version and update telemetry | `device_activations` keyed version records | `devices` joins for update reporting |
| Business data | Server domain tables and local SQLite replica | Separate remote repository APIs |
| Replication | Sync V4 outbox, canonical snapshot, cursor pull | Module bootstrap and remote `/products`, `/customers`, `/sales` paths |
| Store payment authorization | Physical terminal bridge transaction state machine | Local ledger entry as evidence of card approval |
| Financial correction | Immutable reversal/adjustment entry | Deleting a financial transaction |

## Required service contracts

### Device activation

1. The client creates `serenut_device_id` once per installation.
2. Login/activation returns a server-issued `device_activation_id`.
3. Every authenticated heartbeat, update check/report, sync request, SMS
   gateway action, telemetry event, and portal row carries that activation id.
4. Platform, display name, app version, last seen, active/revoked state, and
   entitlement relation live on the same activation record.
5. `devices` is migrated into `device_activations` and then removed from all
   production reads and writes.

### Sync V4

1. A local domain mutation and its outbox record are committed together.
2. The server validates and materializes the aggregate into its business
   tables, appends exactly one change record, and updates the entity tombstone
   in one PostgreSQL transaction.
3. A fresh replica first receives a canonical tenant snapshot and its cursor,
   then only receives later cursor changes.
4. Product and customer precede order and sale; deletes run in reverse order.
5. Financial entries are append-only. Corrections are new reversal or
   adjustment entries, never `DELETE` mutations.

### Payment

1. A terminal request gets a generated payment intent/idempotency key before
   contacting the bridge.
2. A sale is committed only after the bridge returns an approved result with
   transaction id and authorization code.
3. Timeout/unknown responses enter `unreconciled`; retry uses terminal query,
   never a second blind charge.
4. A refund/void is a separate terminal and ledger state transition.
5. SaaS billing and in-store card payment remain separate bounded contexts.

## Legacy disposition

| Item | Disposition | Release gate |
| --- | --- | --- |
| `runLegacyModuleBootstrap` | Remove after recovery export is available | Fresh-device V4 bootstrap test |
| `InMemory*Repository` | Test-only package or delete | No production provider/import |
| Simulated POS/scale adapters | Test-only injection | Production provider rejects simulation |
| `catch (_) {}` on business/network state | Replace with classified error/reporting | Failures visible in sync/health UI |
| `devices` table callers | Migrate to activation read model | Device migration acceptance test |
| Mock SaaS checkout | Disabled until provider integration exists | Real sandbox webhook test |

## Non-negotiable acceptance gates

1. HTTP-authenticated push from device A, cursor pull to device B, and local
   SQLite application are tested against PostgreSQL.
2. Windows and Android clean installations receive the same snapshot, create
   and delete products, and observe the same result on the peer device.
3. Device limit, revoke, re-install, platform, online state, update version,
   and portal display are verified against one activation record.
4. Approved, declined, timeout, query-recovery, void, and refund terminal
   cases are verified with a bridge contract test.
5. No production provider can instantiate mock, in-memory, or legacy remote
   data sources.

No production release is approved until every gate passes.
