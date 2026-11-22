import struct
import unittest
from pathlib import Path

MAIN_CPP = Path(__file__).resolve().parents[1] / "src" / "main.cpp"


def encode_frame(payload):
    if len(payload) != struct.calcsize("<6f3hHB"):
        raise ValueError("payload must match protocol layout")
    body = b"\xAA\xBB" + payload
    checksum = 0
    for byte in body[2:]:
        checksum ^= byte
    return body + bytes((checksum,))


class FrameLayoutTests(unittest.TestCase):
    def test_frame_layout_xor_and_single_bit_flip(self):
        values = (1.0, -2.0, 3.5, 0.25, -0.5, 6.0, -1, 2, -3, 0x1234, 87)
        payload = struct.pack("<6f3hHB", *values)
        frame = encode_frame(payload)

        self.assertEqual(len(frame), 36)
        self.assertEqual(frame[:2], b"\xAA\xBB")
        self.assertEqual(frame[2:35], payload)
        self.assertEqual(struct.unpack("<6f3hHB", frame[2:35]), values)
        self.assertEqual(struct.unpack("<3h", frame[26:32]), (-1, 2, -3))
        self.assertEqual(struct.unpack("<H", frame[32:34])[0], 0x1234)
        self.assertEqual(frame[34], 87)
        expected_xor = 0
        for byte in frame[2:35]:
            expected_xor ^= byte
        self.assertEqual(frame[35], expected_xor)

        flipped = bytearray(frame)
        flipped[17] ^= 0x01
        recalculated_xor = 0
        for byte in flipped[2:35]:
            recalculated_xor ^= byte
        self.assertNotEqual(flipped[35], recalculated_xor)


class AuthV3ProtocolTests(unittest.TestCase):
    """Application auth v3 (docs/STASYS_AUTH_PROTOCOL.md) before telemetry."""

    @classmethod
    def setUpClass(cls):
        cls.source = MAIN_CPP.read_text(encoding="utf-8")

    def test_ready_v3_and_challenge_records(self):
        self.assertIn('"READY v=3\\n"', self.source)
        self.assertIn("AUTH %s %s\\n", self.source)
        self.assertIn('"PROOF "', self.source)
        self.assertIn('"OK\\n"', self.source)
        self.assertIn('"FAIL\\n"', self.source)

    def test_spp_server_started_with_sec_none(self):
        self.assertIn("ESP_SPP_SEC_NONE", self.source)
        self.assertNotIn("ESP_SPP_SEC_AUTHENTICATE", self.source)
        self.assertNotIn("ESP_SPP_SEC_ENCRYPT", self.source)

    def test_hmac_helpers_wired(self):
        for symbol in (
            "staysys_auth_derive_key",
            "staysys_auth_build_transcript",
            "staysys_auth_proof",
            "BT_AUTHENTICATED",
        ):
            self.assertIn(symbol, self.source)

    def test_telemetry_gated_on_auth_bit(self):
        self.assertIn("BT_CONNECTED | BT_AUTHENTICATED", self.source)


if __name__ == "__main__":
    unittest.main()
