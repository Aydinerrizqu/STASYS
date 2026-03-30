#!/usr/bin/env python3
"""
Stasys Session Viewer (Multi-Graph + Micro-Tremor Zoom)
- 3 Separate Graphs for Elevation, Windage, Cant
- Click a shot in the table to ZOOM IN (Micro-Tremor Analysis)
"""

import sys
import os
import sqlite3
from datetime import datetime
import pyqtgraph as pg
from PyQt5.QtWidgets import (QApplication, QMainWindow, QWidget, QVBoxLayout, 
                             QHBoxLayout, QListWidget, QLabel, QSplitter, 
                             QTableWidget, QTableWidgetItem, QHeaderView, QFrame,
                             QPushButton)
from PyQt5.QtGui import QFont, QColor
from PyQt5.QtCore import Qt

# --- CONFIGURATION ---
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DB_FILE = os.path.join(SCRIPT_DIR, 'shooter_data.db')

# Zoom Window (Seconds before/after shot)
ZOOM_PRE = 1.0  # Look back 1 second
ZOOM_POST = 0.5 # Look forward 0.5 seconds

class SessionViewer(QMainWindow):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("STASYS Session Replay (Tremor Analysis)")
        self.resize(1300, 850)
        self.setStyleSheet("""
            QMainWindow { background-color: #2b2b2b; color: white; }
            QLabel { color: white; }
            QListWidget { background-color: #3b3b3b; color: white; border: 1px solid #555; }
            QListWidget::item:selected { background-color: #007ACC; }
            QTableWidget { background-color: #3b3b3b; color: white; gridline-color: #555; }
            QHeaderView::section { background-color: #444; color: white; padding: 4px; }
            QPushButton { background-color: #555; color: white; border: 1px solid #777; padding: 5px; }
            QPushButton:hover { background-color: #666; }
        """)

        # --- Main Layout ---
        main_widget = QWidget()
        self.setCentralWidget(main_widget)
        main_layout = QHBoxLayout(main_widget)
        main_layout.setContentsMargins(10, 10, 10, 10)

        # Splitter
        splitter = QSplitter(Qt.Horizontal)
        main_layout.addWidget(splitter)

        # --- Left Panel ---
        left_panel = QWidget()
        left_layout = QVBoxLayout(left_panel)
        left_layout.setContentsMargins(0, 0, 0, 0)
        
        lbl_sessions = QLabel("Recorded Sessions")
        lbl_sessions.setFont(QFont("Arial", 12, QFont.Bold))
        left_layout.addWidget(lbl_sessions)

        self.session_list = QListWidget()
        self.session_list.setFont(QFont("Consolas", 10))
        self.session_list.currentItemChanged.connect(self.load_session_data)
        left_layout.addWidget(self.session_list)
        splitter.addWidget(left_panel)

        # --- Right Panel ---
        right_panel = QWidget()
        right_layout = QVBoxLayout(right_panel)
        right_layout.setContentsMargins(10, 0, 0, 0)

        # 1. Stats Header
        stats_frame = QFrame()
        stats_frame.setStyleSheet("background-color: #333; border-radius: 5px;")
        stats_layout = QHBoxLayout(stats_frame)
        
        self.lbl_date = QLabel("Date: --")
        self.lbl_duration = QLabel("Duration: --")
        self.lbl_shots = QLabel("Shots: --")
        self.lbl_avg = QLabel("Avg Score: --")
        
        for lbl in [self.lbl_date, self.lbl_duration, self.lbl_shots, self.lbl_avg]:
            lbl.setFont(QFont("Arial", 11, QFont.Bold))
            stats_layout.addWidget(lbl)
        
        # Reset Zoom Button
        self.btn_reset_zoom = QPushButton("Reset Zoom")
        self.btn_reset_zoom.clicked.connect(self.reset_zoom)
        self.btn_reset_zoom.setFixedWidth(100)
        stats_layout.addWidget(self.btn_reset_zoom)

        right_layout.addWidget(stats_frame)

        # 2. Graphs Area (3 Vertical Graphs)
        pg.setConfigOptions(useOpenGL=True, antialias=True)
        
        # --- Graph 1: Elevation (Red) ---
        self.plot_elev = self.create_plot("Elevation (Up/Down)", '#FF4444')
        right_layout.addWidget(self.plot_elev, stretch=1)
        
        # --- Graph 2: Windage (Green) ---
        self.plot_wind = self.create_plot("Windage (Left/Right)", '#44FF44')
        right_layout.addWidget(self.plot_wind, stretch=1)
        
        # --- Graph 3: Cant (Blue) ---
        self.plot_cant = self.create_plot("Cant (Twist)", '#4444FF')
        right_layout.addWidget(self.plot_cant, stretch=1)

        # Link X-Axes for simultaneous zooming
        self.plot_wind.setXLink(self.plot_elev)
        self.plot_cant.setXLink(self.plot_elev)

        # 3. Shot Table
        lbl_shots_table = QLabel("Shot List (Click to Analyze Tremor)")
        right_layout.addWidget(lbl_shots_table)
        
        self.shot_table = QTableWidget()
        self.shot_table.setColumnCount(4)
        self.shot_table.setHorizontalHeaderLabels(["#", "Time (s)", "Score", "Type"])
        self.shot_table.horizontalHeader().setSectionResizeMode(QHeaderView.Stretch)
        self.shot_table.verticalHeader().setVisible(False)
        self.shot_table.setFixedHeight(150)
        self.shot_table.setSelectionBehavior(QTableWidget.SelectRows)
        self.shot_table.itemClicked.connect(self.focus_on_shot) # CLICK EVENT
        right_layout.addWidget(self.shot_table)

        splitter.addWidget(right_panel)
        splitter.setSizes([250, 950])

        # State tracking
        self.current_timestamps = []

        # Load Data
        self.load_sessions_list()

    def create_plot(self, title, color):
        p = pg.PlotWidget(title=title)
        p.setBackground('#1e1e1e')
        p.showGrid(x=True, y=True, alpha=0.3)
        p.setLabel('bottom', 'Time (s)')
        # Add curve
        curve = p.plot(pen=pg.mkPen(color, width=2))
        # Add scatter for shots
        scatter = pg.ScatterPlotItem(size=10, pen=pg.mkPen(None), brush=pg.mkBrush(255, 255, 255, 200), symbol='o')
        p.addItem(scatter)
        # Store references on the widget itself for easy access
        p.curve = curve
        p.scatter = scatter
        return p

    def get_db_connection(self):
        return sqlite3.connect(DB_FILE)

    def load_sessions_list(self):
        if not os.path.exists(DB_FILE):
            self.session_list.addItem("No Database Found")
            return

        conn = self.get_db_connection()
        cur = conn.cursor()
        
        # Check if new columns exist to warn user
        cur.execute("PRAGMA table_info(recordings)")
        cols = [info[1] for info in cur.fetchall()]
        has_axis_data = 'elev' in cols

        query = """
            SELECT session_id, MIN(timestamp), COUNT(*) 
            FROM recordings 
            GROUP BY session_id 
            ORDER BY timestamp DESC
        """
        try:
            cur.execute(query)
            sessions = cur.fetchall()
            
            for sess_id, start_time, count in sessions:
                try:
                    dt = datetime.fromisoformat(start_time)
                    fmt_time = dt.strftime("%Y-%m-%d %H:%M")
                except:
                    fmt_time = str(start_time)

                item_text = f"{fmt_time}  [{count} samples]"
                self.session_list.addItem(item_text)
                
                list_item = self.session_list.item(self.session_list.count() - 1)
                list_item.setData(Qt.UserRole, sess_id)
                
        except Exception as e:
            print(f"DB Error: {e}")
        finally:
            conn.close()

    def load_session_data(self, current_item, previous_item):
        if not current_item: return
        session_id = current_item.data(Qt.UserRole)
        if not session_id: return

        conn = self.get_db_connection()
        cur = conn.cursor()

        # Check for columns
        cur.execute("PRAGMA table_info(recordings)")
        cols = [info[1] for info in cur.fetchall()]
        has_axis = 'elev' in cols

        # Query Data
        if has_axis:
            cur.execute("SELECT timestamp, stability_score, elev, wind, cant FROM recordings WHERE session_id=? ORDER BY timestamp", (session_id,))
        else:
            cur.execute("SELECT timestamp, stability_score FROM recordings WHERE session_id=? ORDER BY timestamp", (session_id,))
            
        rows = cur.fetchall()
        
        self.current_timestamps = []
        elev_data = []
        wind_data = []
        cant_data = []
        scores = []
        start_time = None

        for row in rows:
            try:
                dt = datetime.fromisoformat(row[0])
                if start_time is None: start_time = dt
                delta = (dt - start_time).total_seconds()
                
                self.current_timestamps.append(delta)
                scores.append(row[1])
                
                if has_axis and row[2] is not None:
                    elev_data.append(row[2])
                    wind_data.append(row[3])
                    cant_data.append(row[4])
                else:
                    # Fallback for old data: just plot 0
                    elev_data.append(0)
                    wind_data.append(0)
                    cant_data.append(0)
            except: pass

        # Get Shots
        cur.execute("SELECT timestamp, shot_score, notes FROM shots WHERE session_id=? ORDER BY timestamp", (session_id,))
        shot_rows = cur.fetchall()
        
        shot_times = []
        self.current_shot_details = [] # Store for click handler

        for t_str, score, note in shot_rows:
            try:
                dt = datetime.fromisoformat(t_str)
                if start_time:
                    delta = (dt - start_time).total_seconds()
                    shot_times.append(delta)
                    self.current_shot_details.append((delta, score, note))
            except: pass

        conn.close()

        # --- Update Graphs ---
        self.plot_elev.curve.setData(self.current_timestamps, elev_data)
        self.plot_wind.curve.setData(self.current_timestamps, wind_data)
        self.plot_cant.curve.setData(self.current_timestamps, cant_data)

        # Helper to find Y value at time T
        def get_y_at_t(t_target, t_list, y_list):
            if not t_list: return 0
            # Find closest index
            idx = min(range(len(t_list)), key=lambda i: abs(t_list[i]-t_target))
            return y_list[idx]

        elev_spots = [{'pos': (t, get_y_at_t(t, self.current_timestamps, elev_data)), 'data': 1} for t in shot_times]
        wind_spots = [{'pos': (t, get_y_at_t(t, self.current_timestamps, wind_data)), 'data': 1} for t in shot_times]
        cant_spots = [{'pos': (t, get_y_at_t(t, self.current_timestamps, cant_data)), 'data': 1} for t in shot_times]

        self.plot_elev.scatter.setData(elev_spots)
        self.plot_wind.scatter.setData(wind_spots)
        self.plot_cant.scatter.setData(cant_spots)

        # Reset Zoom automatically on load
        self.reset_zoom()

        # Stats
        if start_time:
            self.lbl_date.setText(f"Date: {start_time.strftime('%Y-%m-%d %H:%M')}")
        
        duration = self.current_timestamps[-1] if self.current_timestamps else 0
        self.lbl_duration.setText(f"Duration: {duration:.1f}s")
        self.lbl_shots.setText(f"Shots: {len(shot_rows)}")
        avg_score = sum(scores) / len(scores) if scores else 0
        self.lbl_avg.setText(f"Avg Score: {avg_score:.1f}")

        # Table
        self.shot_table.setRowCount(0)
        for i, (t, s, n) in enumerate(self.current_shot_details):
            row = self.shot_table.rowCount()
            self.shot_table.insertRow(row)
            self.shot_table.setItem(row, 0, QTableWidgetItem(str(i+1)))
            self.shot_table.setItem(row, 1, QTableWidgetItem(f"{t:.2f}s"))
            self.shot_table.setItem(row, 2, QTableWidgetItem(f"{s:.1f}"))
            self.shot_table.setItem(row, 3, QTableWidgetItem(str(n)))

    def focus_on_shot(self, item):
        """ Zooms the graph to a small window around the selected shot to see tremors. """
        row = item.row()
        if row < len(self.current_shot_details):
            shot_time = self.current_shot_details[row][0]
            
            # Define window: 1 second before -> 0.5 seconds after
            t_min = max(0, shot_time - ZOOM_PRE)
            t_max = shot_time + ZOOM_POST
            
            # Apply Zoom to all graphs (they are X-Linked, so applying to one works for all)
            self.plot_elev.setXRange(t_min, t_max, padding=0)
            
    def reset_zoom(self):
        """ Resets graphs to show the full session. """
        self.plot_elev.autoRange()
        self.plot_wind.autoRange()
        self.plot_cant.autoRange()

if __name__ == '__main__':
    app = QApplication(sys.argv)
    viewer = SessionViewer()
    viewer.show()
    sys.exit(app.exec_())