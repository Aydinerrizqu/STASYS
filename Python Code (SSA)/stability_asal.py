#!/usr/bin/env python3
"""
Real-time Stability Monitor - Tuned Shot Detection
(Updated: Gravity Compensated + Airsoft Mode + Fixed Manual Logging)
"""

import sys
import serial
from collections import deque
import sqlite3
from datetime import datetime
import os
import time
import math
import random
import hashlib
import hmac
import string
import struct 

import pyqtgraph as pg
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                             QHBoxLayout, QPushButton, QLabel, QListWidget, 
                             QGroupBox, QShortcut, QCheckBox, QProgressBar,
                             QComboBox, QDoubleSpinBox)
from PyQt5.QtGui import QKeySequence, QFont
from PyQt5.QtCore import QTimer, Qt

# --- CONFIGURATION ---
BLUETOOTH_COM_PORT = 'COM5' # <--- VERIFY YOUR PORT
BAUD_RATE = 115200
SAMPLES = 100 
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_FILE = os.path.join(SCRIPT_DIR, 'shooter_data.db')
SECRET_KEY = b"12ebaf10h12fa9123z21sti"

# --- BINARY PROTOCOL SETTINGS ---
PACKET_SIZE = 28

# --- DEFAULT SETTINGS ---
DIFFICULTY_MULTIPLIER = 30.0 
SHOT_THRESHOLD = 10.0   
SHOT_COOLDOWN = 0.5    

# --- Globals ---
is_recording = False
current_session_id = None
is_calibrated = False
battery_percentage = 0
last_shot_time = 0.0

gyro_bias = [0.0, 0.0, 0.0]
accel_ref_mag = 9.81        
gyro_noise_std = [0.0, 0.0, 0.0]   
accel_mag_noise = 0.0       

score_queue = deque([100.0]*SAMPLES, maxlen=SAMPLES)
hold_buffer = deque([100.0]*20, maxlen=20) 

elev_queue = deque([0.0]*SAMPLES, maxlen=SAMPLES)
wind_queue = deque([0.0]*SAMPLES, maxlen=SAMPLES)
cant_queue = deque([0.0]*SAMPLES, maxlen=SAMPLES)

# --- High-Pass Filter Globals (For Airsoft) ---
gravity_filter = [0.0, 0.0, 0.0] # Tracks gravity to remove it
alpha = 0.85 # Filter smoothing factor (0.8-0.9 is good for vibration)
prev_linear_mag = 0.0 # For Jerk calculation in Airsoft mode

# --- DB Setup ---
def setup_database():
    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()
    
    # 1. Create Base Tables
    cur.execute('''
        CREATE TABLE IF NOT EXISTS recordings (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp DATETIME NOT NULL,
            session_id TEXT NOT NULL,
            stability_score REAL,
            battery_percentage REAL
        )
    ''')
    cur.execute('''
        CREATE TABLE IF NOT EXISTS shots (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp DATETIME NOT NULL,
            session_id TEXT NOT NULL,
            shot_score REAL,
            notes TEXT
        )
    ''')
    
    # 2. Migration: Add Axis Columns if they don't exist
    cur.execute("PRAGMA table_info(recordings)")
    columns = [info[1] for info in cur.fetchall()]
    
    if 'elev' not in columns:
        print("Migrating DB: Adding Axis Columns...")
        try:
            cur.execute("ALTER TABLE recordings ADD COLUMN elev REAL")
            cur.execute("ALTER TABLE recordings ADD COLUMN wind REAL")
            cur.execute("ALTER TABLE recordings ADD COLUMN cant REAL")
        except Exception as e:
            print(f"Migration Warning: {e}")

    conn.commit()
    conn.close()

def insert_reading(score, bat, elev, wind, cant):
    if not is_recording: return
    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()
    cur.execute(
        '''INSERT INTO recordings(
            timestamp, session_id, stability_score, battery_percentage, 
            elev, wind, cant
           ) VALUES(?,?,?,?,?,?,?)''',
        (datetime.now(), current_session_id, score, bat, elev, wind, cant)
    )
    conn.commit()
    conn.close()

def log_shot_to_db(score, is_auto=False):
    if not is_recording: return
    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()
    note = "Auto-Detected" if is_auto else "Manual"
    cur.execute(
        'INSERT INTO shots(timestamp,session_id,shot_score, notes) VALUES(?,?,?,?)',
        (datetime.now(), current_session_id, score, note)
    )
    conn.commit()
    conn.close()

# --- BINARY PARSING ---
def parse_binary_packet(ser):
    try:
        while ser.in_waiting >= PACKET_SIZE:
            b1 = ser.read(1)
            if b1 != b'\xAA': continue 
            
            b2 = ser.read(1)
            if b2 != b'\xBB': continue 

            raw_data = ser.read(PACKET_SIZE - 2)
            if len(raw_data) != PACKET_SIZE - 2: return None 

            try:
                unpacked = struct.unpack('<ffffffBB', raw_data)
            except struct.error:
                return None
                
            ax, ay, az, gx, gy, gz, batt, checksum_recv = unpacked

            calc_sum = 0
            for i in range(len(raw_data) - 1): 
                calc_sum ^= raw_data[i]

            if calc_sum == checksum_recv:
                return [ax, ay, az, gx, gy, gz], batt
            else:
                if 0 <= batt <= 100:
                    return [ax, ay, az, gx, gy, gz], batt
                return None
    except Exception as e:
        print(f"Parse Error: {e}")
        pass
    return None

def calculate_score_0_to_100(values):
    ax, ay, az, gx, gy, gz = values
    
    if not is_calibrated:
        gyro_mag = math.sqrt(gx**2 + gy**2 + gz**2)
        accel_dev = abs(math.sqrt(ax**2 + ay**2 + az**2) - 9.81)
        return max(0.0, 100.0 - ((gyro_mag + accel_dev*0.5) * DIFFICULTY_MULTIPLIER))

    d_gx = abs(gx - gyro_bias[0])
    d_gy = abs(gy - gyro_bias[1])
    d_gz = abs(gz - gyro_bias[2])
    
    d_gx = max(0.0, d_gx - (gyro_noise_std[0] * 2.0))
    d_gy = max(0.0, d_gy - (gyro_noise_std[1] * 2.0))
    d_gz = max(0.0, d_gz - (gyro_noise_std[2] * 2.0))
    gyro_instability = math.sqrt(d_gx**2 + d_gy**2 + d_gz**2)

    curr_mag = math.sqrt(ax**2 + ay**2 + az**2)
    accel_instability = abs(curr_mag - accel_ref_mag)
    accel_instability = max(0.0, accel_instability - (accel_mag_noise * 3.0))

    total_instability = gyro_instability + (accel_instability * 0.5)
    raw_score = 100.0 - (total_instability * DIFFICULTY_MULTIPLIER)
    return max(0.0, min(100.0, raw_score))

def perform_authentication(ser):
    try:
        print("Auth: Waiting for 'READY'...")
        start_wait = time.time()
        ready_received = False
        
        while time.time() - start_wait < 5.0:
            if ser.in_waiting:
                try:
                    line = ser.readline().decode('utf-8', errors='ignore').strip()
                    if "READY" in line:
                        ready_received = True
                        break
                except: pass
            time.sleep(0.05)
            
        if not ready_received:
            print("Auth: Timed out.")
            return False

        ser.reset_input_buffer()
        
        challenge = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
        print(f"Auth: Sending {challenge}")
        ser.write(f"{challenge}\n".encode('utf-8'))
        
        ser.timeout = 3
        esp_response = ser.readline().decode('utf-8').strip()
        ser.timeout = 0.5 
        
        print(f"Auth: Response '{esp_response}'")
        if not esp_response: return False
        
        to_hash = (challenge + SECRET_KEY.decode('utf-8')).encode('utf-8')
        expected_response = hashlib.sha256(to_hash).hexdigest()
        
        return hmac.compare_digest(esp_response, expected_response)
    except Exception as e:
        print(f"Auth Error: {e}")
        return False

# --- Main Application ---
if __name__ == '__main__':
    setup_database()
    
    ser = None
    try:
        ser = serial.Serial(BLUETOOTH_COM_PORT, BAUD_RATE, timeout=1)
        print(f"Connected to {BLUETOOTH_COM_PORT}")
        time.sleep(1.5) 

        if not perform_authentication(ser):
            print("Auth Failed. Exiting.")
            ser.close()
            sys.exit(1)
        
        ser.reset_input_buffer()
        print("Auth Success. Buffer Cleared.")

    except Exception as e:
        print(f"Connection Error: {e}")

    app = QApplication(sys.argv)
    main_window = QMainWindow()
    main_window.setWindowTitle('Sniper Stability Trainer (Multi-Sport)')
    main_window.resize(1000, 650)
    
    central_widget = QWidget()
    main_window.setCentralWidget(central_widget)
    main_layout = QHBoxLayout(central_widget)
    
    left_widget = QWidget()
    left_layout = QVBoxLayout(left_widget)
    
    lbl_mode = QLabel("Select Sport Mode:")
    lbl_mode.setFont(QFont("Arial", 10, QFont.Bold))
    left_layout.addWidget(lbl_mode)

    cmb_mode = QComboBox()
    cmb_mode.addItem("Target Shooting (Airsoft/Smallbore)")
    cmb_mode.addItem("Archery (Recurve/Compound)")
    cmb_mode.addItem("Long Range Rifle (Centerfire)")
    cmb_mode.addItem("Airsoft / Dry Fire (High Sensitivity)") # NEW MODE
    cmb_mode.setStyleSheet("font-size: 11pt; padding: 5px;")
    left_layout.addWidget(cmb_mode)

    pg.setConfigOptions(useOpenGL=True)
    plot_widget = pg.PlotWidget(title="Stability Analysis (rad/s)")
    plot_widget.showGrid(x=False, y=True, alpha=0.3)
    plot_widget.addLegend(offset=(10, 10))
    
    curve_elev = plot_widget.plot(pen=pg.mkPen('r', width=2), name='Elevation')
    curve_wind = plot_widget.plot(pen=pg.mkPen('g', width=2), name='Windage')
    curve_cant = plot_widget.plot(pen=pg.mkPen('b', width=2), name='Cant')
    left_layout.addWidget(plot_widget)

    # --- Accel Data & Sensitivity Control ---
    accel_layout = QHBoxLayout()
    
    # 1. Kick/Jerk Display (Gravity Compensated)
    lbl_accel_mag = QLabel("Kick: 0.00")
    lbl_accel_mag.setFont(QFont("Consolas", 12, QFont.Bold))
    lbl_accel_mag.setAlignment(Qt.AlignCenter)
    lbl_accel_mag.setStyleSheet("color: #333; background-color: #EEE; border: 1px solid #CCC; border-radius: 4px; padding: 4px;")
    accel_layout.addWidget(lbl_accel_mag)
    
    # 2. Sensitivity/Threshold Label
    lbl_thresh_txt = QLabel("Shot Threshold:")
    lbl_thresh_txt.setAlignment(Qt.AlignRight | Qt.AlignVCenter)
    accel_layout.addWidget(lbl_thresh_txt)

    # 3. Adjustable Spinner
    spin_threshold = QDoubleSpinBox()
    spin_threshold.setRange(0.5, 50.0) 
    spin_threshold.setSingleStep(0.5)
    spin_threshold.setValue(SHOT_THRESHOLD)
    spin_threshold.setSuffix(" m/s²")
    spin_threshold.setStyleSheet("font-size: 11pt;")
    accel_layout.addWidget(spin_threshold)

    left_layout.addLayout(accel_layout)
    # -------------------------------

    score_layout = QHBoxLayout()
    lbl_big_score = QLabel("100")
    lbl_big_score.setAlignment(Qt.AlignCenter)
    lbl_big_score.setStyleSheet("font-size: 60pt; font-weight: bold; color: #00FF00;")
    score_layout.addWidget(lbl_big_score)
    left_layout.addLayout(score_layout)
    
    lbl_status = QLabel("Not Calibrated")
    lbl_status.setAlignment(Qt.AlignCenter)
    left_layout.addWidget(lbl_status)

    btn_layout = QHBoxLayout()
    btn_calib = QPushButton("CALIBRATE")
    btn_calib.setMinimumHeight(40)
    btn_start = QPushButton("START RECORDING")
    btn_start.setMinimumHeight(40)
    
    chk_auto_shot = QCheckBox("Auto-Log Recoil")
    chk_auto_shot.setChecked(True)
    
    btn_layout.addWidget(chk_auto_shot)
    btn_layout.addWidget(btn_calib)
    btn_layout.addWidget(btn_start)
    left_layout.addLayout(btn_layout)

    batt_bar = QProgressBar()
    batt_bar.setRange(0, 100)
    batt_bar.setValue(0)
    batt_bar.setTextVisible(True)
    batt_bar.setFormat("Device Battery: %p%")
    batt_bar.setFixedHeight(25)
    batt_bar.setStyleSheet("QProgressBar { border: 2px solid grey; border-radius: 5px; text-align: center; color: black; } QProgressBar::chunk { background-color: #00FF00; }")
    left_layout.addWidget(batt_bar)
    
    main_layout.addWidget(left_widget, stretch=2)

    right_widget = QWidget()
    right_layout = QVBoxLayout(right_widget)

    stats_group = QGroupBox("Session Statistics")
    stats_layout = QVBoxLayout()
    lbl_shot_count = QLabel("Shots: 0")
    lbl_shot_count.setFont(QFont("Arial", 12))
    lbl_avg_score = QLabel("Avg Score: --")
    lbl_avg_score.setFont(QFont("Arial", 14, QFont.Bold))
    lbl_best_score = QLabel("Best Score: --")
    lbl_best_score.setFont(QFont("Arial", 12))
    lbl_best_score.setStyleSheet("color: #00FF00;")
    stats_layout.addWidget(lbl_shot_count)
    stats_layout.addWidget(lbl_avg_score)
    stats_layout.addWidget(lbl_best_score)
    stats_group.setLayout(stats_layout)
    right_layout.addWidget(stats_group)

    lbl_history_title = QLabel("Shot History")
    right_layout.addWidget(lbl_history_title)
    list_shots = QListWidget()
    list_shots.setFont(QFont("Courier New", 10)) 
    right_layout.addWidget(list_shots)

    btn_log_shot = QPushButton("MANUAL LOG (Space)")
    btn_log_shot.setMinimumHeight(50)
    btn_log_shot.setStyleSheet("background-color: #007ACC; color: white; font-weight: bold;")
    right_layout.addWidget(btn_log_shot)
    main_layout.addWidget(right_widget, stretch=1)

    shot_scores = []

    # --- CALLBACKS ---
    def update_threshold_val(val):
        global SHOT_THRESHOLD
        SHOT_THRESHOLD = val
    
    spin_threshold.valueChanged.connect(update_threshold_val)

    def change_mode():
        global SHOT_THRESHOLD, SHOT_COOLDOWN, DIFFICULTY_MULTIPLIER
        mode = cmb_mode.currentIndex()
        
        new_thresh = 2.5
        
        if mode == 0: # Target Shooting (Airsoft/Smallbore)
            new_thresh = 2.5   
            SHOT_COOLDOWN = 0.5
            DIFFICULTY_MULTIPLIER = 30.0
        elif mode == 1: # Archery
            new_thresh = 1.5   
            SHOT_COOLDOWN = 2.5    
            DIFFICULTY_MULTIPLIER = 40.0 
        elif mode == 2: # Long Range Rifle (Centerfire)
            new_thresh = 15.0  
            SHOT_COOLDOWN = 1.0   
            DIFFICULTY_MULTIPLIER = 50.0 
        elif mode == 3: # NEW: Airsoft / Dry Fire (High Sensitivity)
            new_thresh = 1.5
            SHOT_COOLDOWN = 0.2
            DIFFICULTY_MULTIPLIER = 30.0
        
        spin_threshold.setValue(new_thresh)
    
    cmb_mode.currentIndexChanged.connect(change_mode)

    def calibrate():
        global gyro_bias, accel_ref_mag, gyro_noise_std, accel_mag_noise, is_calibrated, gravity_filter
        if not ser: return
        btn_calib.setText("Sampling...")
        btn_calib.setEnabled(False)
        QApplication.processEvents()
        
        g_samples = [[], [], []]
        a_samples = [[], [], []]
        
        start = time.time()
        ser.reset_input_buffer()
        
        while time.time() - start < 3.0:
            parsed = parse_binary_packet(ser)
            if parsed:
                v, _ = parsed
                a_samples[0].append(v[0])
                a_samples[1].append(v[1])
                a_samples[2].append(v[2])
                g_samples[0].append(v[3])
                g_samples[1].append(v[4])
                g_samples[2].append(v[5])
            QApplication.processEvents() 
            
        count = len(g_samples[0])
        if count < 40:
            btn_calib.setText(f"Failed: {count}")
            btn_calib.setEnabled(True)
            return

        gyro_bias = [sum(axis)/count for axis in g_samples]
        gyro_var = [0.0]*3
        for i in range(count):
            for axis in range(3):
                gyro_var[axis] += (g_samples[axis][i] - gyro_bias[axis])**2
        gyro_noise_std = [math.sqrt(v/count) for v in gyro_var]

        mags = [math.sqrt(a_samples[0][i]**2 + a_samples[1][i]**2 + a_samples[2][i]**2) for i in range(count)]
        accel_ref_mag = sum(mags) / count
        
        mag_var = sum([(m - accel_ref_mag)**2 for m in mags])
        accel_mag_noise = math.sqrt(mag_var / count)

        # Initialize High Pass Gravity Filter
        gravity_filter = [
            sum(a_samples[0])/count,
            sum(a_samples[1])/count,
            sum(a_samples[2])/count
        ]

        if accel_mag_noise > 0.5: 
            is_calibrated = False
            btn_calib.setText("Failed: Unstable")
            btn_calib.setEnabled(True)
            return

        is_calibrated = True
        btn_calib.setText("Calibrated")
        btn_calib.setEnabled(True)
        lbl_status.setText(f"Ready | Noise: {gyro_noise_std[0]:.2f}")

    def toggle_rec():
        global is_recording, current_session_id
        if not is_recording:
            is_recording = True
            current_session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
            btn_start.setText("STOP")
            btn_start.setStyleSheet("background-color: red; color: white;")
            shot_scores.clear()
            list_shots.clear()
            update_stats_ui()
        else:
            is_recording = False
            btn_start.setText("RECORD")
            btn_start.setStyleSheet("")

    def log_shot(is_auto=False):
        if is_auto and not is_calibrated: return 

        buffer_list = list(hold_buffer)
        clean_buffer = buffer_list[:-3] if is_auto and len(buffer_list) > 3 else buffer_list
        avg_hold_score = sum(clean_buffer) / len(clean_buffer) if len(clean_buffer) > 0 else 0.0
        shot_scores.append(avg_hold_score)
        
        shot_num = len(shot_scores)
        prefix = "[A]" if is_auto else "[M]"
        list_shots.addItem(f"{prefix} #{shot_num}: {avg_hold_score:.1f}")
        list_shots.scrollToBottom()
        log_shot_to_db(avg_hold_score, is_auto)
        update_stats_ui()
        
        if not is_auto:
            btn_log_shot.setStyleSheet("background-color: #00FF00; color: black;")
            QTimer.singleShot(200, lambda: btn_log_shot.setStyleSheet("background-color: #007ACC; color: white; font-weight: bold;"))
        else:
            lbl_big_score.setStyleSheet("font-size: 60pt; font-weight: bold; color: blue;")

    def update_stats_ui():
        if not shot_scores:
            lbl_shot_count.setText("Shots: 0")
            lbl_avg_score.setText("Avg Score: --")
            lbl_best_score.setText("Best Score: --")
            return
        count = len(shot_scores)
        avg = sum(shot_scores) / count
        best = max(shot_scores)
        lbl_shot_count.setText(f"Shots: {count}")
        lbl_avg_score.setText(f"Avg Score: {avg:.1f}")
        lbl_best_score.setText(f"Best Score: {best:.1f}")
        if avg > 90: lbl_avg_score.setStyleSheet("color: #00FF00; font-size: 14pt; font-weight: bold;")
        elif avg > 70: lbl_avg_score.setStyleSheet("color: orange; font-size: 14pt; font-weight: bold;")
        else: lbl_avg_score.setStyleSheet("color: red; font-size: 14pt; font-weight: bold;")

    btn_calib.clicked.connect(calibrate)
    btn_start.clicked.connect(toggle_rec)
    btn_log_shot.clicked.connect(lambda: log_shot(False))
    shortcut = QShortcut(QKeySequence("Space"), main_window)
    shortcut.activated.connect(lambda: log_shot(False))

    def update():
        global battery_percentage, last_shot_time, prev_linear_mag
        if not ser or not ser.is_open: return

        packets_processed = 0
        latest_data = None
        
        while ser.in_waiting >= PACKET_SIZE and packets_processed < 20:
            parsed = parse_binary_packet(ser)
            if parsed:
                latest_data = parsed
                values, bat = parsed
                ax, ay, az, gx, gy, gz = values
                
                # Update Gravity Filter (Run constantly to settle filter)
                gravity_filter[0] = alpha * gravity_filter[0] + (1 - alpha) * ax
                gravity_filter[1] = alpha * gravity_filter[1] + (1 - alpha) * ay
                gravity_filter[2] = alpha * gravity_filter[2] + (1 - alpha) * az
                
                val_elev = -((gz - gyro_bias[2]) if is_calibrated else gz)
                val_wind = (gy - gyro_bias[1]) if is_calibrated else gy
                val_cant = (gx - gyro_bias[0]) if is_calibrated else gx

                elev_queue.append(val_elev)
                wind_queue.append(val_wind)
                cant_queue.append(val_cant)
                
                # --- DETECTION LOGIC START ---
                if is_recording and is_calibrated and chk_auto_shot.isChecked():
                    now = time.time()
                    mode_idx = cmb_mode.currentIndex()
                    
                    if mode_idx == 3: # NEW: Airsoft Mode (High Pass Filter)
                        # Linear Accel = Raw - Gravity
                        lin_ax = ax - gravity_filter[0]
                        lin_ay = ay - gravity_filter[1]
                        lin_az = az - gravity_filter[2]
                        
                        # Magnitude of pure vibration
                        linear_mag = math.sqrt(lin_ax**2 + lin_ay**2 + lin_az**2)
                        
                        # Jerk Calculation (Rate of change of vibration)
                        jerk = abs(linear_mag - prev_linear_mag)
                        prev_linear_mag = linear_mag

                        # Airsoft Logic: High frequency spike, low absolute threshold
                        if linear_mag > SHOT_THRESHOLD and jerk > 0.5:
                            if (now - last_shot_time > SHOT_COOLDOWN):
                                last_shot_time = now
                                log_shot(is_auto=True)
                                
                        # Display updates for Airsoft
                        lbl_accel_mag.setText(f"Vib: {linear_mag:.2f}")

                    else: # STANDARD MODES (Gravity Compensation)
                        curr_mag = math.sqrt(ax**2 + ay**2 + az**2)
                        kick_mag = abs(curr_mag - 9.81)
                        
                        if kick_mag > SHOT_THRESHOLD and (now - last_shot_time > SHOT_COOLDOWN):
                            last_shot_time = now
                            log_shot(is_auto=True)
                        
                        lbl_accel_mag.setText(f"Kick: {kick_mag:.2f}")
                else:
                    # Update label even when not recording
                    if cmb_mode.currentIndex() == 3:
                         # Linear Calc for display
                         lin_x = ax - gravity_filter[0]
                         lin_y = ay - gravity_filter[1]
                         lin_z = az - gravity_filter[2]
                         mag = math.sqrt(lin_x**2 + lin_y**2 + lin_z**2)
                         lbl_accel_mag.setText(f"Vib: {mag:.2f}")
                    else:
                         curr = math.sqrt(ax**2 + ay**2 + az**2)
                         lbl_accel_mag.setText(f"Kick: {abs(curr - 9.81):.2f}")
                # --- DETECTION LOGIC END ---

                score = calculate_score_0_to_100(values)
                score_queue.append(score)
                hold_buffer.append(score)
                
                insert_reading(score, bat, val_elev, val_wind, val_cant)
                
                packets_processed += 1
            else:
                break

        if latest_data:
            values, bat = latest_data
            battery_percentage = bat
            
            curve_elev.setData(list(elev_queue))
            curve_wind.setData(list(wind_queue))
            curve_cant.setData(list(cant_queue))
            
            current_score = score_queue[-1] 
            lbl_big_score.setText(f"{int(current_score)}")
            
            if time.time() - last_shot_time > 0.5:
                if current_score > 90: lbl_big_score.setStyleSheet("font-size: 60pt; font-weight: bold; color: #00FF00;") 
                elif current_score > 60: lbl_big_score.setStyleSheet("font-size: 60pt; font-weight: bold; color: #FFA500;") 
                else: lbl_big_score.setStyleSheet("font-size: 60pt; font-weight: bold; color: #FF0000;") 
            
            batt_bar.setValue(int(bat))
            chunk_color = "#00FF00" if bat > 50 else "#FFA500" if bat > 20 else "#FF0000"
            batt_bar.setStyleSheet(f"QProgressBar {{ border: 2px solid grey; border-radius: 5px; text-align: center; color: black; }} QProgressBar::chunk {{ background-color: {chunk_color}; }}")

    timer = QTimer()
    timer.timeout.connect(update)
    timer.start(20)

    main_window.show()
    sys.exit(app.exec_())