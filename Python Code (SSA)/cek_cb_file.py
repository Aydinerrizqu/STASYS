import sqlite3
conn = sqlite3.connect('shooter_data.db')
cur = conn.cursor()

# Cek jumlah sessions
cur.execute("SELECT COUNT(DISTINCT session_id) FROM recordings")
print(f"Total sessions: {cur.fetchone()[0]}")

# Cek isi recordings
cur.execute("SELECT session_id, COUNT(*) FROM recordings GROUP BY session_id")
for row in cur.fetchall():
    print(f"Session {row[0]}: {row[1]} samples")

# Cek isi shots
cur.execute("SELECT session_id, COUNT(*) FROM shots GROUP BY session_id")
for row in cur.fetchall():
    print(f"Session {row[0]}: {row[1]} shots")

conn.close()