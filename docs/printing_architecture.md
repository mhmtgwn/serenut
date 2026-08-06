# Serenut OS Printing Architecture

Status: implementation contract

## Problem statement

Printing currently combines design preferences, physical device configuration,
routing and retry state across `Settings`, a SharedPreferences hardware repository
and the SQLite print queue. This makes a successful TCP write look like a
successful print, lets legacy defaults silently choose a printer, and allows a
receipt setting to influence label output.

The target architecture makes every print deterministic and traceable:

`request -> immutable job -> route -> render -> transport -> observed result`

## Non-negotiable invariants

1. A design profile contains content and layout choices only. It never contains
   an IP address, Windows queue name, connection type or active-device state.
2. A printer device contains physical capabilities and transport configuration
   only. It never contains receipt or label content switches.
3. A route explicitly maps one job kind to one enabled printer device. There is
   no receipt-printer fallback for label jobs and no "last saved device" rule.
4. A queued job is immutable. It records the selected design profile, target
   device, renderer version and payload snapshot at creation time.
5. Rendering is pure and deterministic. The same job snapshot and renderer
   version produce identical bytes.
6. Transport reports delivery separately from physical confirmation. A completed
   socket/spool write is `delivered`, not proof that paper was printed.
7. Jobs left in `rendering` or `sending` at process death are recovered on the
   next startup according to an explicit idempotency policy.
8. Millimetres are the source unit for label media. Receipt paper width and label
   media width are separate capabilities even when both devices are called 58 mm.
9. Legacy data is migrated once, transactionally, with an audit record. Runtime
   code does not keep reading two sources indefinitely.
10. UI success is tied to the job state. Enqueueing alone is never presented as
    printing success.

## Domain model

### Design profiles

- `ReceiptDesignProfile`: paper content, logo policy, typography, sections and
  receipt-paper layout.
- `ProductLabelDesignProfile`: media-independent content choices and element
  layout for one product label.
- `OrderLabelDesignProfile`: order grouping, orientation and element layout.

Each profile has `id`, `name`, `schemaVersion`, `rendererVersion`, timestamps and
an `isDefault` flag. Exactly one default profile exists per job kind.

### Printer devices

`PrinterDeviceProfile` owns:

- stable device id and display name;
- printer language (`escPos`, `tspl`);
- transport (`tcp`, `windowsSpooler`, `usb`, `bluetooth`, `embedded`);
- transport configuration;
- physical capabilities: DPI, printable width, media width/height, gap, cutter,
  cash drawer and raster support;
- enabled state and last test observation.

### Routes

`PrinterRoute` maps `receipt`, `productLabel` or `orderLabel` to a device id and
optionally a design profile id. Route validation rejects incompatible printer
languages and disabled/missing devices.

### Jobs

`PrintJob` contains:

- id, kind, payload snapshot and copy count;
- design profile id plus serialized design snapshot;
- device id plus required capability snapshot;
- renderer version;
- state, attempt count, timestamps, next-attempt time and structured error;
- rendered byte checksum and delivery observation.

The state machine is:

`created -> queued -> rendering -> sending -> delivered`

Failure edges enter `retryWait` or terminal `failed`. User cancellation enters
terminal `cancelled`. Physical test jobs may additionally enter `awaitingUserCheck`
before `confirmed` or `rejected`.

## Persistence ownership

SQLite is the single local source of truth:

- `print_design_profiles`
- `printer_devices`
- `printer_routes`
- `print_jobs`
- `print_job_attempts`

SharedPreferences may only hold ephemeral UI state. Cloud sync serializes these
domain records; it does not recreate active routes by iteration order.

## Processing contract

1. Validate request and resolve an explicit route.
2. Snapshot the route, device capabilities, design and business payload in one
   SQLite transaction.
3. Claim one queued job atomically.
4. Render with the renderer selected by job kind and device language.
5. Persist checksum, then send through the selected transport.
6. Persist the transport observation and surface it to the UI.
7. Retry only retryable failures with bounded exponential backoff.

There is one worker per physical device so two jobs cannot interleave bytes on
the same printer. Different devices may process concurrently.

## Test contract

Automated acceptance requires:

- migration tests from every supported legacy schema;
- renderer golden/byte-boundary tests at 58 mm receipt width and configured
  label dimensions;
- route compatibility and no-fallback tests;
- atomic claim, crash recovery, retry timing and cancellation tests;
- transport contract tests and UI state tests.

Physical acceptance requires a device-card test for every configured printer:
connection test, calibration pattern, logo/raster test, Turkish text, barcode
scan, right-edge ruler and user confirmation. TCP connection alone is insufficient.

## Migration and retirement sequence

1. Introduce new tables and repositories without changing call sites.
2. Transactionally migrate legacy settings/devices/routes/jobs and record the
   migration version.
3. Add renderers, transports and the queue coordinator behind the new API.
4. Move hardware cards and design screens to the new repositories.
5. Move all print call sites to immutable job creation.
6. Enable startup recovery and user-visible job observations.
7. Remove legacy settings fields, fallback routing and direct send paths only
   after migration and parity tests pass.

## Release gate

No release is allowed until automated acceptance is green, legacy migration is
verified against a copy of production-shaped data, and the three physical output
types are accepted on their intended devices. Rollback preserves the old schema
and never downgrades or discards queued jobs.
