import hashlib
import hmac
import re
import struct
import unittest


DOMAIN = b"STASYS-AUTH/v2\0"
KNOWN_PROOF = "12855b0e5b9ed50c4a618a5e0b84cf2d86f7dbbf94fef1d0df83fa6c82d1353b"
UINT32_MAX = 0xFFFFFFFF


def auth_transcript(identity, generation, nonce):
    if len(identity) != 6:
        raise ValueError("identity must be six bytes")
    if not 0 <= generation <= UINT32_MAX:
        raise ValueError("generation out of range")
    if len(nonce) != 32:
        raise ValueError("nonce must be 32 bytes")
    return DOMAIN + identity + struct.pack("<I", generation) + nonce


def auth_proof(key, identity, generation, nonce):
    return hmac.new(key, auth_transcript(identity, generation, nonce), hashlib.sha256).digest()


def encode_frame(payload):
    if len(payload) != struct.calcsize("<6f3hHB"):
        raise ValueError("payload must match protocol layout")
    body = b"\xAA\xBB" + payload
    checksum = 0
    for byte in body[2:]:
        checksum ^= byte
    return body + bytes((checksum,))


def greeting_generation(message):
    match = re.fullmatch(r"READY v=2 gen=(0|[1-9][0-9]*)", message)
    if not match:
        raise ValueError("invalid greeting")
    generation = int(match.group(1))
    if generation > UINT32_MAX:
        raise ValueError("generation out of range")
    return generation


class ProtocolContractTests(unittest.TestCase):
    def test_auth_transcript_exact_boundaries(self):
        identity = bytes.fromhex("010203040506")
        generation = 1
        nonce = bytes(32)
        transcript = auth_transcript(identity, generation, nonce)

        self.assertEqual(len(DOMAIN), 15)
        self.assertEqual(transcript[:15], DOMAIN)
        self.assertEqual(transcript[15:21], identity)
        self.assertEqual(transcript[21:25], b"\x01\x00\x00\x00")
        self.assertEqual(transcript[25:], nonce)
        self.assertEqual(len(transcript), 57)

    def test_auth_fixed_known_proof(self):
        proof = auth_proof(bytes(range(32)), bytes.fromhex("010203040506"), 1, bytes(32))
        self.assertEqual(proof.hex(), KNOWN_PROOF)

    def test_frame_layout_xor_and_single_bit_flip(self):
        values = (1.0, -2.0, 3.5, 0.25, -0.5, 6.0, -1, 2, -3, 0x1234, 87)
        payload = struct.pack("<6f3hHB", *values)
        frame = encode_frame(payload)

        self.assertEqual(len(frame), 36)
        self.assertEqual(frame[:2], b"\xAA\xBB")
        self.assertEqual(frame[2:35], payload)
        self.assertEqual(struct.unpack("<6f3hHB", frame[2:35]), values)
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

    def test_greeting_uint32_boundaries(self):
        self.assertEqual(greeting_generation("READY v=2 gen=0"), 0)
        self.assertEqual(greeting_generation("READY v=2 gen=4294967295"), UINT32_MAX)

    def test_greeting_rejects_invalid_version_or_generation(self):
        for greeting in (
            "READY v=1 gen=0",
            "READY v=3 gen=1",
            "READY v=2 gen=-1",
            "READY v=2 gen=4294967296",
            "READY v=2 gen=",
            "READY v=2 gen=01",
            "READY v=2 gen=1 extra",
        ):
            with self.subTest(greeting=greeting), self.assertRaises(ValueError):
                greeting_generation(greeting)


if __name__ == "__main__":
    unittest.main()
