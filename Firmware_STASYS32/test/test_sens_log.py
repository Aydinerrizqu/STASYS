import unittest
from pathlib import Path

MAIN_CPP = Path(__file__).resolve().parents[1] / "src" / "main.cpp"


def extract_call(source: str, prefix: str) -> str:
    """Return the full call text starting at `prefix`, skipping parens inside strings."""
    start = source.find(prefix)
    if start == -1:
        return ""
    depth = 0
    in_string = False
    for i in range(start, len(source)):
        c = source[i]
        if c == '"' and source[i - 1] != "\\":
            in_string = not in_string
        elif not in_string:
            if c == "(":
                depth += 1
            elif c == ")":
                depth -= 1
                if depth == 0:
                    return source[start:i + 1]
    return ""


class SensLogTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = MAIN_CPP.read_text(encoding="utf-8")

    def test_sens_log_statement_found(self):
        self.assertTrue(
            extract_call(self.source, 'ESP_LOGI(TAG, "SENS'),
            "SENS ESP_LOGI statement not found in src/main.cpp",
        )

    def test_sens_log_prints_piezo_after_mag(self):
        call = extract_call(self.source, 'ESP_LOGI(TAG, "SENS')
        self.assertIn("mag[raw]", call)
        self.assertIn("piezo[raw]", call)
        self.assertLess(
            call.index("mag[raw]"),
            call.index("piezo[raw]"),
            "piezo must be printed after the magnetometer values",
        )

    def test_sens_log_prints_payload_piezo_value(self):
        call = extract_call(self.source, 'ESP_LOGI(TAG, "SENS')
        self.assertIn("payload.piezo", call)


class PiezoBurstDiagnosticTests(unittest.TestCase):
    """Stage 1: burst characterization log in the diagnostic branch."""

    @classmethod
    def setUpClass(cls):
        cls.source = MAIN_CPP.read_text(encoding="utf-8")

    def test_piezo_burst_log_present(self):
        call = extract_call(self.source, 'ESP_LOGI(TAG, "PIEZO')
        self.assertTrue(call, "PIEZO burst ESP_LOGI statement not found in src/main.cpp")

    def test_piezo_burst_log_reports_stats(self):
        call = extract_call(self.source, 'ESP_LOGI(TAG, "PIEZO')
        for field in ("n=", "min=", "max=", "mean=", "nonzero=", "errs=", "dt_us="):
            self.assertIn(field, call, f"PIEZO log missing '{field}'")

    def test_piezo_burst_runs_back_to_back_reads(self):
        # burst loop must call staysys_piezo_read repeatedly with its own count
        self.assertIn("staysys_piezo_read", self.source)
        burst_pos = self.source.find('ESP_LOGI(TAG, "PIEZO')
        read_pos = self.source.rfind("staysys_piezo_read", 0, burst_pos)
        self.assertNotEqual(read_pos, -1, "no staysys_piezo_read before the PIEZO log")


class AdcScanDiagnosticTests(unittest.TestCase):
    """Stage 1: temporary ADC1 channel scan to locate the piezo signal."""

    @classmethod
    def setUpClass(cls):
        cls.source = MAIN_CPP.read_text(encoding="utf-8")

    def test_adcscan_log_present(self):
        call = extract_call(self.source, 'ESP_LOGI(TAG, "ADCSCAN')
        self.assertTrue(call, "ADCSCAN ESP_LOGI statement not found in src/main.cpp")

    def test_adcscan_log_reports_per_channel_stats(self):
        call = extract_call(self.source, 'ESP_LOGI(TAG, "ADCSCAN')
        for field in ("ch=", "gpio=", "min=", "max="):
            self.assertIn(field, call, f"ADCSCAN log missing '{field}'")

class CandidateChannelTests(unittest.TestCase):
    """Stage 1: full-rate monitoring of candidate channels GPIO32/GPIO33.

    The 500ms ADCSCAN only touches each channel for a fraction of a
    millisecond, so a click transient can fall between scan windows. These
    assertions require the candidate channels to be sampled in the main
    oversample loop (every ~1ms) and reported as a max since the previous
    diagnostic tick.
    """

    @classmethod
    def setUpClass(cls):
        cls.source = MAIN_CPP.read_text(encoding="utf-8")

    def test_candidate_log_present(self):
        call = extract_call(self.source, 'ESP_LOGI(TAG, "CAND')
        self.assertTrue(call, "CAND ESP_LOGI statement not found in src/main.cpp")

    def test_candidate_log_reports_both_gpios(self):
        call = extract_call(self.source, 'ESP_LOGI(TAG, "CAND')
        self.assertIn("gpio32=", call)
        self.assertIn("gpio33=", call)

    def test_candidate_channels_sampled_in_oversample_loop(self):
        loop_pos = self.source.find("STASYS_OVERSAMPLE_LOOPS")
        self.assertNotEqual(loop_pos, -1)
        cand_pos = self.source.find("ADC_CHANNEL_4", loop_pos)
        self.assertNotEqual(cand_pos, -1, "GPIO32 (ADC ch4) not sampled in the oversample loop")
        loop_end = self.source.find("if (!have_mpu", loop_pos)
        self.assertTrue(loop_pos < cand_pos < loop_end,
                        "candidate sampling must be inside the oversample loop")
        self.assertIn("ADC_CHANNEL_5", self.source[loop_pos:loop_end],
                      "GPIO33 (ADC ch5) not sampled in the oversample loop")

    def test_candidate_max_reset_each_diagnostic_tick(self):
        cand_log = self.source.find('ESP_LOGI(TAG, "CAND')
        self.assertNotEqual(cand_log, -1, "CAND log missing")
        zone = self.source[cand_log:cand_log + 600]
        self.assertIn("diag_max_gpio32 = 0;", zone,
                      "candidate maxima must reset after each report")
        self.assertIn("diag_max_gpio33 = 0;", zone,
                      "candidate maxima must reset after each report")


    def test_adcscan_restores_piezo_channel_config(self):
        # after the scan, the piezo channel must be reconfigured to its original state
        scan_pos = self.source.find('ESP_LOGI(TAG, "ADCSCAN')
        self.assertNotEqual(scan_pos, -1)
        restore_zone = self.source[scan_pos:scan_pos + 4000]
        self.assertRegex(
            restore_zone,
            r"adc_oneshot_config_channel\([^;]*piezo_channel",
            "piezo channel must be reconfigured after the ADC scan",
        )


if __name__ == "__main__":
    unittest.main()
