# Design: Session = 1 Baris, dengan Series di Dalamnya

**Date**: 2026-11-05
**Branch**: `PreProduction3_Design_Adjust`
**Approved via**: brainstorming session (pemilih series di detail, statistik ikut series terpilih, badge series di History, default series terakhir, simpan data mentah per series, series kosong tidak ditampilkan, END SESSION tersedia di luar series aktif)

## Goal

Satu sesi latihan = satu entri di History, meskipun sesi itu berisi beberapa
*series*. Saat user membuka detail sesi, ia memilih series yang ingin dilihat,
dan seluruh tampilan (target, chip shot, header, MATCH TOTAL) mengikuti
series terpilih.

Hari ini, setiap tombol **END SERIES** menulis baris `sessions` baru, sehingga
sesi 3 series tampil sebagai 3 kartu terpisah di History dan tidak ada cara
memihat "sesi ini secara keseluruhan". Perubahan ini membuat:

- 1 sesi latihan = 1 kartu di History, dengan badge jumlah series.
- Detail sesi punya pemilih series; chip shot dan semua statistik mengikuti
  series yang dipilih.
- Data mentah gyro/accel disimpan per series, sehingga Offline Replay bisa
  merekonstruksi trace series mana pun.
- Sesi lama (yang sebelumnya satu baris per series) tetap bisa dibaca.

Non-goal: mengubah algoritma scoring, deteksi shot, atau visual target.
Non-goal: penggabungan backfill sesi lama menjadi satu sesi — data lama tidak
mengandung informasi bahwa dua baris `sessions` berasal dari satu sesi.

## Current baseline (verified 2026-11-05)

**Penyimpanan** (`ssa_app/lib/services/`):

- SQLite `stasys_sessions.db`, schema version 2. Tabel `sessions` (metadata +
  6 BLOB mentah) dan `shots` (skor + 6 BLOB phase-trace).
- `shots.series_number` **sudah ada** di schema (added saat migrasi v1→v2),
  default 1, tapi **tidak pernah diisi** — `ShotResult.seriesNumber` selalu
  `1` karena shot dibuat di isolate yang tidak tahu nomor series.
- `sessions.series_count` sudah ada, diisi `train.seriesCount` saat save —
  nilainya adalah nomor series terakhir, bukan jumlah series.

**Alur tulis** (`train_screen.dart` → `sensor_data_provider.dart` →
`session_logger.dart` → `database_service.dart`):

- `TrainSessionProvider` adalah state machine `choices → readySeries →
  activeSeries → reviewSeries/reviewSession`, dengan `_seriesCount`,
  `_currentSeries`, `_allShots`, `_lastSeriesShots`.
- `END SERIES` (`train_screen.dart:610`) memanggil
  `sensor.saveCurrentSession(...)` dengan `shots = train.currentSeriesShots`
  lalu `train.endSeries()`. Setiap pemanggilan membuat **SessionLog baru**
  dengan id `SESSION_<millisecondsSinceEpoch>` dan
  `ConflictAlgorithm.replace` pada baris `sessions` — sehingga tiap series
  menjadi satu baris session tersendiri.
- `END SESSION` (`train_screen.dart:641`) melakukan hal yang sama untuk series
  aktif, lalu `train.endSession()`. Karena `endSession()` hanya mem-flush
  series yang sedang aktif, series yang sudah di-*END SERIES* tidak diduplikasi
  (komentar di `train_session_provider.dart:85`).
- `SensorDataProvider.saveCurrentSession` mengambil buffer mentah dari isolate
  (permintaan `get_session_data` bila buffer kosong), membangun `SessionLog`,
  lalu memanggil `SessionLogger.saveSession`.
- Setelah save, buffer sesi di provider **dikosongkan** dan isolate
  menerima `clear_session`. Jadi data mentah yang tersimpan selalu milik
  series/sesi terakhir saja.

**Pembacaan**:

- `DatabaseService.loadAllSessions()` membaca kolom ringkasan saja
  (`_summaryColumns` — tanpa BLOB mentah, demi batas CursorWindow ~2 MB) lalu
  memuat shot per sesi.
- `DatabaseService.getSession(id)` juga memuat BLOB mentah secara chunked
  (256 KB per query, lihat `database_service.dart:_readBlobColumn`).
- `SessionLog` menyimpan `gyroX…accelZ` sebagai `List<DataPoint>` dan
  `shots` sebagai `List<ShotResult>`.

**UI**:

- `HistoryScreen` menampilkan kartu sesi (tanggal, jam, chip jenis senjata,
  chip jumlah shot, AVG, tombol Replay) dengan `onTap` → `SessionDetailScreen`.
- `SessionDetailScreen` menampilkan header (`N shots — avg`), target
  `TrainTargetWidget`, strip chip shot, dan dialog HAPUS.
- `ReplayScreen` memuat sesi dari DB, menjalankan `ReplayEngine` atas data
  mentah, lalu menampilkan trace + chip shot.
- `HomeTab` punya kartu sesi sendiri dengan statistik yang sama.
- `ExportService` menulis CSV berisi ringkasan sesi dan daftar shot (tanpa
  kolom series).

## Key decisions (agreed in brainstorming)

1. **Satu sesi = satu baris `sessions`.** Series adalah anak, bukan sibling.
   `session_series` (tabel baru) menyimpan data mentah per series; `shots`
   menyimpan skor per shot dengan `series_number` yang benar.
2. **Data mentah disimpan per series** (bukan hanya series terakhir), agar
   Offline Replay bisa menampilkan trace series yang dipilih. Ini membutuhkan
   tabel baru + migrasi schema v2→v3.
3. **Pemilih series di UI berupa chip** di atas strip chip shot — konsisten
   dengan bahasa visual chip shot yang sudah dipakai.
4. **Semua statistik detail ikut series terpilih**: header `N shots — avg`,
   nilai MATCH TOTAL, dan strip chip shot. Kartu di History tetap menampilkan
   agregat seluruh sesi.
5. **Series default = yang terakhir**, karena itu hasil terbaru.
6. **Series tanpa shot tidak ditampilkan.** Daftar series diturunkan dari
   shot yang benar-benar ada, sehingga tidak ada logika khusus untuk
   session/series kosong. Nomor series tetap asli (bisa ada gap, mis. seri 1
   dan 3 tanpa seri 2). Konsekuensinya, `sessions.series_count` juga dihitung
   dari shot — bukan dari nomor series terakhir — supaya badge di History
   selalu konsisten dengan jumlah chip di pemilih series.
7. **Badge jumlah series ditambahkan di kartu History**, di samping chip
   jumlah shot yang sudah ada.
8. **Mengganti seri memakai UPDATE-lalu-INSERT**, bukan `INSERT OR REPLACE`.
   `ConflictAlgorithm.replace` pada `sessions` menghapus baris lama dulu, dan
   `ON DELETE CASCADE` akan ikut menghapus seluruh `shots` dan
   `session_series` anak — data sesi akan hilang setiap END SERIES.
9. **Migrasi v2→v3 bersifat non-destruktif**: kolom BLOB di `sessions`
   dipertahankan (legacy), tabel baru dibuat, dan data mentah sesi lama
   disalin ke `session_series` nomor 1. Tidak ada data yang dihapus.

## Architecture

```
TrainScreen                      (END SERIES / END SESSION)
  └─ TrainSessionProvider        pemilik sessionId + nomor series
       └─ SensorDataProvider     buffer mentah isolate per series
            └─ SessionLogger
                 └─ DatabaseService
                      ├─ sessions        (1 baris per sesi)
                      ├─ shots           (series_number terisi)
                      └─ session_series  (mentah per series)  ← BARU

HistoryScreen ──▶ SessionDetailScreen ──▶ (pilih series) ──▶ chip shot
                              └─▶ ReplayScreen ──▶ (pilih series) ──▶ trace
```

Ownership identitas sesi dipindah ke `TrainSessionProvider`: provider itu yang
tahu apakah seri ini masih milik sesi yang sama. `SensorDataProvider` tetap
menjadi pemilik buffer sensor mentah, tapi buffer itu sekarang **per series**
(dikosongkan/replace saat series berganti), bukan per sesi.

## Data model changes

### Schema v3

```sql
CREATE TABLE session_series (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  session_id TEXT NOT NULL,
  series_number INTEGER NOT NULL,
  duration REAL NOT NULL DEFAULT 0,
  gyro_x BLOB, gyro_y BLOB, gyro_z BLOB,
  accel_x BLOB, accel_y BLOB, accel_z BLOB,
  FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE,
  UNIQUE (session_id, series_number)
);
CREATE INDEX idx_session_series ON session_series(session_id, series_number);
```

Constraint `UNIQUE (session_id, series_number)` **wajib**: tanpa itu,
`INSERT OR REPLACE` tidak akan mengganti baris yang ada — SQLite hanya
memakai perilaku replace bila ada index UNIQUE pada target konflik. Tanpa
constraint ini, setiap END SERIES akan menumpuk baris series duplikat.

`shots` tidak berubah strukturnya — hanya `series_number` yang mulai diisi
dengan nilai sebenarnya. Kolom BLOB di `sessions` tetap ada (legacy) tetapi
tidak lagi ditulis untuk sesi baru.

### Migrasi v2 → v3

1. `CREATE TABLE session_series` + index (jika belum ada).
2. Untuk setiap sesi yang punya BLOB mentah:
   `INSERT OR IGNORE INTO session_series (session_id, series_number, duration, gyro_x, …)
    SELECT id, 1, duration, gyro_x, … FROM sessions WHERE gyro_x IS NOT NULL`.
   → sesi lama tampil sebagai "1 series", persis seperti sebelumnya.
   `INSERT OR IGNORE` dipakai karena tabel sudah punya `UNIQUE` dan
   migrasi harus aman bila dijalankan dua kali.
3. Kolom BLOB di `sessions` **tidak dihapus** — `decodeRawSession` tetap bisa
   membacanya sebagai fallback untuk sesi yang belum punya baris
   `session_series`.

Sesi lama yang tadinya 1 baris per series tetap 1 baris per series (tidak
digabung) — tidak ada informasi yang memungkinkan penggabungan.

### `ShotResult`

- `seriesNumber` mulai diisi benar (nilai 1..N).
- Butuh `copyWith` untuk men-stamp nomor series saat shot masuk ke provider.

### `SessionLog`

Menambah getter turunan (tidak menambah kolom DB):

```dart
/// Nomor series distinct yang punya shot, ascending.
List<int> get seriesNumbers;

/// Shot milik satu series.
List<ShotResult> shotsForSeries(int seriesNumber);

/// Rata-rata skor satu series.
double averageScoreForSeries(int seriesNumber);
```

`seriesNumbers` dihitung dari `shots` (distinct `seriesNumber`, ascending) —
ini yang mendasarui keputusan "series kosong tidak ditampilkan".

## Write path changes

### `TrainSessionProvider`

Menambah:
- `String? _sessionId` — id sesi yang sedang berjalan.
- `DateTime? _sessionStartedAt` — timestamp sesi (dipakai sebagai `date`).
- `int get currentSeriesNumber` — nomor series aktif.
- `void onShotDetected(ShotResult shot)` → men-stamp `seriesNumber` saat ini
  sebelum dimasukkan ke `_currentSeries`.

`startSeries()` membuat `sessionId` baru (jika belum ada) saat series 1 dimulai
dan menandai seri pertama.

`endSession()` menghapus identitas sesi (`_sessionId = null`), sehingga sesi
berikutnya benar-benar baru.

**END SERIES tanpa shot tidak menulis apa pun ke DB.** Tidak ada baris
`session_series`, tidak ada shot, dan `series_count` tidak bertambah. Data
mentah seri kosong ikut dibuang — tanpa shot, trace tidak punya arti. Perilaku
ini konsisten dengan keputusan 6 (series kosong tidak pernah terlihat).

### `SensorDataProvider.saveCurrentSession`

Diubah dari "selalu buat sesi baru" menjadi "upsert ke sesi + series":

- Menerima parameter tambahan `sessionId`, `seriesNumber`, `sessionDate`.
- Buffer mentah di provider menjadi **per series**. Pentingnya: setelah
  `saveCurrentSession` berhasil, provider sudah mengosongkan `_sessionGyro*`
  dan mengirim `clear_session` ke isolate — jadi seri berikutnya sudah mulai
  dari buffer kosong. Yang belum tertangani adalah kasus **END SERIES tanpa
  shot**: tidak ada save, sehingga buffer tidak pernah dikosongkan dan data
  mentah seri kosong itu akan ikut terbaca sebagai milik seri berikutnya.
  Perbaikannya: `SensorDataProvider.startRecording()` mengosongkan buffer
  sesi sebelum rekaman baru dimulai (titik tunggal tempat seri baru
  dimulai).
- `DatabaseService.upsertSessionWithSeries(...)` dipanggil dalam satu
  transaksi:
  - `DELETE FROM shots WHERE session_id=? AND series_number=?` (ulangi seri
    yang sama, mis. user mengulang seri)
  - batch insert shot seri tersebut
  - `UPDATE sessions SET duration=?, series_count=? WHERE id=?` — `duration`
    adalah durasi **kumulatif sesi** (durasi seri sebelumnya + durasi seri
    ini, bukan hanya durasi seri ini), dan `series_count` dihitung dari
    `SELECT COUNT(DISTINCT series_number) FROM shots WHERE session_id=?`
    **setelah** delete+insert di atas. Bila `rowsUpdated == 0` →
    `INSERT INTO sessions …` (sesi baru).
  - `INSERT OR REPLACE INTO session_series …` (aman: tabel `session_series`
    punya `UNIQUE (session_id, series_number)` dan tidak punya anak tabel)
- Setelahnya, buffer provider dikosongkan dan isolate diberi `clear_session`
  sehingga seri berikutnya mulai dari buffer kosong.

Urutannya penting: `series_count` harus dihitung **setelah** shot seri ini
disimpan, supaya nilainya selalu sama dengan jumlah chip di pemilih series.
`duration` dihitung di sisi Dart (akumulasi durasi seri), karena provider
tahu durasi tiap seri.

`series_count` pada `sessions` diisi **jumlah series distinct yang punya
shot** — dihitung ulang dari shot yang tersimpan, bukan dari nomor series
terakhir. Ini membuat nilainya selalu identik dengan jumlah chip di pemilih
series dan dengan badge di History.

### `DatabaseService`

**Aturan penyimpanan data mentah:** data mentah gyro/accel **hanya** hidup di
tabel `session_series`. Kolom BLOB di `sessions` tidak lagi ditulis untuk
sesi baru — kolom itu tetap ada hanya sebagai sumber fallback saat migrasi.
Alasan: satu sesi bisa punya beberapa series, sehingga tidak ada lagi
"data mentah sesi" tunggal; menyimpan di `sessions` juga menggandakan
megabyte data.

Metode baru:

```dart
/// Simpan/pertahankan satu sesi beserta satu series di dalamnya.
Future<void> upsertSessionWithSeries({...});

/// Baca data mentah per series untuk satu sesi.
Future<Map<int, Map<String, List<DataPoint>>>> getSeriesRaw(String sessionId);

/// Shot milik satu series.
Future<List<ShotResult>> getShotsForSeries(String sessionId, int seriesNumber);
```

`saveSession(SessionLog)` yang sudah ada **dipertahankan** sebagai pembungkus
yang memanggil `upsertSessionWithSeries` dengan `seriesNumber = 1`. Kontrak
lama tidak berubah: sesi yang disimpan lewat `saveSession` tetap bisa dibaca
penuh lewat `decodeRawSession`. Ini penting karena dipakai test.

`decodeRawSession(id)` membaca `session_series` lebih dulu, dan **fallback ke
kolom legacy `sessions`** untuk sesi yang belum punya baris `session_series`
(migrasi v2→v3 sudah menyalinnya, tapi fallback ini membuat jalur ini tahan
gagal).

**Perubahan kontrak `getSession(id)` — disengaja.** `getSession` berhenti
hydrate BLOB mentah dan hanya mengembalikan metadata + shot. Alasannya: pada
sesi multi-series tidak ada lagi "data mentah sesi" tunggal, jadi
`hasRawData` akan ambigu. Konsekuensi yang harus disadari:

- `ReplayScreen` tidak boleh lagi bergantung pada `session.hasRawData` dari
  `getSession`; ia memakai data mentah series terpilih dari `getSeriesRaw`.
- Dua test yang ada perlu disesuaikan assertion-nya (bukan dihapus):
  - `database_migration_test.dart` — "History summary omits raw BLOBs while
    getSession hydrates them" → `getSession` tidak lagi hydrate; raw diambil
    lewat `decodeRawSession`.
  - `database_row_size_test.dart` — "getSession loads a session whose raw row
    exceeds the row limit" → `getSession` tetap berhasil memuat sesi
    berukuran besar (metadata + shot) tanpa kena batas CursorWindow, dan
    data mentah diambil lewat `decodeRawSession` (sudah ada test saudara
    yang menutupnya).

Batas CursorWindow tetap dihormati: `session_series` dibaca per series dengan
chunk 256 KB (`_readBlobColumn` dengan kolom+sesi+series).

## UI changes

### `SessionDetailScreen`

- Header: `N shots — avg` dan `MATCH TOTAL` memakai nilai series terpilih.
- Baris baru di atas strip chip shot:
  `SERIES  [ 1 ] [ 2 ] [ 3 ]` — chip aktif diberi highlight (mengikuti gaya
  chip shot: isi accent + border accent).
- Strip chip shot menampilkan **hanya shot dari series terpilih**.
- Ganti series → shot terpilih direset ke shot terakhir di series itu, dan
  replay di-reset ke `1.0` (sama seperti saat memilih shot).
- State awal: series terakhir; shot terakhir dari series itu.

### `HistoryScreen`

- Badge baru "N SERIES" di samping chip jumlah shot. Hanya ditampilkan bila
  `N > 1` (sesi 1 series tidak perlu badge — pengguna sudah tahu).
- Kartu tetap menampilkan agregat seluruh sesi (total shot, avg).

### `ReplayScreen`

- Pemilih series ditambahkan di header area (hanya bila sesi punya >1 series).
- Trace dibangun dari data mentah series terpilih + shot series tersebut.
- `ReplayEngine` **tidak diubah**: ia menerima `SessionLog` dan memakai
  `session.gyroX…accelZ` + `session.shots`. Agar itu tetap benar, Replay
  menyusun `SessionLog` sementara yang berisi raw dan shot **hanya dari series
  terpilih** — jadi `ReplayEngine` tetap called dengan objek yang sama
  seperti sekarang, tanpa signature baru.

### `TrainScreen`

- `END SESSION` kini tampil juga di state `reviewSeries` dan `readySeries`
  (keputusan A), berdampingan dengan tombol `OK` / START. Tombol `END SERIES`
  tetap hanya saat series aktif.
- Label status seri tetap `SERIES n · …`.

### `ExportService`

- Kolom `series_number` ditambahkan ke bagian `# SHOTS` CSV, agar data
  per-series terbaca di luar aplikasi.

### `HomeTab`

- Kartu sesi memakai statistik agregat sesi (tidak berubah), tapi kini
  otomatis menampilkan jumlah shot gabungan beberapa series.

## Error handling

- `upsertSessionWithSeries` dibungkus satu transaksi: kegagalan di tengah
  tidak meninggalkan session tanpa shot.
- `getSeriesRaw` untuk series yang tidak ada mengembalikan map kosong; UI
  menampilkan empty state "NO TRACE DATA" yang sudah ada di `AnalysisTab`.
- Sesi legacy tanpa baris `session_series` → `getSeriesRaw` fallback ke kolom
  `sessions` sebagai series 1, sehingga Replay tetap berfungsi untuk data
  lama.

## Testing strategy

Semua test memakai `sqflite_common_ffi` dengan file DB unik per file test
(pola yang sudah dipakai `database_migration_test.dart` dan
`database_row_size_test.dart`).

**Database** (`test/unit/services/`):
- 2 series dalam 1 sesi → `sessions` berisi **1** baris, `session_series`
  berisi 2 baris, `shots` berisi shot dengan `series_number` 1 dan 2.
- Upsert series yang sama (ulangi seri) tidak menggandakan shot.
- Migrasi v2→v3: sesi legacy dengan BLOB mentah menghasilkan baris
  `session_series` nomor 1; shot legacy tetap `series_number = 1`.
- Sesi besar (>2 MB total) tetap terbaca: `getSeriesRaw` memakai chunking.
- `getSession` pada sesi multi-series mengembalikan semua shot.

**Provider** (`test/unit/providers/`):
- `sessionId` sama untuk seri 1 dan 2, berbeda untuk sesi berikutnya.
- `onShotDetected` men-stamp `seriesNumber` yang benar.
- `endSession` menghapus identitas sesi.

**Widget** (`test/unit/screens/`):
- Tap chip `SERIES 1` → chip shot dan header statistik berubah sesuai seri 1.
- Default saat membuka detail = seri terakhir.
- Kartu History menampilkan badge jumlah series.

**Regresi**: seluruh test yang sudah ada harus tetap lulus. Dua test perlu
penyesuaian **assertion** (bukan dihapus) karena kontrak `getSession` berubah —
lihat bagian `DatabaseService` di atas. Target: 208 test + test baru.

## Out of scope

- Penggabungan sesi lama yang sebelumnya terpisah.
- Penghapusan kolom BLOB legacy di `sessions`.
- Halaman statistik antar-seri (tren per seri di luar detail sesi).
- Perbandingan antar-seri di dalam detail sesi.
