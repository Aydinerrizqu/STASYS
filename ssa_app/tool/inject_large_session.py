"""Inject a large session into the pulled app database.

Mirrors the BLOB encoding used by DatabaseService:
  int32 count + count * (float32 relTimestamp, float32 value)
"""
import struct
import sqlite3
import sys

db_path = sys.argv[1]

# 60 000 samples per axis = ~480 KB per axis, ~2.8 MB for one session row.
# That exceeds Android's ~2 MB CursorWindow limit, which is exactly the case
# the chunked BLOB read has to survive.
SAMPLES = 60000


def encode_time_series():
    buf = bytearray()
    buf += struct.pack('<i', SAMPLES)
    for i in range(SAMPLES):
        buf += struct.pack('<ff', i / 100.0, (i % 7) / 7.0)
    return bytes(buf)


def encode_double_list(values):
    buf = bytearray()
    buf += struct.pack('<i', len(values))
    for v in values:
        buf += struct.pack('<d', v)
    return bytes(buf)


conn = sqlite3.connect(db_path)
cur = conn.cursor()

raw = encode_time_series()
print('blob bytes per axis:', len(raw))

# --- session 1: huge raw payload, 3 shots -------------------------------
cur.execute('DELETE FROM sessions')
cur.execute('DELETE FROM shots')

cur.execute(
    '''INSERT INTO sessions
       (id, date, duration, firearm_type, training_mode, profile_name,
        training_preset, series_count, gyro_x, gyro_y, gyro_z,
        accel_x, accel_y, accel_z)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
    (
        'HUGE_SESSION', 1794000000000, 300.0, 'pistol', 'dryFire',
        'Huge Profile', 'dry-air-softgun-10', 1,
        raw, raw, raw, raw, raw, raw,
    ),
)

for idx in range(3):
    cur.execute(
        '''INSERT INTO shots
           (session_id, timestamp, total_score, hold_score, press_score,
            recoil_score, elevation_score, windage_score, travel_distance,
            peak_jerk, firearm_type, training_mode, series_number,
            hold_x, hold_y, press_x, press_y, recoil_x, recoil_y)
           VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)''',
        (
            'HUGE_SESSION', 1794000000000 + idx * 1000,
            80.0 + idx, 81.0, 82.0, 83.0, 80.0, 80.0, 0.01, 1.0,
            'pistol', 'dryFire', 1,
            encode_double_list([0.1 * i for i in range(10)]),
            encode_double_list([0.2 * i for i in range(10)]),
            encode_double_list([0.3 * i for i in range(10)]),
            encode_double_list([0.4 * i for i in range(10)]),
            encode_double_list([0.5 * i for i in range(10)]),
            encode_double_list([0.6 * i for i in range(10)]),
        ),
    )

# --- session 2: small, no raw data --------------------------------------
cur.execute(
    '''INSERT INTO sessions
       (id, date, duration, firearm_type, training_mode, profile_name,
        training_preset, series_count, gyro_x, gyro_y, gyro_z,
        accel_x, accel_y, accel_z)
       VALUES (?,?,?,?,?,?,?,?,NULL,NULL,NULL,NULL,NULL,NULL)''',
    (
        'SMALL_SESSION', 1794000600000, 60.0, 'rifle', 'liveFire',
        'Small Profile', 'rifle-50', 1,
    ),
)
cur.execute(
    '''INSERT INTO shots
       (session_id, timestamp, total_score, hold_score, press_score,
        recoil_score, elevation_score, windage_score, travel_distance,
        peak_jerk, firearm_type, training_mode, series_number,
        hold_x, hold_y, press_x, press_y, recoil_x, recoil_y)
       VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,NULL,NULL,NULL,NULL,NULL,NULL)''',
    (
        'SMALL_SESSION', 1794000600000, 91.0, 92.0, 93.0, 94.0, 95.0, 96.0,
        0.02, 2.0, 'rifle', 'liveFire', 1,
    ),
)

conn.commit()
rows = cur.execute('SELECT id, length(gyro_x) FROM sessions').fetchall()
print('sessions:', rows)
print('shots:', cur.execute('SELECT COUNT(*) FROM shots').fetchone()[0])
conn.close()
print('OK')
