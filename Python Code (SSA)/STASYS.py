#!/usr/bin/env python3
"""
STASYS Receiver v3.1 - Hardcore Micro-Tremor Scoring
Features:
- **Tuned Scoring**: Penalties increased by ~8x.
  - Designed for engineering-grade analysis of micro-movements.
  - Scores of 90+ now require near-mechanical perfection.
- Auto-Simulation Mode.
- Live Monitor.
- Multi-Phase Shot Trace.
"""

import sys
import serial
import serial.tools.list_ports
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
                             QComboBox, QDoubleSpinBox, QGridLayout, QFrame, QMessageBox)
from PyQt5.QtGui import QKeySequence, QFont, QColor
from PyQt5.QtCore import QTimer, Qt

# ================= CONFIGURATION =================
BLUETOOTH_COM_PORT = 'COM7' 
BAUD_RATE = 115200

# Timing & Protocol
PACKET_SIZE = 30
DT = 0.01 # 10ms (100Hz from Firmware)

# --- MANTIS-LIKE DETECTION SETTINGS ---
STABILITY_WINDOW_MS = 200    
STABILITY_GYRO_LIMIT = 4.0   

HOLD_DURATION_IDX = 150      
PRESS_DURATION_IDX = 30      
RECOIL_DURATION_IDX = 10     
TOTAL_HISTORY_NEEDED = HOLD_DURATION_IDX + RECOIL_DURATION_IDX + 10

DEFAULT_ACCEL_THRESH = 8.0   
DEFAULT_PIEZO_MIN = 100.0    
PIEZO_MAX_LIMIT = 1000.0      

# --- SCORING TUNING (HARDCORE MODE) ---
# Previous values: Travel=150, Jerk=1000
# New values amplify micro-movements significantly.

# 1. Travel Penalty: Penalizes the total length of the path during the press.
#    At 1200, a cumulative drift of just 0.05 degrees drops the score by 60 points.
SCORE_PENALTY_TRAVEL = 1200.0 

# 2. Jerk Penalty: Penalizes the single largest jump (slap/flinch).
#    At 5000, a single micro-spasm destroys the score.
SCORE_PENALTY_JERK = 5000.0   

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_FILE = os.path.join(SCRIPT_DIR, 'shooter_data.db')
SECRET_KEY = b"12ebaf10h12fa9123z21sti"

# ================= MOCK SERIAL FOR TESTING =================
class MockSerial:
    def __init__(self):
        self.is_open = True
        self.in_waiting = 0
        self.buffer = b""
        self.last_update = time.time()
        
        # Sim state
        self.x = 0
        self.y = 0
        self.noise_seed = 0

    def write(self, data):
        pass

    def readline(self):
        return b"READY\n"

    def read(self, size):
        if len(self.buffer) >= size:
            ret = self.buffer[:size]
            self.buffer = self.buffer[size:]
            self.in_waiting = len(self.buffer)
            return ret
        return b""

    def update_sim(self):
        # Generate 100Hz packets
        now = time.time()
        if now - self.last_update > 0.01:
            self.last_update = now
            self.in_waiting += PACKET_SIZE
            
            # Generate fake sensor data
            self.noise_seed += 0.1
            
            # Slight drift (Gyro)
            gx = math.sin(self.noise_seed * 0.5) * 0.5 + random.uniform(-0.1, 0.1)
            gy = math.cos(self.noise_seed * 0.3) * 0.5 + random.uniform(-0.1, 0.1)
            gz = 0.0
            
            # Accel (Gravity + Noise)
            ax = random.uniform(-0.2, 0.2)
            ay = random.uniform(-0.2, 0.2)
            az = 9.8
            
            piezo = int(random.uniform(0, 50))
            bat = 85
            
            # Pack
            payload = struct.pack('<ffffffHB', ax, ay, az, gx, gy, gz, piezo, bat)
            
            # Checksum
            calc_sum = 0
            for b in payload: calc_sum ^= b
            
            self.buffer += b'\xAA\xBB' + payload + bytes([calc_sum])

# ================= CORE LOGIC =================

def setup_database():
    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()
    cur.execute('''CREATE TABLE IF NOT EXISTS shots (
            id INTEGER PRIMARY KEY AUTOINCREMENT, 
            timestamp DATETIME, 
            session_id TEXT, 
            score REAL, 
            cant REAL, 
            mode TEXT)''')
    conn.commit()
    conn.close()

def log_shot_db(session_id, score, cant, mode):
    conn = sqlite3.connect(DB_FILE)
    cur = conn.cursor()
    cur.execute('INSERT INTO shots(timestamp, session_id, score, cant, mode) VALUES(?,?,?,?,?)',
        (datetime.now(), session_id, score, cant, mode))
    conn.commit()
    conn.close()

def parse_binary_packet(ser):
    try:
        # Mock Serial update hook
        if hasattr(ser, 'update_sim'):
            ser.update_sim()

        if ser.in_waiting >= PACKET_SIZE:
            header = ser.read(2)
            if header != b'\xAA\xBB': 
                return None
            
            raw_payload = ser.read(PACKET_SIZE - 2)
            if len(raw_payload) != PACKET_SIZE - 2: return None
            
            received_checksum = raw_payload[-1]
            data = raw_payload[:-1]
            
            calc_sum = 0
            for b in data: calc_sum ^= b
            if calc_sum != received_checksum: return None

            unpacked = struct.unpack('<ffffffHB', data)
            return list(unpacked) 
    except Exception as e:
        print(e)
    return None

def perform_auth(ser):
    if hasattr(ser, 'update_sim'): return True

    print("Handshaking...")
    try:
        start = time.time()
        got_ready = False

        while time.time() - start < 5.0:
            if ser.in_waiting:
                line = ser.readline().decode('utf-8', errors='ignore').strip()

                if not got_ready:
                    # Wait for READY signal (firmware may also send version string)
                    if "READY" in line.upper():
                        got_ready = True
                        print(f"  <- {line}")
                        # Flush any remaining lines (like FIRMWARE_VERSION)
                        while ser.in_waiting:
                            extra = ser.readline().decode('utf-8', errors='ignore').strip()
                            print(f"  <- (extra) {extra}")
                            if not extra:
                                break
                        # Send challenge
                        c = ''.join(random.choices(string.ascii_letters + string.digits, k=16))
                        print(f"  -> Challenge: {c}")
                        ser.write(f"{c}\n".encode('utf-8'))
                else:
                    # Already got READY — wait for hash response
                    if line and len(line) == 64:  # SHA256 hex is always 64 chars
                        print(f"  <- Response hash: {line[:16]}...")
                        exp = hashlib.sha256((c + SECRET_KEY.decode('utf-8')).encode('utf-8')).hexdigest()
                        if hmac.compare_digest(line.lower(), exp.lower()):
                            print("  Auth SUCCESS!")
                            return True
                        else:
                            print(f"  Auth FAILED (hash mismatch). Retrying...")
                            got_ready = False  # Reset, wait for next READY
                            start = time.time()  # Reset timeout

            time.sleep(0.01)
    except Exception as e:
        print(f"Auth error: {e}")
    return False

class ShotDetector:
    def __init__(self):
        self.accel_thresh = DEFAULT_ACCEL_THRESH
        self.piezo_thresh = DEFAULT_PIEZO_MIN
        self.trigger_mode = 0 
        
        self.is_calibrated = False
        self.gyro_bias = [0,0,0]
        self.gravity_ref = [0,0,1] 

        self.state = "IDLE" 
        self.state_timer = 0
        self.gather_counter = 0 
        self.last_trigger_piezo = 0

        self.buf_size = TOTAL_HISTORY_NEEDED * 2 
        self.trace_x = deque([0.0]*self.buf_size, maxlen=self.buf_size)
        self.trace_y = deque([0.0]*self.buf_size, maxlen=self.buf_size)
        self.curr_x = 0.0
        self.curr_y = 0.0
        
        self.prev_ax = 0; self.prev_ay = 0; self.prev_az = 0

    def calibrate(self, samples):
        cnt = len(samples)
        if cnt < 10: return False
        self.gyro_bias = [
            sum(s[3] for s in samples)/cnt,
            sum(s[4] for s in samples)/cnt,
            sum(s[5] for s in samples)/cnt
        ]
        self.curr_x = 0.0; self.curr_y = 0.0
        self.trace_x.clear(); self.trace_y.clear()
        self.trace_x.extend([0.0]*self.buf_size)
        self.trace_y.extend([0.0]*self.buf_size)
        self.is_calibrated = True
        return True

    def process(self, packet):
        raw_ax, raw_ay, raw_az, raw_gx, raw_gy, raw_gz, piezo, bat = packet
        
        if self.is_calibrated:
            gx = raw_gx - self.gyro_bias[0]
            gy = raw_gy - self.gyro_bias[1]
            gz = raw_gz - self.gyro_bias[2]
        else:
            gx, gy, gz = raw_gx, raw_gy, raw_gz

        vel_x = -gz 
        vel_y = -gx 
        
        self.curr_x += vel_x * DT
        self.curr_y += vel_y * DT
        
        self.trace_x.append(self.curr_x)
        self.trace_y.append(self.curr_y)

        rot_mag = math.sqrt(gx**2 + gy**2 + gz**2)
        j_x = (raw_ax - self.prev_ax); j_y = (raw_ay - self.prev_ay); j_z = (raw_az - self.prev_az)
        jerk_mag = math.sqrt(j_x**2 + j_y**2 + j_z**2) / DT
        self.prev_ax = raw_ax; self.prev_ay = raw_ay; self.prev_az = raw_az

        shot_data = None
        
        if self.state == "COOLDOWN":
            self.state_timer -= DT
            if self.state_timer <= 0:
                self.state = "IDLE"

        elif self.state == "IDLE":
            if rot_mag < STABILITY_GYRO_LIMIT:
                self.state = "ARMING"
                self.state_timer = 0

        elif self.state == "ARMING":
            if rot_mag > STABILITY_GYRO_LIMIT:
                self.state = "IDLE"
            else:
                self.state_timer += DT * 1000
                if self.state_timer >= STABILITY_WINDOW_MS:
                    self.state = "ARMED"
        
        elif self.state == "ARMED":
            triggered = False
            if self.trigger_mode == 1: 
                if jerk_mag > (self.accel_thresh * 1.5): triggered = True
            else: 
                if piezo >= self.piezo_thresh and piezo <= PIEZO_MAX_LIMIT:
                     if rot_mag < 6.0: triggered = True
            
            if triggered:
                self.last_trigger_piezo = piezo
                self.state = "POST_GATHER"
                self.gather_counter = RECOIL_DURATION_IDX
            
            if rot_mag > (STABILITY_GYRO_LIMIT * 3.0): self.state = "IDLE"
        
        elif self.state == "POST_GATHER":
            self.gather_counter -= 1
            if self.gather_counter <= 0:
                shot_data = self.analyze_shot()
                self.state = "COOLDOWN"
                self.state_timer = 0.5 

        return shot_data, bat, rot_mag, jerk_mag, piezo

    def analyze_shot(self):
        hist_len = len(self.trace_x)
        total_needed = HOLD_DURATION_IDX + RECOIL_DURATION_IDX
        if hist_len < total_needed: return None
        
        full_x = list(self.trace_x)
        full_y = list(self.trace_y)
        
        idx_recoil_end = len(full_x)
        idx_break = idx_recoil_end - RECOIL_DURATION_IDX
        idx_press_start = idx_break - PRESS_DURATION_IDX
        idx_hold_start = idx_break - HOLD_DURATION_IDX
        if idx_hold_start < 0: return None
        
        break_x = full_x[idx_break]
        break_y = full_y[idx_break]
        
        def get_norm_segment(start, end):
            seg_x = [x - break_x for x in full_x[start:end]]
            seg_y = [y - break_y for y in full_y[start:end]]
            return seg_x, seg_y

        hold_x, hold_y = get_norm_segment(idx_hold_start, idx_press_start)
        press_x, press_y = get_norm_segment(idx_press_start, idx_break + 1) 
        recoil_x, recoil_y = get_norm_segment(idx_break, idx_recoil_end)
        
        # --- HARDCORE SCORING ALGORITHM (Path Efficiency) ---
        
        deltas = []
        for i in range(1, len(press_x)):
            dx = press_x[i] - press_x[i-1]
            dy = press_y[i] - press_y[i-1]
            dist = math.sqrt(dx*dx + dy*dy)
            deltas.append(dist)
        
        if not deltas: 
            score = 100.0 
        else:
            # Sum of all micro-movements during the press
            total_travel = sum(deltas)
            
            # Max single jump distance (slap/flinch)
            peak_jerk = max(deltas)
            
            # Heavily weighted penalties
            penalty_travel = total_travel * SCORE_PENALTY_TRAVEL
            penalty_jerk = peak_jerk * SCORE_PENALTY_JERK
            
            raw_score = 100.0 - (penalty_travel + penalty_jerk)
            score = max(0.0, min(100.0, raw_score))

        return { "score": score, "hold": (hold_x, hold_y), "press": (press_x, press_y), 
                 "recoil": (recoil_x, recoil_y), "piezo": self.last_trigger_piezo }

# ================= UI CLASSES =================

class LiveMonitorWindow(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("Live Aim Monitor")
        self.resize(600, 600)
        self.setStyleSheet("background-color: #000;")
        cw = QWidget(); self.setCentralWidget(cw); lay = QVBoxLayout(cw)
        
        head_layout = QHBoxLayout()
        lbl_head = QLabel("REAL-TIME TRACE")
        lbl_head.setStyleSheet("color: #0F0; font-weight: bold; font-size: 14pt;")
        self.lbl_calib_status = QLabel("UNCALIBRATED")
        self.lbl_calib_status.setStyleSheet("color: #FF5500; font-weight: bold; font-size: 10pt; background: #331100; padding: 3px;")
        
        head_layout.addWidget(lbl_head); head_layout.addStretch(); head_layout.addWidget(self.lbl_calib_status)
        lay.addLayout(head_layout)

        self.plot = pg.PlotWidget()
        self.plot.setBackground('k')
        self.plot.showGrid(x=True, y=True, alpha=0.3)
        self.plot.setAspectLocked(True)
        self.plot.setXRange(-0.05, 0.05); self.plot.setYRange(-0.05, 0.05)
        
        self.trace_curve = self.plot.plot(pen=pg.mkPen('#00FF00', width=3))
        self.center_ref = self.plot.plot(pen=None, symbol='+', symbolSize=20, symbolBrush='#555')
        self.cursor = self.plot.plot(pen=None, symbol='o', symbolSize=10, symbolBrush='r')
        lay.addWidget(self.plot)

    def update_data(self, x_data, y_data, is_calibrated):
        if is_calibrated:
            self.lbl_calib_status.setText("CALIBRATED")
            self.lbl_calib_status.setStyleSheet("color: #00FF00; background: #002200; padding: 3px;")
        else:
            self.lbl_calib_status.setText("UNCALIBRATED")
            self.lbl_calib_status.setStyleSheet("color: #FF5500; background: #331100; padding: 3px;")

        self.trace_curve.setData(x_data, y_data)
        self.center_ref.setData([0], [0]) 
        if x_data: self.cursor.setData([x_data[-1]], [y_data[-1]])

class MainWindow(QMainWindow):
    def __init__(self, serial_port):
        super().__init__()
        self.ser = serial_port
        self.detector = ShotDetector()
        self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self._session_scores = []
        self._session_viewer = None
        self.live_window = None
        self.init_ui()
        self.calib_buffer = []
        self.calibrating = False
        self.timer = QTimer()
        self.timer.timeout.connect(self.update_loop)
        self.timer.start(10)

    def init_ui(self):
        self.setWindowTitle('STASYS PRO - Shot Analysis')
        self.resize(1200, 800)
        self.setStyleSheet("background-color: #222; color: #EEE;")
        central = QWidget(); self.setCentralWidget(central); main_layout = QHBoxLayout(central)
        
        # LEFT PANEL
        left_panel = QFrame(); left_panel.setFrameShape(QFrame.StyledPanel); left_layout = QVBoxLayout(left_panel)
        lbl_title = QLabel("STASYS PRO"); lbl_title.setStyleSheet("font-size: 20pt; font-weight: bold; color: #00FF00;")
        left_layout.addWidget(lbl_title)
        
        self.cmb_mode = QComboBox(); self.cmb_mode.addItems(["Dry Fire (Piezo 400-900)", "Live Fire (Recoil Only)"])
        self.cmb_mode.setStyleSheet("background: #444; padding: 5px;")
        self.cmb_mode.currentIndexChanged.connect(self.change_mode)
        left_layout.addWidget(QLabel("Detection Mode:")); left_layout.addWidget(self.cmb_mode)
        
        grid_thresh = QGridLayout()
        self.spin_piezo = QDoubleSpinBox(); self.spin_piezo.setRange(0, 4095); self.spin_piezo.setValue(DEFAULT_PIEZO_MIN)
        self.spin_jerk = QDoubleSpinBox(); self.spin_jerk.setRange(0, 200); self.spin_jerk.setValue(DEFAULT_ACCEL_THRESH)
        for s in [self.spin_piezo, self.spin_jerk]:
            s.setStyleSheet("background: #444; color: white;")
            s.valueChanged.connect(self.update_thresholds)
        grid_thresh.addWidget(QLabel("Piezo Min:"), 0, 0); grid_thresh.addWidget(self.spin_piezo, 0, 1)
        grid_thresh.addWidget(QLabel("Jerk (G):"), 1, 0); grid_thresh.addWidget(self.spin_jerk, 1, 1)
        left_layout.addLayout(grid_thresh)
        
        self.lbl_status = QLabel("DISCONNECTED"); self.lbl_status.setAlignment(Qt.AlignCenter)
        self.lbl_status.setStyleSheet("background: #555; font-size: 14pt; font-weight: bold; border-radius: 5px; padding: 10px;")
        left_layout.addWidget(self.lbl_status)
        
        self.btn_calib = QPushButton("CALIBRATE (Hold Steady)"); self.btn_calib.setStyleSheet("background: #007ACC; padding: 10px; font-weight: bold;")
        self.btn_calib.clicked.connect(self.start_calibration)
        left_layout.addWidget(self.btn_calib)
        
        self.btn_live_mon = QPushButton("OPEN LIVE MONITOR"); self.btn_live_mon.setStyleSheet("background: #444; border: 1px solid #0F0; color: #0F0; padding: 10px; font-weight: bold; margin-top: 20px;")
        self.btn_live_mon.clicked.connect(self.toggle_live_window)
        left_layout.addWidget(self.btn_live_mon)
        
        left_layout.addStretch()
        self.lbl_telem = QLabel("Jerk: 0\nPiezo: 0\nRot: 0"); self.lbl_telem.setStyleSheet("font-family: Courier; font-size: 10pt;")
        left_layout.addWidget(self.lbl_telem)
        main_layout.addWidget(left_panel, 1)
        
        # CENTER PANEL
        center_panel = QVBoxLayout()
        self.plot = pg.PlotWidget(title="Shot Trace (Red=Hold, Yellow=Press, Cyan=Recoil)")
        self.plot.setBackground('#111'); self.plot.showGrid(x=True, y=True, alpha=0.3)
        self.plot.setAspectLocked(True)
        # Tightened the Zoom to see micro-movements
        self.plot.setXRange(-0.05, 0.05); self.plot.setYRange(-0.05, 0.05)
        
        self.curve_hold = self.plot.plot(pen=pg.mkPen('r', width=2))
        self.curve_press = self.plot.plot(pen=pg.mkPen('y', width=3))
        self.curve_recoil = self.plot.plot(pen=pg.mkPen('c', width=2))
        self.hit_marker = self.plot.plot(pen=pg.mkPen('w', width=1), symbol='o', symbolSize=15, symbolBrush=pg.mkBrush(255, 0, 0, 200))
        self.live_curve = self.plot.plot(pen=pg.mkPen('#444', width=1, style=Qt.DotLine))
        self.cursor = self.plot.plot(pen=None, symbol='+', symbolSize=15, symbolBrush='r')
        for r in [0.01, 0.02, 0.03]:
            circle = pg.QtWidgets.QGraphicsEllipseItem(-r, -r, r*2, r*2)
            circle.setPen(pg.mkPen('#333')); self.plot.addItem(circle)
        center_panel.addWidget(self.plot)
        
        self.lbl_big_score = QLabel("--"); self.lbl_big_score.setAlignment(Qt.AlignCenter)
        self.lbl_big_score.setStyleSheet("font-size: 60pt; color: #555; font-weight: bold;")
        center_panel.addWidget(self.lbl_big_score)
        main_layout.addLayout(center_panel, 3)
        
        # RIGHT PANEL
        right_panel = QVBoxLayout()
        right_panel.addWidget(QLabel("Session History"))
        self.list_history = QListWidget(); self.list_history.setStyleSheet("background: #333; font-size: 12pt;")
        right_panel.addWidget(self.list_history)

        stats_layout = QHBoxLayout()
        self.lbl_shot_count = QLabel("Shots: 0"); self.lbl_shot_count.setStyleSheet("color: #AAA; font-size: 10pt;")
        self.lbl_avg_score = QLabel("Avg: --"); self.lbl_avg_score.setStyleSheet("color: #AAA; font-size: 10pt;")
        stats_layout.addWidget(self.lbl_shot_count); stats_layout.addWidget(self.lbl_avg_score)
        right_panel.addLayout(stats_layout)

        btn_row = QHBoxLayout()
        self.btn_reset = QPushButton("New Session"); self.btn_reset.setStyleSheet("background: #444; padding: 5px;")
        self.btn_reset.clicked.connect(self.reset_session)
        self.btn_sessions = QPushButton("View Sessions"); self.btn_sessions.setStyleSheet("background: #007ACC; color: white; padding: 5px;")
        self.btn_sessions.clicked.connect(self.open_session_viewer)
        btn_row.addWidget(self.btn_reset); btn_row.addWidget(self.btn_sessions)
        right_panel.addLayout(btn_row)
        main_layout.addLayout(right_panel, 1)

    def change_mode(self):
        self.detector.trigger_mode = self.cmb_mode.currentIndex()
        if self.detector.trigger_mode == 1:
             self.spin_jerk.setValue(15.0); self.spin_piezo.setValue(4000)
        else:
             self.spin_jerk.setValue(DEFAULT_ACCEL_THRESH); self.spin_piezo.setValue(DEFAULT_PIEZO_MIN)

    def update_thresholds(self):
        self.detector.accel_thresh = self.spin_jerk.value(); self.detector.piezo_thresh = self.spin_piezo.value()

    def start_calibration(self):
        self.calib_buffer = []; self.calibrating = True
        self.btn_calib.setText("Calibrating... DO NOT MOVE"); self.btn_calib.setStyleSheet("background: #FFA500; color: black;")

    def reset_session(self):
        self.list_history.clear(); self.session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
        self._session_scores = []
        self.lbl_big_score.setText("--"); self.lbl_shot_count.setText("Shots: 0"); self.lbl_avg_score.setText("Avg: --")
        self.curve_hold.clear(); self.curve_press.clear(); self.curve_recoil.clear(); self.hit_marker.clear()

    def open_session_viewer(self):
        try:
            from STASYS_REPORTCARD import SessionViewer
            if not hasattr(self, '_session_viewer') or self._session_viewer is None:
                self._session_viewer = SessionViewer()
            self._session_viewer.show()
            self._session_viewer.raise_()
        except Exception as e:
            print(f"Failed to open session viewer: {e}")

    def toggle_live_window(self):
        if self.live_window is None: self.live_window = LiveMonitorWindow()
        if self.live_window.isVisible():
            self.live_window.hide(); self.btn_live_mon.setText("OPEN LIVE MONITOR")
        else:
            self.live_window.show(); self.btn_live_mon.setText("CLOSE LIVE MONITOR")

    def update_loop(self):
        count = 0
        while (hasattr(self.ser, 'update_sim') or self.ser.in_waiting >= PACKET_SIZE) and count < 10:
            count += 1
            pkt = parse_binary_packet(self.ser)
            if not pkt: continue
            
            if self.calibrating:
                self.calib_buffer.append(pkt)
                if len(self.calib_buffer) >= 100: 
                    if self.detector.calibrate(self.calib_buffer):
                        self.calibrating = False; self.btn_calib.setText("CALIBRATED"); self.btn_calib.setStyleSheet("background: #007ACC;")
                    else:
                        self.calib_buffer = [] 
                continue

            shot_res, bat, rot, jerk, piezo = self.detector.process(pkt)
            self.lbl_telem.setText(f"Jerk: {jerk:.1f}\nPiezo: {piezo}\nRot: {rot:.2f}\nBat: {bat}%")
            
            s = self.detector.state
            if s == "IDLE": self.lbl_status.setText("WAITING FOR STABILITY"); self.lbl_status.setStyleSheet("background: #555; color: #AAA;")
            elif s == "ARMING": self.lbl_status.setText("STEADY..."); self.lbl_status.setStyleSheet("background: #AA5500; color: white;")
            elif s == "ARMED": self.lbl_status.setText("READY"); self.lbl_status.setStyleSheet("background: #00AA00; color: white; border: 2px solid #0F0;")
            elif s == "POST_GATHER": self.lbl_status.setText("DETECTED - GATHERING"); self.lbl_status.setStyleSheet("background: #00AA00; color: white; border: 2px solid #FFF;")
            elif s == "COOLDOWN": self.lbl_status.setText("SHOT RECORDED"); self.lbl_status.setStyleSheet("background: #0000AA; color: white;")

            if shot_res:
                score = shot_res['score']; piezo_val = shot_res['piezo']
                self._session_scores.append(score)
                self.lbl_big_score.setText(f"{int(score)}")
                c_hex = "#00FF00" if score > 90 else "#FFFF00" if score > 70 else "#FF0000"
                self.lbl_big_score.setStyleSheet(f"font-size: 80pt; font-weight: bold; color: {c_hex};")
                self.curve_hold.setData(shot_res['hold'][0], shot_res['hold'][1])
                self.curve_press.setData(shot_res['press'][0], shot_res['press'][1])
                self.curve_recoil.setData(shot_res['recoil'][0], shot_res['recoil'][1])
                self.hit_marker.setData([0], [0])
                self.list_history.insertItem(0, f"{datetime.now().strftime('%H:%M:%S')} - Score: {score:.1f} (Pz:{piezo_val})")
                log_shot_db(self.session_id, score, 0.0, "Auto")
                # Update session stats
                avg = sum(self._session_scores) / len(self._session_scores)
                self.lbl_shot_count.setText(f"Shots: {len(self._session_scores)}")
                self.lbl_avg_score.setText(f"Avg: {avg:.1f}")
            
            recent_x = list(self.detector.trace_x); recent_y = list(self.detector.trace_y)
            if recent_x:
                cx = recent_x[-1]; cy = recent_y[-1]
                if self.detector.is_calibrated:
                    short_x = recent_x[-50:]; short_y = recent_y[-50:]
                    disp_x = [x - cx for x in short_x]; disp_y = [y - cy for y in short_y]
                    self.live_curve.setData(disp_x, disp_y); self.cursor.setData([0], [0])
                if self.live_window and self.live_window.isVisible():
                    long_x = recent_x[-100:]; long_y = recent_y[-100:]
                    mon_x = [x - cx for x in long_x]; mon_y = [y - cy for y in long_y]
                    self.live_window.update_data(mon_x, mon_y, self.detector.is_calibrated)

if __name__ == '__main__':
    setup_database()
    app = QApplication(sys.argv)
    
    print(f"Attempting connection to {BLUETOOTH_COM_PORT}...")
    try:
        ser = serial.Serial(BLUETOOTH_COM_PORT, BAUD_RATE, timeout=0.5)
        if perform_auth(ser):
            print("Hardware Verified.")
            win = MainWindow(ser)
            win.show()
            sys.exit(app.exec_())
        else:
            print("Hardware Authentication Failed.")
    except Exception as e:
        print(f"Hardware Error: {e}")
        print(">> SWITCHING TO SIMULATION MODE <<")
        ser = MockSerial()
        win = MainWindow(ser)
        win.setWindowTitle(win.windowTitle() + " [SIMULATION MODE]")
        win.show()
        sys.exit(app.exec_())