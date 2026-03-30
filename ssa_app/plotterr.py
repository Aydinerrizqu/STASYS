import serial
import matplotlib
matplotlib.use('TkAgg')
import matplotlib.pyplot as plt
import matplotlib.animation as animation
from matplotlib.widgets import Button
from collections import deque
import sqlite3
from datetime import datetime
import os
import time

# --- Konfigurasi ---
BLUETOOTH_COM_PORT = 'COM6' # Ganti dengan port COM Anda, misal: 'COM5'
BAUD_RATE = 115200
SAMPLES = 100
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_FILE = os.path.join(SCRIPT_DIR, 'shooter_data.db')

# --- Variabel Status Perekaman dan Kalibrasi ---
is_recording = False
current_session_id = None
is_calibrated = False
gyro_bias = [0.0, 0.0, 0.0]
accel_bias = [0.0, 0.0, 0.0]

# --- Variabel Global untuk Data ---
all_queues = [deque([0.0]*SAMPLES, maxlen=SAMPLES) for _ in range(6)]

# --- Pengaturan Database ---
def setup_database():
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS recordings (
            id INTEGER PRIMARY KEY AUTOINCREMENT, timestamp DATETIME NOT NULL, session_id TEXT NOT NULL,
            accel_x REAL, accel_y REAL, accel_z REAL, gyro_x REAL, gyro_y REAL, gyro_z REAL
        )
    ''')
    conn.commit()
    conn.close()
    print(f"Database '{DB_FILE}' siap.")

def insert_reading(timestamp, session_id, values):
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()
    sql = 'INSERT INTO recordings(timestamp,session_id,accel_x,accel_y,accel_z,gyro_x,gyro_y,gyro_z) VALUES(?,?,?,?,?,?,?,?)'
    data_to_insert = (timestamp, session_id) + tuple(values)
    cursor.execute(sql, data_to_insert)
    conn.commit()
    conn.close()

# --- Membuat Plot dan Tombol ---
fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(12, 9))
fig.suptitle('Analisis Stabilitas Atlet Secara Real-Time (Bluetooth)', fontsize=16)
plt.subplots_adjust(bottom=0.2)

# --- Fungsi Callback ---
def start_recording(event):
    global is_recording, current_session_id
    if not is_recording:
        is_recording = True
        current_session_id = datetime.now().strftime('%Y-%m-%d_%H-%M-%S')
        print(f"--- Merekam dimulai. ID Sesi: {current_session_id} ---")
        button_start.color = 'limegreen'
        fig.canvas.draw_idle()

def stop_recording(event):
    global is_recording
    if is_recording:
        is_recording = False
        print("--- Merekam dihentikan. ---")
        button_start.color = '0.85'
        fig.canvas.draw_idle()

def calibrate_sensor(event):
    global gyro_bias, accel_bias, is_calibrated
    print("\n--- Memulai Kalibrasi ---")
    print("Harap letakkan sensor di permukaan yang datar dan jangan digerakkan selama 5 detik...")
    
    if ser.in_waiting > 0:
        ser.read(ser.in_waiting)
        
    samples_to_collect = 200
    gyro_samples = []
    accel_samples = []
    
    for _ in range(samples_to_collect):
        try:
            line = ser.readline().decode('utf-8', errors='ignore').strip()
            if line:
                parts = line.split(',')
                if len(parts) == 6:
                    values = list(map(float, parts))
                    accel_samples.append(values[0:3])
                    gyro_samples.append(values[3:6])
            time.sleep(0.02)
        except Exception as e:
            print(f"Error saat kalibrasi: {e}")
            continue
            
    if len(gyro_samples) < 50:
        print("Gagal mengumpulkan sampel kalibrasi. Coba lagi.")
        return

    accel_bias = [sum(axis) / len(axis) for axis in zip(*accel_samples)]
    gyro_bias = [sum(axis) / len(axis) for axis in zip(*gyro_samples)]
    
    # Asumsikan sensor diletakkan datar, Z-axis menunjuk ke atas melawan gravitasi
    accel_bias[2] -= 9.81 

    is_calibrated = True
    print("--- Kalibrasi Selesai ---")
    print(f"Bias Giroskop (X, Y, Z): {[f'{b:.4f}' for b in gyro_bias]}")
    print(f"Bias Akselerometer (X, Y, Z): {[f'{b:.4f}' for b in accel_bias]}")

# --- Fungsi Animasi Utama ---
def animate(i, ser):
    try:
        if ser.in_waiting > 0:
            data_bytes = ser.read(ser.in_waiting)
            lines = data_bytes.decode('utf-8', errors='ignore').strip().split('\n')
            
            for line in lines:
                if not line: continue
                try:
                    parts = line.split(',')
                    if len(parts) == 6:
                        values = list(map(float, parts))
                        
                        if is_calibrated:
                            corrected_values = [
                                values[0] - accel_bias[0], values[1] - accel_bias[1], values[2] - accel_bias[2],
                                values[3] - gyro_bias[0], values[4] - gyro_bias[1], values[5] - gyro_bias[2]
                            ]
                        else:
                            corrected_values = values

                        for q, val in zip(all_queues, corrected_values):
                            q.append(val)
                        if is_recording:
                            insert_reading(datetime.now(), current_session_id, corrected_values)
                except (ValueError, IndexError):
                    pass
    except serial.SerialException as e:
        print(f"Serial Error: {e}")
        return

    # Plot 1: Akselerometer (Y-axis Tetap)
    ax1.clear()
    ax1.plot(all_queues[0], color='r', label='Aksel X (Maju/Mundur)')
    ax1.plot(all_queues[1], color='g', label='Aksel Y (Kiri/Kanan)')
    ax1.plot(all_queues[2], color='b', label='Aksel Z (Naik/Turun)')
    ax1.set_title('Grafik Akselerometer (Goyangan Postur)')
    ax1.set_ylabel('m/s²')
    ax1.set_ylim(-12, 12)
    ax1.legend(loc='upper left', fontsize='small')
    ax1.grid(True, linestyle='--')
    
    # Plot 2: Giroskop (Y-axis Adaptif)
    ax2.clear()
    ax2.plot(all_queues[3], color='r', label='Giro X (Kemiringan)')
    ax2.plot(all_queues[4], color='g', label='Giro Y (Putaran)')
    ax2.plot(all_queues[5], color='b', label='Giro Z (Gulingan)')
    ax2.set_title('Grafik Giroskop (Stabilitas Bidikan)')
    ax2.set_xlabel('Waktu (Sampel)')
    ax2.set_ylabel('derajat/detik')
    # Tidak ada set_ylim() di sini, sehingga sumbu Y akan menyesuaikan secara otomatis
    ax2.legend(loc='upper left', fontsize='small')
    ax2.grid(True, linestyle='--')

    fig.tight_layout(rect=[0, 0, 1, 0.96])

# --- Eksekusi Utama ---
if __name__ == '__main__':
    setup_database()
    
    print("Mencari port serial Bluetooth...")
    try:
        ser = serial.Serial(BLUETOOTH_COM_PORT, BAUD_RATE, timeout=0.1)
        print(f"Terhubung ke {BLUETOOTH_COM_PORT} pada baud rate {BAUD_RATE}")
    except serial.SerialException:
        print(f"Error: Tidak dapat membuka port {BLUETOOTH_COM_PORT}.")
        print("Pastikan perangkat sudah dipasangkan dan port COM sudah benar.")
        exit()

    # Menambahkan tombol ke UI
    ax_calib = plt.axes([0.59, 0.05, 0.1, 0.075])
    button_calib = Button(ax_calib, 'Kalibrasi', color='skyblue', hovercolor='lightblue')
    button_calib.on_clicked(calibrate_sensor)

    ax_start = plt.axes([0.7, 0.05, 0.1, 0.075])
    button_start = Button(ax_start, 'Mulai Rekam', color='0.85', hovercolor='limegreen')
    button_start.on_clicked(start_recording)

    ax_stop = plt.axes([0.81, 0.05, 0.1, 0.075])
    button_stop = Button(ax_stop, 'Hentikan Rekam', color='lightcoral', hovercolor='red')
    button_stop.on_clicked(stop_recording)
        
    # Memanggil animasi. Blit dinonaktifkan untuk memungkinkan Y-axis adaptif.
    ani = animation.FuncAnimation(fig, animate, fargs=(ser,), interval=100, blit=False)
    
    plt.show()
    
    ser.close()
    print("Koneksi ditutup.")
