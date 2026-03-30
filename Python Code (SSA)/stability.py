#!/usr/bin/env python3
"""
Real-time Stability Monitor - OPTIMIZED Shot Detection
(Modified: Integrated ShotDetector class)
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
                             QComboBox, QDoubleSpinBox, QTabWidget, QFormLayout)
from PyQt5.QtGui import QKeySequence, QFont
from PyQt5.QtCore import QTimer, Qt

# ========== IMPORT DETECTOR BARU ==========
from shot_detection_optimized import ShotDetector
# ==========================================

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
SHOT_THRESHOLD = 10.0   # Ini tidak dipakai lagi, diganti detector
SHOT_COOLDOWN = 0.5     # Ini tidak dipakai lagi

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

# ========== SHOT DETECTOR GLOBAL ==========
shot_detector = None  # Akan diinisialisasi nanti
# ==========================================

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
# GANTI bagian main execution (baris terakhir) dengan ini:

if __name__ == '__main__':
    import traceback
    
    try:
        setup_database()
        
        # ========== INISIALISASI DETECTOR ==========
        shot_detector = ShotDetector(mode='airsoft')
        print("✓ Shot Detector initialized")
        # ===========================================
        
        ser = None
        try:
            print(f"Connecting to {BLUETOOTH_COM_PORT}...")
            ser = serial.Serial(BLUETOOTH_COM_PORT, BAUD_RATE, timeout=1)
            print(f"✓ Connected to {BLUETOOTH_COM_PORT}")
            time.sleep(1.5) 

            if not perform_authentication(ser):
                print("✗ Auth Failed. Exiting.")
                if ser: ser.close()
                sys.exit(1)
            
            ser.reset_input_buffer()
            print("✓ Auth Success. Buffer Cleared.")

        except Exception as e:
            print(f"✗ Connection Error: {e}")
            print("⚠️ Continuing without serial connection for UI testing...")
            ser = None  # Allow UI to run without serial

        # ========== CREATE QT APPLICATION ==========
        print("Creating Qt Application...")
        app = QApplication(sys.argv)
        print("✓ QApplication created")
        
        print("Creating Main Window...")
        main_window = QMainWindow()
        main_window.setWindowTitle('Sniper Stability Trainer (Optimized Detection)')
        main_window.resize(1000, 650)
        print("✓ Main Window created")
        
        central_widget = QWidget()
        main_window.setCentralWidget(central_widget)
        main_layout = QHBoxLayout(central_widget)
        
        # ========== LEFT PANEL ==========
        left_widget = QWidget()
        left_layout = QVBoxLayout(left_widget)
        
        lbl_mode = QLabel("Select Sport Mode:")
        lbl_mode.setFont(QFont("Arial", 10, QFont.Bold))
        left_layout.addWidget(lbl_mode)

        cmb_mode = QComboBox()
        cmb_mode.addItem("Target Shooting (Airsoft/Smallbore)")
        cmb_mode.addItem("Archery (Recurve/Compound)")
        cmb_mode.addItem("Long Range Rifle (Centerfire)")
        cmb_mode.addItem("Airsoft ")
        cmb_mode.addItem("Airsoft Dry Fire (High Sensitivity)")
        cmb_mode.setStyleSheet("font-size: 11pt; padding: 5px;")
        left_layout.addWidget(cmb_mode)

        print("Creating Plot Widget...")
        try:
            pg.setConfigOptions(useOpenGL=False)
            plot_widget = pg.PlotWidget(title="Stability Analysis (rad/s)")
            plot_widget.showGrid(x=False, y=True, alpha=0.3)
            plot_widget.addLegend(offset=(10, 10))
            
            # # --- PENYESUAIAN DI SINI ---
            # # Menentukan range Y statis dari -5 sampai 5
            # plot_widget.setYRange(-5, 5, padding=0)
            # # Opsional: Mencegah user men-scroll/zoom sumbu Y secara tidak sengaja
            # plot_widget.setMouseEnabled(x=True, y=False) 
            # # ---------------------------
            
            curve_elev = plot_widget.plot(pen=pg.mkPen('r', width=2), name='Elevation')
            curve_wind = plot_widget.plot(pen=pg.mkPen('g', width=2), name='Windage')
            curve_cant = plot_widget.plot(pen=pg.mkPen('b', width=2), name='Cant')
            left_layout.addWidget(plot_widget)
            print("✓ Plot Widget created")
        except Exception as e:
            print(f"✗ Plot Widget Error: {e}")
            print("⚠️ Continuing without plot widget...")

        # --- Display Layout ---
        display_layout = QHBoxLayout()
        
        lbl_accel_mag = QLabel("Vib: 0.00 | Jerk: 0.00")
        lbl_accel_mag.setFont(QFont("Consolas", 11, QFont.Bold))
        lbl_accel_mag.setAlignment(Qt.AlignCenter)
        lbl_accel_mag.setStyleSheet("color: #333; background-color: #EEE; border: 1px solid #CCC; border-radius: 4px; padding: 4px;")
        display_layout.addWidget(lbl_accel_mag, stretch=2)
        
        lbl_debug = QLabel("Status: Ready")
        lbl_debug.setFont(QFont("Consolas", 10))
        lbl_debug.setAlignment(Qt.AlignCenter)
        lbl_debug.setStyleSheet("color: #666; background-color: #F9F9F9; border: 1px solid #DDD; border-radius: 4px; padding: 4px;")
        display_layout.addWidget(lbl_debug, stretch=3)
        
        left_layout.addLayout(display_layout)

        score_layout = QHBoxLayout()
        lbl_big_score = QLabel("100")
        lbl_big_score.setAlignment(Qt.AlignCenter)
        lbl_big_score.setStyleSheet("font-size: 60pt; font-weight: bold; color: #00FF00;")
        score_layout.addWidget(lbl_big_score)
        left_layout.addLayout(score_layout)
        
        lbl_status = QLabel("Not Calibrated - Click CALIBRATE to start")
        lbl_status.setAlignment(Qt.AlignCenter)
        lbl_status.setStyleSheet("font-size: 12pt; color: orange;")
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

        # ========== RIGHT PANEL (MODIFIED FOR TUNING) ==========
        right_widget = QWidget()
        right_layout = QVBoxLayout(right_widget)

        # 1. Buat Tab System
        tabs = QTabWidget()
        right_layout.addWidget(tabs)

        # --- TAB 1: STATISTICS (Tampilan Lama) ---
        tab_stats = QWidget()
        stats_layout = QVBoxLayout(tab_stats)
        
        stats_group = QGroupBox("Session Statistics")
        stats_inner_layout = QVBoxLayout()
        lbl_shot_count = QLabel("Shots: 0")
        lbl_shot_count.setFont(QFont("Arial", 12))
        lbl_avg_score = QLabel("Avg Score: --")
        lbl_avg_score.setFont(QFont("Arial", 14, QFont.Bold))
        lbl_best_score = QLabel("Best Score: --")
        lbl_best_score.setFont(QFont("Arial", 12))
        lbl_best_score.setStyleSheet("color: #00FF00;")
        stats_inner_layout.addWidget(lbl_shot_count)
        stats_inner_layout.addWidget(lbl_avg_score)
        stats_inner_layout.addWidget(lbl_best_score)
        stats_group.setLayout(stats_inner_layout)
        
        stats_layout.addWidget(stats_group)
        
        lbl_history_title = QLabel("Shot History")
        stats_layout.addWidget(lbl_history_title)
        list_shots = QListWidget()
        list_shots.setFont(QFont("Courier New", 10)) 
        stats_layout.addWidget(list_shots)
        
        tabs.addTab(tab_stats, "📊 Stats")

        # --- TAB 2: TUNING (Fitur Baru) ---
        tab_tuning = QWidget()
        tuning_layout = QVBoxLayout(tab_tuning)
        
        tuning_group = QGroupBox("Detector Thresholds")
        form_layout = QFormLayout()

        # Input: Vibration Threshold
        spin_vib = QDoubleSpinBox()
        spin_vib.setRange(0.1, 20.0)
        spin_vib.setSingleStep(0.1)
        spin_vib.setValue(shot_detector.vib_threshold)
        spin_vib.setToolTip("Minimal force (m/s²) to trigger detection")
        form_layout.addRow("Vib Threshold:", spin_vib)

        # Input: Jerk Threshold
        spin_jerk = QDoubleSpinBox()
        spin_jerk.setRange(0.1, 20.0)
        spin_jerk.setSingleStep(0.1)
        spin_jerk.setValue(shot_detector.jerk_threshold)
        spin_jerk.setToolTip("Rate of change (snapiness) required")
        form_layout.addRow("Jerk Threshold:", spin_jerk)

        # Input: Spike Ratio
        spin_ratio = QDoubleSpinBox()
        spin_ratio.setRange(1.0, 10.0)
        spin_ratio.setSingleStep(0.1)
        spin_ratio.setValue(shot_detector.spike_ratio)
        spin_ratio.setToolTip("Peak signal must be X times higher than baseline")
        form_layout.addRow("Spike Ratio:", spin_ratio)

        # Input: Duration Min
        spin_dur_min = QDoubleSpinBox()
        spin_dur_min.setRange(1, 20)
        spin_dur_min.setDecimals(0)
        spin_dur_min.setValue(shot_detector.duration_min)
        form_layout.addRow("Min Duration:", spin_dur_min)

        tuning_group.setLayout(form_layout)
        tuning_layout.addWidget(tuning_group)

        # Monitor Live Values di Tab Tuning
        monitor_group = QGroupBox("Live Monitor")
        monitor_layout = QVBoxLayout()
        
        lbl_live_vib = QLabel("Cur Vib: 0.00 / Thr: 0.00")
        lbl_live_vib.setStyleSheet("font-weight: bold; font-size: 11pt;")
        
        lbl_live_jerk = QLabel("Cur Jerk: 0.00 / Thr: 0.00")
        lbl_live_jerk.setStyleSheet("font-weight: bold; font-size: 11pt;")

        # Progress bar untuk visualisasi threshold
        bar_vib_vis = QProgressBar()
        bar_vib_vis.setRange(0, 100) # Scaled 0-10 m/s^2
        bar_vib_vis.setTextVisible(False)
        bar_vib_vis.setStyleSheet("QProgressBar::chunk { background-color: #007ACC; }")

        monitor_layout.addWidget(lbl_live_vib)
        monitor_layout.addWidget(bar_vib_vis)
        monitor_layout.addWidget(lbl_live_jerk)
        
        monitor_group.setLayout(monitor_layout)
        tuning_layout.addWidget(monitor_group)
        tuning_layout.addStretch()

        tabs.addTab(tab_tuning, "🛠️ Tuning")

        # Tombol Manual Log tetap di luar Tab agar selalu ada
        btn_log_shot = QPushButton("MANUAL LOG (Space)")
        btn_log_shot.setMinimumHeight(50)
        btn_log_shot.setStyleSheet("background-color: #007ACC; color: white; font-weight: bold;")
        right_layout.addWidget(btn_log_shot)
        
        main_layout.addWidget(right_widget, stretch=1)

        shot_scores = []

        # --- TUNING LOGIC ---
        def update_detector_params():
            """Update parameter detector saat SpinBox berubah"""
            shot_detector.vib_threshold = spin_vib.value()
            shot_detector.jerk_threshold = spin_jerk.value()
            shot_detector.spike_ratio = spin_ratio.value()
            shot_detector.duration_min = int(spin_dur_min.value())
            
            # Update label monitor agar user tahu target thresholdnya
            lbl_live_vib.setText(f"Vib: 0.00 / Thr: {shot_detector.vib_threshold:.1f}")
            lbl_live_jerk.setText(f"Jerk: 0.00 / Thr: {shot_detector.jerk_threshold:.1f}")
            print(f"Params Updated: Vib={shot_detector.vib_threshold}, Jerk={shot_detector.jerk_threshold}")

        # Connect signals
        spin_vib.valueChanged.connect(update_detector_params)
        spin_jerk.valueChanged.connect(update_detector_params)
        spin_ratio.valueChanged.connect(update_detector_params)
        spin_dur_min.valueChanged.connect(update_detector_params)

        # ========== CALLBACKS ==========
        def change_mode():
            """Update detector mode based on ComboBox selection"""
            global shot_detector
            mode = cmb_mode.currentIndex()
            
            mode_map = {
                0: 'target',
                1: 'archery',
                2: 'rifle',
                3: 'airsoft',
                4: 'airsoft_dry'
            }
            
            selected_mode = mode_map.get(mode, 'airsoft')
            shot_detector.setup_thresholds(selected_mode)
            
            # --- TAMBAHAN: Update UI SpinBoxes agar sinkron ---
            spin_vib.blockSignals(True) # Cegah loop update
            spin_vib.setValue(shot_detector.vib_threshold)
            spin_jerk.setValue(shot_detector.jerk_threshold)
            spin_ratio.setValue(shot_detector.spike_ratio)
            spin_dur_min.setValue(shot_detector.duration_min)
            spin_vib.blockSignals(False)
            
            print(f"Detector mode changed to: {selected_mode}")
            lbl_debug.setText(f"Mode: {selected_mode.upper()}")
        
        cmb_mode.currentIndexChanged.connect(change_mode)

        def calibrate():
            global gyro_bias, accel_ref_mag, gyro_noise_std, accel_mag_noise, is_calibrated
            
            if not ser:
                lbl_status.setText("⚠️ No Serial Connection!")
                lbl_status.setStyleSheet("color: red; font-size: 12pt;")
                return
                
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
            print(f"Calibration collected {count} samples")
            
            if count < 40:
                btn_calib.setText(f"Failed: Only {count} samples")
                btn_calib.setEnabled(True)
                lbl_status.setText(f"⚠️ Calibration Failed: {count} samples")
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

            # Calibrate shot detector
            accel_samples = [(a_samples[0][i], a_samples[1][i], a_samples[2][i]) 
                            for i in range(count)]
            shot_detector.calibrate_gravity(accel_samples)
            print("✓ Shot Detector calibrated")

            if accel_mag_noise > 0.5: 
                is_calibrated = False
                btn_calib.setText("Failed: Too Unstable")
                btn_calib.setEnabled(True)
                lbl_status.setText("⚠️ Too much movement during calibration")
                lbl_status.setStyleSheet("color: red; font-size: 12pt;")
                return

            is_calibrated = True
            btn_calib.setText("✓ Calibrated")
            btn_calib.setEnabled(True)
            lbl_status.setText(f"✓ Ready | Noise: {gyro_noise_std[0]:.3f} rad/s")
            lbl_status.setStyleSheet("color: green; font-size: 12pt;")
            lbl_debug.setText("Status: Calibrated ✓")
            print("✓ Calibration complete")

        def toggle_rec():
            global is_recording, current_session_id
            if not is_recording:
                if not is_calibrated:
                    lbl_status.setText("⚠️ Please CALIBRATE first!")
                    return
                    
                is_recording = True
                current_session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
                btn_start.setText("STOP RECORDING")
                btn_start.setStyleSheet("background-color: red; color: white; font-weight: bold;")
                shot_scores.clear()
                list_shots.clear()
                update_stats_ui()
                print(f"✓ Recording started: {current_session_id}")
            else:
                is_recording = False
                btn_start.setText("START RECORDING")
                btn_start.setStyleSheet("")
                print(f"✓ Recording stopped: {len(shot_scores)} shots")

        def log_shot(is_auto=False):
            if is_auto and not is_calibrated: return 

            buffer_list = list(hold_buffer)
            clean_buffer = buffer_list[:-3] if is_auto and len(buffer_list) > 3 else buffer_list
            avg_hold_score = sum(clean_buffer) / len(clean_buffer) if len(clean_buffer) > 0 else 0.0
            shot_scores.append(avg_hold_score)
            
            shot_num = len(shot_scores)
            prefix = "[AUTO]" if is_auto else "[MANUAL]"
            timestamp = datetime.now().strftime("%H:%M:%S")
            list_shots.addItem(f"{prefix} #{shot_num}: {avg_hold_score:.1f} @ {timestamp}")
            list_shots.scrollToBottom()
            log_shot_to_db(avg_hold_score, is_auto)
            update_stats_ui()
            
            print(f"{'🎯' if is_auto else '✋'} Shot logged: {avg_hold_score:.1f}")
            
            if not is_auto:
                btn_log_shot.setStyleSheet("background-color: #00FF00; color: black; font-weight: bold;")
                QTimer.singleShot(200, lambda: btn_log_shot.setStyleSheet("background-color: #007ACC; color: white; font-weight: bold;"))
            else:
                lbl_big_score.setStyleSheet("font-size: 60pt; font-weight: bold; color: blue;")
                QTimer.singleShot(300, lambda: None)  # Reset handled in update()

        def update_stats_ui():
            if not shot_scores:
                lbl_shot_count.setText("Shots: 0")
                lbl_avg_score.setText("Avg: --")
                lbl_best_score.setText("Best: --")
                return
            count = len(shot_scores)
            avg = sum(shot_scores) / count
            best = max(shot_scores)
            lbl_shot_count.setText(f"Shots: {count}")
            lbl_avg_score.setText(f"Avg: {avg:.1f}")
            lbl_best_score.setText(f"Best: {best:.1f}")
            
            if avg > 90: 
                lbl_avg_score.setStyleSheet("color: #00FF00; font-size: 14pt; font-weight: bold;")
            elif avg > 70: 
                lbl_avg_score.setStyleSheet("color: orange; font-size: 14pt; font-weight: bold;")
            else: 
                lbl_avg_score.setStyleSheet("color: red; font-size: 14pt; font-weight: bold;")

        btn_calib.clicked.connect(calibrate)
        btn_start.clicked.connect(toggle_rec)
        btn_log_shot.clicked.connect(lambda: log_shot(False))
        
        shortcut = QShortcut(QKeySequence("Space"), main_window)
        shortcut.activated.connect(lambda: log_shot(False))

        # Tambahkan di bagian globals atau di dalam main sebelum loop update
        gyro_speed_history = deque([1.0] * 10, maxlen=15) # Menyimpan 10 sampel terakhir (~200ms)
        
        # ========== UPDATE LOOP ==========
        def update():
            global battery_percentage, last_shot_time
            
            if not ser or not ser.is_open:
                # No serial - show test data
                if is_calibrated:
                    lbl_accel_mag.setText("Vib: 0.15 | Jerk: 0.08")
                    lbl_debug.setText("⚠️ No Serial - Test Mode")
                return

            packets_processed = 0
            latest_data = None
            
            try:
                while ser.in_waiting >= PACKET_SIZE and packets_processed < 20:
                    parsed = parse_binary_packet(ser)
                    if parsed:
                        latest_data = parsed
                        values, bat = parsed
                        ax, ay, az, gx, gy, gz = values
                        
                        val_elev = ((gy - gyro_bias[2]) if is_calibrated else gy)
                        val_wind = (gz - gyro_bias[1]) if is_calibrated else gz
                        val_cant = (gx - gyro_bias[0]) if is_calibrated else gx

                        elev_queue.append(val_elev)
                        wind_queue.append(val_wind)
                        cant_queue.append(val_cant)
                        
                        # 1. Hitung kecepatan rotasi saat ini (magnitudo gyro)
                        # val_elev, val_wind, val_cant sudah dikurangi bias di baris sebelumnya
                        current_gyro_speed = math.sqrt(val_elev**2 + val_wind**2 + val_cant**2)
                        gyro_speed_history.append(current_gyro_speed)
                        
                        # Shot detection
                        if is_recording and is_calibrated and chk_auto_shot.isChecked():
                            is_shot, debug_info = shot_detector.detect_shot(ax, ay, az)
                            
                            if is_shot:
                                # 1. Hitung total rotasi saat ini (Elevation, Windage, Cant)
                                # Kita ambil dari data gyro yang sudah dikurangi bias
                                total_rotation = abs(val_elev) + abs(val_wind) + abs(val_cant)
                                
                                # Cek rata-rata pergerakan dalam buffer (Steady-State Gate)
                                avg_stability = sum(gyro_speed_history) / len(gyro_speed_history)
                                
                                # 2. Syarat Tambahan: Tembakan hanya valid jika unit tidak sedang "berayun" lebar
                                # Jika total_rotation > 1.5 rad/s, kemungkinan itu gerakan berdiri atau mengokang
                                if total_rotation < 1.5 and avg_stability < 0.5: 
                                    log_shot(is_auto=True)
                                    lbl_debug.setText(
                                        f"🎯 SHOT! Spike:{debug_info.get('spike_ratio', 0):.1f}x "
                                        f"Dur:{debug_info.get('duration', 0)}"
                                    )
                                else:
                                    lbl_debug.setStyleSheet("color: white; background-color: #FF5555; border: 2px solid #CC0000; border-radius: 4px; padding: 4px; font-weight: bold;")
                                    QTimer.singleShot(800, lambda: lbl_debug.setStyleSheet("color: #666; background-color: #F9F9F9; border: 1px solid #DDD; border-radius: 4px; padding: 4px;"))
                            else:
                                reason_map = {
                                    'cooldown': '⏱️ Cooldown',
                                    'below_threshold': '📉 Too weak',
                                    'slow_movement': '🐌 Too slow',
                                    'no_spike': '📊 No spike',
                                    'too_short': '⚡ Too short',
                                    'too_long': '⏳ Too long',
                                    'inconsistent_jerk': '〰️ Inconsistent'
                                }
                                reason = reason_map.get(debug_info.get('reason', ''), '👁️ Monitoring')
                                lbl_debug.setText(reason)
                            
                            linear = debug_info.get('linear', 0)
                            jerk = debug_info.get('jerk', 0)
                            lbl_accel_mag.setText(f"Vib: {linear:.2f} | Jerk: {jerk:.2f}")
                            
                            # Update Tuning Monitor UI
                            if tabs.currentIndex() == 1: # Hanya update jika Tab Tuning aktif (hemat resource)
                                lbl_live_vib.setText(f"Cur Vib: {linear:.2f} / Thr: {shot_detector.vib_threshold:.1f}")
                                lbl_live_jerk.setText(f"Cur Jerk: {jerk:.2f} / Thr: {shot_detector.jerk_threshold:.1f}")
                                
                                # Visualisasi bar (Scale x10 agar terlihat jelas)
                                val_bar = int(linear * 10)
                                bar_vib_vis.setValue(min(100, val_bar))
                                
                                # Ubah warna bar jika melewati threshold
                                if linear > shot_detector.vib_threshold:
                                    bar_vib_vis.setStyleSheet("QProgressBar::chunk { background-color: #FF0000; }")
                                else:
                                    bar_vib_vis.setStyleSheet("QProgressBar::chunk { background-color: #007ACC; }")
                        else:
                            _, debug_info = shot_detector.detect_shot(ax, ay, az)
                            linear = debug_info.get('linear', 0)
                            jerk = debug_info.get('jerk', 0)
                            lbl_accel_mag.setText(f"Vib: {linear:.2f} | Jerk: {jerk:.2f}")

                        score = calculate_score_0_to_100(values)
                        score_queue.append(score)
                        hold_buffer.append(score)
                        
                        insert_reading(score, bat, val_elev, val_wind, val_cant)
                        
                        packets_processed += 1
                    else:
                        break
            except Exception as e:
                print(f"Update error: {e}")
                traceback.print_exc()

            if latest_data:
                values, bat = latest_data
                battery_percentage = bat
                
                try:
                    curve_elev.setData(list(elev_queue))
                    curve_wind.setData(list(wind_queue))
                    curve_cant.setData(list(cant_queue))
                except Exception as e:
                    print(f"Plot update error: {e}")
                
                current_score = score_queue[-1] 
                lbl_big_score.setText(f"{int(current_score)}")
                
                if time.time() - last_shot_time > 0.5:
                    if current_score > 90: 
                        lbl_big_score.setStyleSheet("font-size: 60pt; font-weight: bold; color: #00FF00;") 
                    elif current_score > 60: 
                        lbl_big_score.setStyleSheet("font-size: 60pt; font-weight: bold; color: #FFA500;") 
                    else: 
                        lbl_big_score.setStyleSheet("font-size: 60pt; font-weight: bold; color: #FF0000;") 
                
                batt_bar.setValue(int(bat))
                chunk_color = "#00FF00" if bat > 50 else "#FFA500" if bat > 20 else "#FF0000"
                batt_bar.setStyleSheet(f"QProgressBar {{ border: 2px solid grey; border-radius: 5px; text-align: center; color: black; }} QProgressBar::chunk {{ background-color: {chunk_color}; }}")

        timer = QTimer()
        timer.timeout.connect(update)
        timer.start(20)  # 50Hz update rate

        print("✓ All widgets created successfully")
        print("Showing main window...")
        main_window.show()
        print("✓ Window shown")
        
        print("\n" + "="*50)
        print("🚀 APPLICATION READY")
        print("="*50)
        print("1. Click CALIBRATE (hold device steady for 3 sec)")
        print("2. Click START RECORDING")
        print("3. Fire your airsoft gun")
        print("4. Watch for auto-detection or press SPACE for manual log")
        print("="*50 + "\n")
        
        exit_code = app.exec_()
        
        if ser and ser.is_open:
            ser.close()
            print("✓ Serial connection closed")
            
        sys.exit(exit_code)
        
    except Exception as e:
        print("\n" + "="*50)
        print("❌ CRITICAL ERROR")
        print("="*50)
        print(f"Error: {e}")
        print("\nFull traceback:")
        traceback.print_exc()
        print("="*50)
        sys.exit(1)