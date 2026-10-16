# Code requirements

Generic rules for QML/JavaScript plugins in this style. They describe how code is divided, named, tested and
failed, not what any one plugin does.

## 1. Division of labour (QML vs JavaScript)

- **QML defines what exists, how things are connected, and how they react to change.** UI, observable state,
  property bindings, singletons shared across widgets, service objects, and system objects (such as `Process`).
- **JavaScript decides and calculates.** Parsing, formatting, validation, policies, migrations, request building.
  Reusable logic lives in `.js` modules; short component-specific handlers may stay inside QML.
- Prefer QML. Add JavaScript only when a calculation or decision needs it, and keep the total small.
- JavaScript modules never touch UI, QML types or logging; they take plain data and return plain data.
- A JS module is `.pragma library` and holds no state. State belongs to QML objects.

## 2. Layers and folders

- Mirror the structure in `src/` and `tests/`. Each folder has one role:
  - `QML/Contracts`: data holders.
  - `QML/Services`: stateful objects shared across the plugin.
  - `QML/Helpers`: per-widget helper items.
  - `QML/Views`: UI only.
  - `JS/Contracts`: value domains (enums with `isValid`/`label`) and the exception type.
  - `JS/Helpers`: pure logic modules.
  - `JS/<Integration>/<Name>/`: everything specific to one external integration (see section 6).
- Dependencies point one way: Views → Helpers/Services → Contracts. A lower layer never imports a higher one.
- One type per file; the file name equals the type name. Every QML folder has a `qmldir` listing exactly its files.

## 3. Contracts (shared data structures)

- A contract is a QML type with typed properties. It is a **data holder**.
- Allowed in a contract: defaults, and a validity flag **per single field**. Not allowed: parsing, loops,
  cross-field checks, policy, conversion, I/O.
- Cross-field validation, parsing, clamping and conversion go to separate JS modules or services.
- One contract per file. When a new shared structure appears, add its contract, a test, and an audit entry.
- Where building thousands of objects would cost more than it gives (raw bulk data), keep plain data and wrap
  only what is stored or shown. Bulk data is bounded by what is needed (section 8).
- Enumerations of "what exists" are one enum (for example a `ProviderType`); nothing else enumerates it.

## 4. Services

- A service is **stateful**: it owns state (queues, caches, configuration, lists of loaded things).
  Stateless helpers are not services; they are JS modules.
- Shared state is a `pragma Singleton` registered in `qmldir` as `singleton`. Per-resource state (one queue per
  external provider) is an instance created and handed out by a singleton manager.
- A manager only manages: it enumerates what is supported, initialises it, and hands out the facade. It does no
  work itself.
- A facade is the **only** door to its resource. The rest of the code never reaches around it to the underlying
  JS/API. Enforce this with an audit test.
- A broken component is recorded and reported (a load error list); it never prevents the others from working.

## 5. Data formats and migration

- Only the current data format flows through the code. Handling of older saved formats lives in **one** module in the
  storage layer and runs before anything else sees the data.
- Persisted data is never silently discarded: damaged data is reported and backed up before anything can overwrite it.
- Every write reports whether it really happened; a failed write is shown to the user and never looks like success.
- Only one object touches storage; everything else goes through it.
- Persisted identifiers are stable internal handles (UUIDs), never display text.

## 6. Integrations (external providers/APIs)

- Each integration is a folder with **declared properties as plain data** (names, URLs, rules, limits) and an **API
  module** (build requests, read answers) plus its constants.
- The properties are checked as a whole when the integration is loaded; unknown keys and inconsistent declarations
  are errors.
- Integrations are stateless and see only current-format data. They know nothing about storage, UI, retries or
  other integrations.
- Limits (ranges, resolutions, polling rates) are declared by the integration and verified against the real service.
  Requests outside the declared limits are refused before any request is made; nothing is silently approximated.
- Retries, queues, timeouts and response interpretation are centralised once, in the facade, not per integration.
- Add a new integration by adding a folder, one enum value and one registry entry. No other file changes.

## 7. Error handling

- JavaScript throws one typed error (`PluginError`) with a friendly `userMessage`, developer `details`, and a
  `retryable` flag. Never throw a bare `Error` or a string.
- Only QML layers catch and report, through one error service. Users only ever see `userMessage`; raw exception
  text goes to the log.
- Nothing swallows an exception. A `catch` rethrows, reports, wraps, or is a documented exception.
- Logging goes through one logging service (a singleton) that alone knows dev mode: callers just call
  `debug(scope, text)` / `error(scope, text)` and never check dev mode or use `console.*`. Log decisions and outcomes (queued, started, retried, finished with counts, saved, migrated, skipped
  and why), never URLs, keys or credentials.
- Retry only transient failures, a bounded number of times, with growing delay; permanent failures are final.
  Every loop and queue is bounded.
- A failure shown per item (a card, a row) replaces only the information that failed; the item stays usable.
- Notifications are rate-limited so a failing source cannot spam the user.

## 8. Efficiency and limits

- Work is bounded by what is needed: compute the window (for example, a count of newest items) up front, request no
  more than the API allows, and parse only that many.
- Timers are explicit and one-shot unless there is a reason to repeat; repeating timers stop when there is nothing
  to do. No raw `setTimeout`/`setInterval`.
- Process work (shell, network) is queued and limited in concurrency.

## 9. Time, text and security

- All stored and compared times are UTC; local time is never used except for relative labels.
- Values reaching a shell or URL are validated by a strict anchored pattern that cannot admit whitespace, quotes or
  shell/URL metacharacters. Pass URLs and arguments as separate process arguments; never splice them into shell text.
- Secrets are not logged, and not stored as plain text where an alternative exists.
- No hard-coded user-visible defaults scattered in code: defaults and limits live in constants or in the
  declaration that owns them.

## 10. Naming and style

- Use clear, descriptive names. No abbreviations (`c`, `s`, `k`, `sel`, `ctx`, `fn`, `btn`, `tmp`), including in
  lambdas, loops over keys, shell variables and QML ids. `i` (and `j` when nested) is fine for a running index.
- Name a variable for what it **is**: `selection`, `pluginService`, `pendingGroup`, not its type or a shortening.
- Do not shadow or reuse a name for a different meaning in the same scope.
- Comments say why, not what; every file starts with a short header stating its role and its rules.
- Match the surrounding code: comment density, naming, idiom.
- One concept, one place: no duplicated approaches (for example, one clamp function, not two variants).

## 11. Testing

- Test on the real runtime where behaviour depends on it. Run QML headless and instantiate real contracts, services
  and singletons; text-matching a source file is not a behaviour test.
- Layers of tests:
  - Node tests for pure logic.
  - Real QML tests for contracts, services and facades.
  - Static audits for architecture rules (layers, one contract per file, no legacy handling outside the migration
    module, JS size ceiling, no direct reach around a facade).
  - An opt-in live test that exercises the real external services end to end.
- Load the real entry points (the widget, the settings page) in an integration test, against stand-ins for the host's
  own modules that keep the host's contract (required properties, types, when data is delivered), with the network and
  other external tools replaced by deterministic fakes. A unit test of each file cannot see ordering and timing
  problems between them.
- Stand-ins for the host's modules must sit exactly where the real types live (audited against the installed host
  when present); a stand-in in the wrong module hides a missing import.
- Create host-loaded pages in tests the way the host does: the page first, its services attached afterwards, host controls
  that save on every change, data that changes later. Assert that nothing is reported to the user in that window.
- Any runtime warning from the code under test (an undefined property, a component that is not ready, a binding
  error) fails the test run.
- Do not assert source text as a substitute for behaviour; a static check that encodes an assumption hides the bug.
- Tests mirror the source structure. Tests that need fresh state reset it in setup; no state leaks between tests.
- Every bug fix and every rule above gets a test or an audit that would have caught it.
- Keep the whole suite green before finishing any change.

## 12. Working method

- Decide, then act: when the rule is clear, apply it everywhere rather than in one place.
- Ask before assuming when a choice changes behaviour; otherwise pick the conventional default and say so.
- When a rule changes, update the tests, the audits, the documentation and the changelog together.
- Report what changed and what was not verified, plainly.
