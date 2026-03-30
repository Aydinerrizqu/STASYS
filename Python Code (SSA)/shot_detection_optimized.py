"""
OPTIMIZED SHOT DETECTION SYSTEM
Solusi untuk mengurangi false positives dengan multi-stage filtering
"""

import math
from collections import deque
import time

class ShotDetector:
    """
    Sistem deteksi tembakan yang lebih pintar dengan:
    1. Multi-stage filtering
    2. Signature recognition
    3. Adaptive thresholding
    """
    
    def __init__(self, mode='airsoft'):
        self.mode = mode
        
        # Buffer untuk analisis temporal
        self.accel_history = deque(maxlen=30)  # 30 samples ~ 0.6 detik @ 50Hz
        self.linear_history = deque(maxlen=30)
        self.jerk_history = deque(maxlen=10)
        
        # Gravity filter (high-pass)
        self.gravity_filter = [0.0, 0.0, 0.0]
        self.alpha = 0.85  # Smoothing factor
        
        # State tracking
        self.last_shot_time = 0.0
        self.prev_linear_mag = 0.0
        self.in_cooldown = False
        
        # Thresholds (akan di-tune per mode)
        self.setup_thresholds(mode)
        
    def setup_thresholds(self, mode):
        """Setup parameter deteksi berdasarkan mode"""
        if mode == 'airsoft':
            self.vib_threshold = 1.5      # m/s² - vibrasi minimum  ← Naikkan jika terlalu banyak false positives
            self.jerk_threshold = 1.5     # m/s³ - laju perubahan   ← Naikkan jika gerakan tangan terdeteksi
            self.duration_min = 2         # samples minimum (40ms)  ← Naikkan agar lebih strict
            self.duration_max = 8         # samples maximum (160ms)
            self.cooldown = 0.2           # detik
            self.spike_ratio = 3.0        # Peak harus 3x baseline
            
        elif mode == 'airsoft_dry':
            self.vib_threshold = 0.8       # Diturunkan: karena dry shot tidak ada resistensi peluru
            self.jerk_threshold = 0.7      # Diturunkan: agar sentakan kecil piston/hammer terdeteksi
            self.duration_min = 1          # Sangat pendek: dry shot biasanya hanya berupa satu ketukan tajam
            self.duration_max = 3          # Dibatasi: agar tidak tercampur dengan gerakan tangan saat membidik
            self.cooldown = 10           # Cepat: memungkinkan latihan double-tap, default = 0.5
            self.spike_ratio = 2.0         # Sensitif: asal lebih kuat 2x dari getaran tangan diam
        
        elif mode == 'target':
            self.vib_threshold = 2.5
            self.jerk_threshold = 1.5
            self.duration_min = 3
            self.duration_max = 10
            self.cooldown = 0.5
            self.spike_ratio = 2.5
            
        elif mode == 'rifle':
            self.vib_threshold = 8.0
            self.jerk_threshold = 3.0
            self.duration_min = 2
            self.duration_max = 6
            self.cooldown = 1.0
            self.spike_ratio = 4.0
            
        elif mode == 'archery':
            self.vib_threshold = 1.0
            self.jerk_threshold = 0.8
            self.duration_min = 5
            self.duration_max = 15
            self.cooldown = 2.5
            self.spike_ratio = 2.0
    
    def update_gravity_filter(self, ax, ay, az):
        """Update low-pass filter untuk tracking gravitasi"""
        self.gravity_filter[0] = self.alpha * self.gravity_filter[0] + (1 - self.alpha) * ax
        self.gravity_filter[1] = self.alpha * self.gravity_filter[1] + (1 - self.alpha) * ay
        self.gravity_filter[2] = self.alpha * self.gravity_filter[2] + (1 - self.alpha) * az
    
    def get_linear_acceleration(self, ax, ay, az):
        """Dapatkan linear acceleration (gravitasi sudah dihilangkan)"""
        lin_ax = ax - self.gravity_filter[0]
        lin_ay = ay - self.gravity_filter[1]
        lin_az = az - self.gravity_filter[2]
        
        return math.sqrt(lin_ax**2 + lin_ay**2 + lin_az**2)
    
    def calculate_baseline(self):
        """Hitung baseline vibrasi dari history"""
        if len(self.linear_history) < 10:
            return 0.5  # Default baseline
        
        # Gunakan median 50% data terendah (robust terhadap outliers)
        sorted_data = sorted(list(self.linear_history))
        mid_point = len(sorted_data) // 2
        baseline_samples = sorted_data[:mid_point]
        
        return sum(baseline_samples) / len(baseline_samples) if baseline_samples else 0.5
    
    def detect_shot(self, ax, ay, az):
        """
        Main detection function
        
        Returns:
            bool: True jika tembakan terdeteksi
            dict: Debug info
        """
        now = time.time()
        
        # Update filters
        self.update_gravity_filter(ax, ay, az)
        linear_mag = self.get_linear_acceleration(ax, ay, az)
        
        # Calculate jerk (rate of change)
        jerk = abs(linear_mag - self.prev_linear_mag)
        self.prev_linear_mag = linear_mag
        
        # Store history
        self.accel_history.append(math.sqrt(ax**2 + ay**2 + az**2))
        self.linear_history.append(linear_mag)
        self.jerk_history.append(jerk)
        
        # Cooldown check
        if now - self.last_shot_time < self.cooldown:
            return False, {'reason': 'cooldown', 'linear': linear_mag, 'jerk': jerk}
        
        # ===== STAGE 1: Magnitude Check =====
        if linear_mag < self.vib_threshold:
            return False, {'reason': 'below_threshold', 'linear': linear_mag, 'jerk': jerk}
        
        # ===== STAGE 2: Jerk Check (Impulsiveness) =====
        if jerk < self.jerk_threshold:
            return False, {'reason': 'slow_movement', 'linear': linear_mag, 'jerk': jerk}
        
        # ===== STAGE 3: Baseline Comparison (Spike Detection) =====
        baseline = self.calculate_baseline()
        if linear_mag < baseline * self.spike_ratio:
            return False, {'reason': 'no_spike', 'linear': linear_mag, 'baseline': baseline}
        
        # ===== STAGE 4: Duration Check (Signature Analysis) =====
        # Hitung berapa lama sinyal di atas threshold
        above_threshold = sum(1 for x in list(self.linear_history)[-15:] 
                             if x > self.vib_threshold)
        
        if above_threshold < self.duration_min:
            return False, {'reason': 'too_short', 'duration': above_threshold}
        
        if above_threshold > self.duration_max:
            return False, {'reason': 'too_long', 'duration': above_threshold}
        
        # ===== STAGE 5: Jerk Consistency =====
        # Pastikan ada sustained jerk, bukan noise acak
        recent_jerks = list(self.jerk_history)[-5:]
        high_jerk_count = sum(1 for j in recent_jerks if j > self.jerk_threshold * 0.7)
        
        if high_jerk_count < 2:
            return False, {'reason': 'inconsistent_jerk', 'high_jerk_count': high_jerk_count}
        
        # ===== DETECTION CONFIRMED =====
        self.last_shot_time = now
        
        return True, {
            'linear': linear_mag,
            'jerk': jerk,
            'baseline': baseline,
            'duration': above_threshold,
            'spike_ratio': linear_mag / baseline
        }
    
    def calibrate_gravity(self, accel_samples):
        """
        Kalibrasi initial gravity filter
        
        Args:
            accel_samples: List of (ax, ay, az) tuples
        """
        if len(accel_samples) < 10:
            return False
        
        # Hitung rata-rata
        avg_x = sum(s[0] for s in accel_samples) / len(accel_samples)
        avg_y = sum(s[1] for s in accel_samples) / len(accel_samples)
        avg_z = sum(s[2] for s in accel_samples) / len(accel_samples)
        
        self.gravity_filter = [avg_x, avg_y, avg_z]
        
        return True


# ============================================
# INTEGRATION CODE - Ganti bagian update() Anda
# ============================================

def integrate_into_main_program():
    """
    Cara mengintegrasikan ke program utama Anda
    """
    
    # 1. INISIALISASI (di awal program, setelah setup_database)
    shot_detector = ShotDetector(mode='airsoft')  # atau 'target', 'rifle', 'archery'
    
    # 2. KALIBRASI (dalam fungsi calibrate(), setelah sampling selesai)
    def calibrate():
        # ... kode existing ...
        
        # Tambahkan kalibrasi gravity untuk detector
        accel_samples = [(a_samples[0][i], a_samples[1][i], a_samples[2][i]) 
                        for i in range(len(a_samples[0]))]
        shot_detector.calibrate_gravity(accel_samples)
        
        # ... sisa kode ...
    
    # 3. DETEKSI (dalam fungsi update(), ganti logic di baris 454-490)
    def update():
        # ... kode existing hingga parsing data ...
        
        if parsed:
            values, bat = parsed
            ax, ay, az, gx, gy, gz = values
            
            # DETEKSI TEMBAKAN
            if is_recording and is_calibrated and chk_auto_shot.isChecked():
                is_shot, debug_info = shot_detector.detect_shot(ax, ay, az)
                
                if is_shot:
                    log_shot(is_auto=True)
                    print(f"SHOT! Info: {debug_info}")
                
                # Update UI dengan debug info
                lbl_accel_mag.setText(
                    f"Vib: {debug_info.get('linear', 0):.2f} | "
                    f"Jerk: {debug_info.get('jerk', 0):.2f}"
                )
            
            # ... sisa kode ...


# ============================================
# TUNING HELPER
# ============================================

class DetectorTuner:
    """Tool untuk tuning threshold secara real-time"""
    
    def __init__(self, detector):
        self.detector = detector
        self.shot_log = []
        self.false_positive_log = []
    
    def log_detection(self, is_actual_shot, debug_info):
        """Log untuk analisis"""
        entry = {
            'time': time.time(),
            'info': debug_info,
            'actual': is_actual_shot
        }
        
        if is_actual_shot:
            self.shot_log.append(entry)
        else:
            self.false_positive_log.append(entry)
    
    def analyze(self):
        """Analisis untuk tuning"""
        print("\n=== DETECTION ANALYSIS ===")
        print(f"Real Shots: {len(self.shot_log)}")
        print(f"False Positives: {len(self.false_positive_log)}")
        
        if self.shot_log:
            print("\nReal Shot Characteristics:")
            avg_linear = sum(s['info']['linear'] for s in self.shot_log) / len(self.shot_log)
            avg_jerk = sum(s['info']['jerk'] for s in self.shot_log) / len(self.shot_log)
            print(f"  Avg Linear: {avg_linear:.2f} m/s²")
            print(f"  Avg Jerk: {avg_jerk:.2f} m/s³")
        
        if self.false_positive_log:
            print("\nFalse Positive Reasons:")
            reasons = {}
            for fp in self.false_positive_log:
                reason = fp['info'].get('reason', 'unknown')
                reasons[reason] = reasons.get(reason, 0) + 1
            
            for reason, count in sorted(reasons.items(), key=lambda x: -x[1]):
                print(f"  {reason}: {count}")


# ============================================
# USAGE EXAMPLE
# ============================================

# if __name__ == "__main__":
#     # Test detector
#     detector = ShotDetector(mode='airsoft')
    
#     # Simulasi kalibrasi
#     calibration_data = [(0.1, 0.2, 9.8)] * 50
#     detector.calibrate_gravity(calibration_data)
    
#     # Simulasi data
#     print("\n=== Testing Shot Detection ===\n")
    
#     # 1. Gerakan biasa (slow movement)
#     print("Test 1: Slow movement")
#     for i in range(10):
#         is_shot, info = detector.detect_shot(0.15, 0.2, 9.85)
#         print(f"  Sample {i}: Shot={is_shot}, Info={info}")
    
#     time.sleep(0.3)
    
#     # 2. Tembakan simulasi (sharp spike)
#     print("\nTest 2: Simulated shot")
#     shot_sequence = [
#         (0.1, 0.2, 9.8),   # baseline
#         (0.1, 0.2, 9.8),   # baseline
#         (1.5, 0.8, 11.2),  # spike start
#         (3.2, 1.5, 12.5),  # peak
#         (2.8, 1.2, 11.8),  # decay
#         (1.2, 0.5, 10.2),  # decay
#         (0.3, 0.2, 9.9),   # return
#         (0.1, 0.2, 9.8),   # baseline
#     ]
    
#     for i, (ax, ay, az) in enumerate(shot_sequence):
#         is_shot, info = detector.detect_shot(ax, ay, az)
#         print(f"  Sample {i}: Shot={is_shot}, Info={info}")