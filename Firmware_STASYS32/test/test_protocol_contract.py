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


class AuthFreeProtocolTests(unittest.TestCase):
    """Contract of the auth-free streaming protocol (upstream 5f955e8):
    static READY greeting, open SPP, packets stream without any exchange."""

    @classmethod
    def setUpClass(cls):
        cls.source = MAIN_CPP.read_text(encoding="utf-8")

    def test_static_ready_v2_greeting(self):
        self.assertIn('"READY v=2\\n"', self.source)
        self.assertNotIn("AUTH ", self.source)
        self.assertNotIn("PROOF", self.source)

    def test_spp_server_started_with_sec_none(self):
        self.assertIn("ESP_SPP_SEC_NONE", self.source)
        self.assertNotIn("ESP_SPP_SEC_AUTHENTICATE", self.source)
        self.assertNotIn("ESP_SPP_SEC_ENCRYPT", self.source)

    def test_no_auth_or_provisioning_symbols_remain(self):
        for symbol in (
            "staysys_auth_",
            "staysys_provisioned_key",
            "auth_nonce",
            "auth_state",
            "provisioning",
            "ENROLLMENT_WINDOW",
        ):
            self.assertNotIn(symbol, self.source, f"'{symbol}' must be removed from src/main.cpp")

    def test_packet_send_gate_has_no_auth_bit(self):
        self.assertIn("bool can_send = !spp_congested && handle != 0;", self.source)
        self.assertNotIn("BT_AUTHENTICATED", self.source)


if __name__ == "__main__":
    unittest.main()
