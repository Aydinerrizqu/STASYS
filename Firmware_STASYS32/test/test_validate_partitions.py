import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))

from validate_partitions import size_bytes, validate

PARTITIONS_CSV = Path(__file__).resolve().parents[1] / "partitions_dual_ota.csv"
DUAL_OTA_FLASH = 4194304  # 0x400000


class SizeBytesTest(unittest.TestCase):
    def test_plain_integer(self):
        self.assertEqual(size_bytes("4194304"), 4194304)

    def test_hex(self):
        self.assertEqual(size_bytes("0x400000"), 0x400000)

    def test_kilobyte_suffixes(self):
        self.assertEqual(size_bytes("16k"), 16384)
        self.assertEqual(size_bytes("16KB"), 16384)

    def test_megabyte_suffixes(self):
        self.assertEqual(size_bytes("1M"), 1048576)
        self.assertEqual(size_bytes("2MB"), 2 * 1048576)


class ValidateTest(unittest.TestCase):
    def _validate_text(self, text, flash_size):
        with tempfile.NamedTemporaryFile(
            "w", suffix=".csv", delete=False, encoding="utf-8"
        ) as handle:
            handle.write(text)
            path = Path(handle.name)
        try:
            return validate(path, flash_size)
        finally:
            path.unlink()

    def test_valid_table_has_no_errors(self):
        errors = self._validate_text(
            "nvs,data,nvs,0x9000,0x5000,\n"
            "app0,app,ota_0,0x10000,0x100000,\n",
            0x200000,
        )
        self.assertEqual(errors, [])

    def test_overlap_detected(self):
        errors = self._validate_text(
            "a,data,nvs,0x9000,0x5000,\n"
            "b,data,nvs,0xa000,0x5000,\n",
            0x200000,
        )
        self.assertTrue(any("overlaps" in error for error in errors), errors)

    def test_beyond_flash_detected(self):
        errors = self._validate_text(
            "app0,app,ota_0,0x10000,0x3F1000,\n",
            0x400000,
        )
        self.assertTrue(
            any("beyond flash" in error for error in errors), errors
        )

    def test_non_positive_size_detected(self):
        errors = self._validate_text(
            "bad,data,nvs,0x9000,0x0,\n",
            0x200000,
        )
        self.assertTrue(
            any("non-positive size" in error for error in errors), errors
        )

    def test_invalid_value_detected(self):
        errors = self._validate_text(
            "bad,data,nvs,notanumber,0x1000,\n",
            0x200000,
        )
        self.assertTrue(
            any("invalid offset/size" in error for error in errors), errors
        )

    def test_real_dual_ota_table_fits_4mb(self):
        self.assertEqual(validate(PARTITIONS_CSV, DUAL_OTA_FLASH), [])

    def test_real_dual_ota_table_exceeds_4mb_minus_one(self):
        errors = validate(PARTITIONS_CSV, DUAL_OTA_FLASH - 1)
        self.assertTrue(
            any("beyond flash" in error for error in errors), errors
        )


if __name__ == "__main__":
    unittest.main()
