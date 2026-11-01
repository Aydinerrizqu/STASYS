# Design: Supabase Cloud Sync + Developer Panel

**Date**: 2026-11-01
**Branch**: `PreProduction3_Design_Adjust`
**Approved via**: brainstorming session (Supabase + Google/Email login + auto-sync + Supabase Studio panel)

## Goal

Add a cloud backend to STASYS so that:

- Training sessions recorded on the phone are backed up to a server, so the user
  does not lose data when the phone is lost, wiped, or reinstalled.
- The developer can inspect all user data (sessions, shots, trends) from an
  internal panel.
- The app keeps working exactly as today when there is no account and no
  network. Nothing about the live path (Bluetooth streaming, shot detection,
  scoring, local SQLite) changes.

Explicitly **not** a goal for this milestone: a public web app, leaderboards,
coaching workflows, push notifications, server-side firmware distribution,
or user-facing self-service account deletion.

## Current baseline (verified 2026-11-01)

The repository has no network layer at all. Everything is local.

**Firmware** (`Firmware_STASYS32/`, ESP-IDF):

- Bluetooth Classic SPP only. No WiFi, no HTTP, no MQTT.
- Streams 36-byte frames at 100 Hz, auth-free (`ESP_SPP_SEC_NONE`).
- Device name is `STASYS-%04X` derived from the MAC address; there is no
  stable device ID that the app could send to a server.
- `src/ota/` is dead code (not referenced by `src/CMakeLists.txt`).

**Flutter app** (`ssa_app/`):

- Storage: SQLite `stasys_sessions.db` (tables `sessions` and `shots`, schema
  version 2) plus SharedPreferences for settings and local profiles.
- `SessionLog` (12 metadata fields + 6 raw time series) and `ShotResult`
  (8 scores + `travelDistance`/`peakJerk` + 6 phase-trace arrays) are the
  canonical data shapes.
- Raw time series are stored as binary BLOBs:
  `int32 count` + `count * (float32 relTimestamp, float32 value)`.
  Phase traces are stored as `int32 count` + `count * float64`.
- `export_service.dart` produces CSV through the Share Sheet. This is the only
  way data leaves the device today.
- There is no HTTP client dependency (`http`/`dio` are absent from
  `pubspec.yaml`) and no code calls `Uri.parse` or `HttpClient`.
- `firebase_core` and `firebase_crashlytics` are declared in `pubspec.yaml`
  but never initialized: there is no `google-services.json`, no
  `firebase_options.dart`, and no `Firebase.initializeApp` call.
- Session persistence happens in `sensor_data_provider.dart`, which calls
  `_sessionLogger.saveSession(log)` (around line 536) after building the
  `SessionLog` with a client-generated id `SESSION_<millisecondsSinceEpoch>`.
- Uncommitted work in the working tree fixes Android's
  `Row too big to fit into CursorWindow` by reading BLOBs in 256 KB chunks.
  Session payloads are therefore large (megabytes), which constrains how they
  may be uploaded.

## Key decisions (agreed in brainstorming)

| Decision | Choice | Rationale |
|---|---|---|
| Backend stack | Supabase (Postgres + Auth + Storage) | SQL is the strongest tool for the aggregation and CSV export the developer panel needs; one vendor covers auth, database, and blob storage. |
| Purpose of the backend | Cloud backup and sync, plus developer access to user data | Offline-first app, server-side analytics. |
| Who the panel is for | Developer only, internal | Smallest milestone; a custom web panel can follow later. |
| Login method | Google + Email | Least friction on Android/iOS; Supabase Auth handles the OAuth flow. |
| What is uploaded per session | Scores + phase traces + raw BLOB backup | Meets "complete user data" and allows recomputing scores if the algorithm changes. |
| When sync happens | Automatically when a session ends, with an offline queue | The user should not have to think about it. |
| Panel shape | Supabase Studio + saved SQL views | No web frontend to build or host. |

## Architecture

```
┌──────────────┐  BT SPP   ┌───────────────────────────┐   HTTPS (REST)   ┌─────────────────────────────┐
│    ESP32     │ ────────► │       Flutter app         │ ───────────────► │         Supabase            │
│  stream 100Hz│           │  offline-first            │                  │                             │
└──────────────┘           │  SQLite (tetap sumber      │   sync otomatis  │  Postgres  → sessions/shots │
                           │  utama, jalan tanpa akun)  │   + antre offline│  Storage   → raw BLOB       │
                           └───────────────────────────┘                  │  Auth      → Google/Email   │
                                          ▲                               └──────────────┬──────────────┘
                                          │ login opsional                                 │
                                   ┌──────┴───────┐                          Supabase Studio + SQL views
                                   │  Akun user   │                          (panel developer — read-only)
                                   │ Google/Email │
                                   └──────────────┘
```

Division of responsibility, unchanged from the offline app:

- **On the phone**: everything that needs the raw sensor stream or low latency.
  Shot detection, the three-phase analysis (hold/press/recoil), scoring, live
  trace rendering, and trajectory replay all stay on the device.
- **On the server**: everything that needs history across many sessions or many
  users. Storage, trend queries, cohort statistics, and export.

The server never re-scores a shot and never receives the 100 Hz stream. It
receives the finished result of the on-device analysis.

### The two kinds of "profile"

These are distinct and must not be conflated in the schema or in the code:

- **Supabase account** — the identity that owns uploaded data, referenced as
  `user_id`. Optional; the app works without it.
- **App profile** (`profile_service.dart`, `models/profile.dart`) — a local,
  name-only value object (the shooter's name) that is attached to sessions as
  the `profile_name` column. It is metadata and is uploaded as such.

## Database schema (Supabase / Postgres)

### Table `sessions`

| Column | Type | Notes |
|---|---|---|
| `id` | `text` PK | The client-generated `SESSION_<ms>` id. Makes sync idempotent. |
| `user_id` | `uuid` FK → `auth.users` | Owner. `ON DELETE CASCADE`. |
| `date` | `timestamptz` | Session start. |
| `duration` | `double precision` | Seconds. |
| `firearm_type` | `text` | `pistol` / `rifle` / `shotgun` / … (enum *name*, not label). |
| `training_mode` | `text` | `dryFire` / … (enum *name*). |
| `profile_name` | `text` | App profile name, may be empty. |
| `training_preset` | `text` | May be empty. |
| `series_count` | `integer` | |
| `raw_path` | `text` | Folder path in the `session-raw` bucket. |
| `created_at` | `timestamptz` | Server default. |

Index: `sessions (user_id, date DESC)`, `sessions (date DESC)`.

### Table `shots`

| Column | Type | Notes |
|---|---|---|
| `id` | `bigint` identity PK | Server-assigned; the local shot id is not stable and is not used. |
| `session_id` | `text` FK → `sessions(id)` | `ON DELETE CASCADE`. |
| `timestamp` | `timestamptz` | |
| `total_score`, `hold_score`, `press_score`, `recoil_score`, `elevation_score`, `windage_score` | `double precision` | 0–100. |
| `travel_distance` | `double precision` | Radians. |
| `peak_jerk` | `double precision` | |
| `firearm_type`, `training_mode` | `text` | |
| `series_number` | `integer` | |
| `hold_x`, `hold_y`, `press_x`, `press_y`, `recoil_x`, `recoil_y` | `double precision[]` | The 6 phase-trace arrays. Postgres arrays map 1:1 onto Dart's `List<double>`. |

Index: `shots (session_id)`, `shots (total_score DESC)`.

### Storage bucket `session-raw` (private)

Six files per session, at `{user_id}/{session_id}/{axis}.bin`:

```
gyro_x.bin  gyro_y.bin  gyro_z.bin  accel_x.bin  accel_y.bin  accel_z.bin
```

The byte format is **identical to the existing SQLite encoding** — no new
format is introduced:

- Time series: `int32 count` (little endian) + `count` × (`float32`
  relTimestamp, `float32` value).
- Phase traces: `int32 count` + `count` × `float64`.

Because the format is shared, a future server-side recompute of scores reads
the same bytes the app already writes locally.

### Row Level Security

Both tables enable RLS. The only policies are "own rows":

```sql
create policy "own rows" on sessions
  for all using (user_id = auth.uid()) with check (user_id = auth.uid());
```

The same policy shape applies to `shots` via a join on `session_id`. The
Storage bucket is private with a path-prefix policy so that a user can only
read objects under their own `{user_id}/` prefix.

Developer access uses the service-role key from Supabase Studio, which bypasses
RLS. The anon key shipped in the app is safe to bundle because RLS is what
enforces access.

### Developer panel views (SQL)

Three views are created in the Supabase SQL editor and used from Studio's
table editor (they also power its chart builder). No web application is
built for this milestone.

```sql
-- 1. Most recent sessions across all users, with the owner's email.
create view v_recent_sessions as
select s.id,
       s.user_id,
       u.email            as user_email,
       s.date,
       s.duration,
       s.firearm_type,
       s.training_mode,
       s.profile_name,
       s.training_preset,
       s.series_count,
       count(sh.id)       as shot_count,
       avg(sh.total_score) as avg_total_score,
       max(sh.total_score) as best_total_score,
       min(sh.total_score) as worst_total_score
from sessions s
left join auth.users u on u.id = s.user_id
left join shots sh on sh.session_id = s.id
group by s.id, u.email
order by s.date desc;

-- 2. Weekly score trend per user.
create view v_user_progress as
select s.user_id,
       u.email            as user_email,
       date_trunc('week', s.date) as week,
       count(distinct s.id)      as session_count,
       count(sh.id)              as shot_count,
       avg(sh.hold_score)        as avg_hold,
       avg(sh.press_score)       as avg_press,
       avg(sh.recoil_score)      as avg_recoil,
       avg(sh.total_score)       as avg_total
from sessions s
left join auth.users u on u.id = s.user_id
left join shots sh on sh.session_id = s.id
group by s.user_id, u.email, date_trunc('week', s.date)
order by s.user_id, week desc;

-- 3. Per-user activity summary.
create view v_activity as
select s.user_id,
       u.email              as user_email,
       count(distinct s.id)  as session_count,
       count(sh.id)          as shot_count,
       min(s.date)          as first_session,
       max(s.date)          as last_session,
       sum(s.duration)      as total_duration_sec
from sessions s
left join auth.users u on u.id = s.user_id
left join shots sh on sh.session_id = s.id
group by s.user_id, u.email
order by last_session desc;
```

Views are read-only by nature; the service-role key in Studio is what grants
the developer unrestricted access to the underlying tables.

## Flutter app changes

### Dependencies

- `supabase_flutter` — client for Auth, PostgREST, and Storage.
- `google_sign_in` — Google OAuth. Requires a real `applicationId` and SHA-1
  in the Firebase/Google Cloud project; `com.example.ssa_app` must be replaced
  first.

`connectivity_plus` is deliberately **not** added: the sync queue is driven by
success/failure of the HTTP call itself, not by a connectivity signal.

### New services

**`lib/services/auth_service.dart`**

Wraps Supabase Auth. Responsibilities: `signInWithGoogle()`,
`signInWithEmail(email, password)`, `signOut()`, and exposing the
`authStateChanges` stream. When signed out, every other component treats the
user as anonymous and sync is disabled.

**`lib/services/sync_service.dart`**

The core of the backend integration.

- **Queue**: a new column `sync_status INTEGER NOT NULL DEFAULT 0` on the
  local `sessions` table (SQLite migration v2 → v3). `0 = pending`,
  `1 = done`, `2 = failed`. Pending rows are the queue; no separate queue
  table is needed.
- **Idempotency**: everything is an upsert keyed on the session `id`, and
  Storage objects are written to a fixed path. Retrying any number of times
  produces the same server state.
- **Upload order**: (1) upload the 6 raw BLOBs to Storage; (2) upsert the
  `sessions` row (with `raw_path` already set) and its `shots` rows via
  PostgREST; (3) mark the local row `sync_status = 1`. BLOBs go first so the
  `sessions` row never exists on the server without its raw data; a failure
  leaves only orphan objects under a path that the retry overwrites anyway.
  A failure at any step leaves the local row `pending` for a later attempt.
- **Retry**: exponential backoff. After a bounded number of failures the row
  is marked `failed` and the user can retry it manually.
- **Triggers**: called from `sensor_data_provider.dart` immediately after
  `_sessionLogger.saveSession(log)` succeeds, plus a sweep on app start and on
  app resume (drains any rows left `pending` from previous runs).
- **Demo sessions are excluded**: a session produced by demo mode is not
  queued. The flag is passed at the call site, not inferred later.

### Local database migration (v2 → v3)

`database_helper.dart` gains:

```sql
ALTER TABLE sessions ADD COLUMN sync_status INTEGER NOT NULL DEFAULT 0;
```

and `database_service.dart` gains a way to read and update that column. The
existing `onUpgrade` block already handles v1 → v2 in this style and is
extended, not rewritten.

### New UI

- **Settings → ACCOUNT** section (new `_buildSectionHeader('ACCOUNT')` block
  in `settings_screen.dart`, matching the existing section style): sign-in
  button (Google / Email), signed-in state with the account email, sign-out,
  a "N sessions waiting to sync" indicator, and a retry button.
- **History**: a small sync badge per session row (pending / uploading /
  synced). Icon only, no layout change.
- **First sign-in dialog**: the first time a user signs in, offer to upload the
  N sessions already on the phone (default yes, skippable). This prevents an
  unannounced mass upload of the entire history.
- The ACCOUNT section is always visible. While signed out it shows a
  "Sign in to back up your sessions" prompt, so the feature is discoverable.

## Error handling

| Situation | Behaviour |
|---|---|
| No account | Sync is disabled. The app is otherwise unchanged. |
| No network | Upload fails, row stays `pending`, no error surfaced to the user. |
| Partial upload (rows ok, BLOB failed) | Row stays `pending`; the next attempt re-uploads both. Upserts make this safe. |
| Server error / 5xx | Same as "no network", with backoff. |
| Auth expired | The Supabase client refreshes tokens automatically; a persistent auth error marks the session `failed` and the Settings screen offers re-login. |
| Local deletion of a synced session | The local row is removed. Server-side deletion is **out of scope** for this milestone and is listed as a follow-up; until then the developer can delete stale rows from Studio. |
| Duplicate id | Impossible to cause: the id is `SESSION_<millisecondsSinceEpoch>` and upsert overwrites. |

## Privacy and consent

- The sign-in screen states that sessions are uploaded so the user can restore
  them and so the developer can improve the app.
- The app is a firearms-training tool; session traces are behavioural data.
  Before any public release, a privacy policy covering the uploaded data must
  exist.
- `applicationId` is still `com.example.ssa_app` and the release build is
  signed with the debug key. Both block a real store release and are tracked
  as separate prerequisites.

## Testing

- **Unit — `SyncService`**: with a mocked `SupabaseClient` (mocktail is
  already a dev dependency). Cover the pending → done transition, the
  pending → failed transition with backoff, retry after failure, demo sessions
  being skipped, and the order of row-upload vs BLOB-upload.
- **Unit — encoding parity**: assert that the bytes the app writes for the 6
  BLOBs match the documented layout (`int32 count` + float pairs), since the
  server relies on it.
- **Unit — migration**: extend the existing `database_migration_test.dart`
  pattern with a v2 → v3 case asserting `sync_status` defaults to `0` and
  that existing rows are preserved.
- **Regression**: the existing 190 tests must stay green.
- **Manual end-to-end**: sign in against a real Supabase project, record and
  finish a session, confirm the row and its BLOBs appear in Studio.

## Implementation phases

1. **Supabase project setup** (not app code): create the project, apply the
   schema, enable RLS, create the `session-raw` bucket, and save the three SQL
   views in the SQL editor.
2. **App — auth**: add the dependency, implement `AuthService`, add the
   ACCOUNT section to Settings with the sign-in and sign-out flow.
3. **App — sync**: implement `SyncService`, the SQLite v2 → v3 migration, the
   hook after `saveSession`, and the sync indicators.
4. **App — polish**: first-sync dialog, manual retry, tests.

Each phase ends with something demonstrable and independently testable.

## Follow-ups (not in this milestone)

- Server-side deletion of sessions when the user deletes them locally.
- A custom web panel (the SQL views are the seed of it).
- Analytics and crash reporting: `firebase_crashlytics` is declared but never
  initialized; it needs a `google-services.json` and is unrelated to the sync
  work.
- Device identity and firmware distribution over the network.
- Release signing and a real `applicationId`.

## Open items for implementation

- The Supabase project URL and anon key are passed at build time with
  `--dart-define=SUPABASE_URL=…` / `--dart-define=SUPABASE_ANON_KEY=…` and
  read via `String.fromEnvironment`. No new dependency, and nothing secret is
  committed. (The anon key is not secret — RLS is the enforcement — but
  keeping it out of the repo avoids accidental public forks reusing the
  project quota.)
- Whether the six phase-trace arrays are stored as Postgres arrays (as
  designed) or as JSONB. Postgres arrays were chosen because they map directly
  onto `List<double>`; JSONB is the fallback if array handling in PostgREST
  proves awkward in practice.
