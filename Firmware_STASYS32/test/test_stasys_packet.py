import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.stasys_packet import (
    AUTH_TRANSCRIPT_SIZE,
    DEV_AUTH_SALT,
    FRAME_SIZE,
    Packet,
    PacketParser,
    PacketParseError,
    SppReceiver,
    auth_derive_key,
    auth_proof,
    auth_transcript,
    encode_packet,
    parse_packet,
)

REFERENCE_MAC = bytes([0xAA, 0xBB, 0xCC, 0xDD, 0xEE, 0xFF])
REFERENCE_NONCE = bytes(range(32))
REFERENCE_PROOF_HEX = (
    "ec5a7a2972cb6a8ad4efd676535c63ae61d47c72bd82706edde7897a150ba8d9"
)
REFERENCE_TRANSCRIPT_HEX = (
    "5354415359532d415554482f7633aabbccddeeff"
    "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"
)


class PacketTests(unittest.TestCase):
    def setUp(self):
        self.packet = Packet(
            ax=1.25, ay=-2.5, az=0.0,
            gx=0.1, gy=-0.2, gz=3.5,
            mag_x=-32768, mag_y=1234, mag_z=32767,
            piezo=65535, battery=254,
        )

    def test_round_trip_preserves_all_fields(self):
        frame = encode_packet(self.packet)
        self.assertEqual(len(frame), FRAME_SIZE)
        self.assertEqual(frame[:2], b"\xaa\xbb")
        decoded = parse_packet(frame)
        for name in ("ax", "ay", "az", "gx", "gy", "gz"):
            self.assertAlmostEqual(getattr(decoded, name), getattr(self.packet, name), places=6)
        self.assertEqual(decoded.mag_x, self.packet.mag_x)
        self.assertEqual(decoded.mag_y, self.packet.mag_y)
        self.assertEqual(decoded.mag_z, self.packet.mag_z)
        self.assertEqual(decoded.piezo, self.packet.piezo)
        self.assertEqual(decoded.battery, self.packet.battery)

    def test_strict_parser_rejects_length_header_and_checksum(self):
        frame = encode_packet(self.packet)
        with self.assertRaises(PacketParseError):
            parse_packet(frame[:-1])
        with self.assertRaises(PacketParseError):
            parse_packet(b"\x00\xbb" + frame[2:])
        corrupt = bytearray(frame)
        corrupt[10] ^= 1
        with self.assertRaises(PacketParseError):
            parse_packet(corrupt)

    def test_stream_parser_handles_fragmentation_and_concatenation(self):
        parser = PacketParser()
        frame = encode_packet(self.packet)
        self.assertEqual(parser.feed(frame[:1]), [])
        self.assertEqual(parser.feed(frame[1:17]), [])
        packets = parser.feed(frame[17:] + frame)
        self.assertEqual(len(packets), 2)
        self.assertTrue(all(abs(item.gx - self.packet.gx) < 1e-6 for item in packets))

    def test_stream_parser_discards_noise_and_resynchronizes(self):
        parser = PacketParser()
        good = encode_packet(self.packet)
        bad = bytearray(good)
        bad[-1] ^= 0x80
        packets = parser.feed(b"noise" + bytes(bad) + b"\xAA" + good)
        self.assertEqual(len(packets), 1)
        self.assertAlmostEqual(packets[0].gx, self.packet.gx, places=6)
        self.assertGreaterEqual(parser.discarded_bytes, 1)
        self.assertGreaterEqual(parser.checksum_errors, 1)

    def test_stream_parser_retains_incomplete_tail(self):
        parser = PacketParser()
        frame = encode_packet(self.packet)
        first = parser.feed(frame + frame[:4])
        self.assertEqual(len(first), 1)
        self.assertAlmostEqual(first[0].gx, self.packet.gx, places=6)
        second = parser.feed(frame[4:])
        self.assertEqual(len(second), 1)
        self.assertAlmostEqual(second[0].gx, self.packet.gx, places=6)

    def test_parser_accepts_nan_float_payload(self):
        packet = Packet(math.nan, 1, 2, 3, 4, 5, 1, 2, 3, 4, 5)
        decoded = parse_packet(encode_packet(packet))
        self.assertTrue(math.isnan(decoded.ax))


class FakeSerial:
    def __init__(self, chunks):
        self.chunks = list(chunks)
        self.writes = []
        self.closed = False

    def read(self, _size):
        return self.chunks.pop(0) if self.chunks else b""

    def write(self, data):
        self.writes.append(bytes(data))

    def close(self):
        self.closed = True


class AuthTests(unittest.TestCase):
    def test_auth_transcript_matches_reference_bytes(self):
        transcript = auth_transcript(REFERENCE_MAC, REFERENCE_NONCE)
        self.assertEqual(len(transcript), AUTH_TRANSCRIPT_SIZE)
        self.assertEqual(transcript.hex(), REFERENCE_TRANSCRIPT_HEX)

    def test_auth_proof_matches_reference_vector(self):
        device_key = auth_derive_key(DEV_AUTH_SALT, REFERENCE_MAC)
        transcript = auth_transcript(REFERENCE_MAC, REFERENCE_NONCE)
        proof = auth_proof(device_key, transcript)
        self.assertEqual(proof.hex(), REFERENCE_PROOF_HEX)

    def test_auth_rejects_wrong_key(self):
        transcript = auth_transcript(REFERENCE_MAC, REFERENCE_NONCE)
        wrong_key = bytes([0xFF] * 32)
        proof = auth_proof(wrong_key, transcript)
        self.assertNotEqual(proof.hex(), REFERENCE_PROOF_HEX)

    def test_auth_rejects_changed_nonce(self):
        device_key = auth_derive_key(DEV_AUTH_SALT, REFERENCE_MAC)
        nonce = bytearray(REFERENCE_NONCE)
        nonce[-1] ^= 0xFF
        transcript = auth_transcript(REFERENCE_MAC, bytes(nonce))
        proof = auth_proof(device_key, transcript)
        self.assertNotEqual(proof.hex(), REFERENCE_PROOF_HEX)


class SppReceiverTests(unittest.TestCase):
    def _auth_prefix(self):
        return (
            b"READY v=3\n"
            + f"AUTH {REFERENCE_NONCE.hex()} {REFERENCE_MAC.hex()}\n".encode("ascii")
        )

    def test_receiver_handshake_succeeds(self):
        packet = Packet(1, 2, 3, 4, 5, 6, -1, 2, -3, 400, 88)
        frame = encode_packet(packet)
        serial = FakeSerial([self._auth_prefix(), b"OK\n", frame])
        receiver = SppReceiver(serial, read_size=128)

        decoded = receiver.read_packets(limit=1)

        self.assertEqual(decoded, [parse_packet(frame)])
        self.assertEqual(len(serial.writes), 1)
        self.assertTrue(serial.writes[0].startswith(b"PROOF "))
        self.assertTrue(receiver.authenticated)

    def test_packet_fragmentation_is_reassembled_after_auth(self):
        packet = Packet(1, 2, 3, 4, 5, 6, -1, 2, -3, 400, 88)
        frame = encode_packet(packet)
        serial = FakeSerial([
            self._auth_prefix(),
            b"OK\n",
            frame[:9],
            frame[9:],
        ])
        receiver = SppReceiver(serial, read_size=128)

        decoded = receiver.read_packets(limit=1)

        self.assertEqual(decoded, [parse_packet(frame)])
        self.assertEqual(len(serial.writes), 1)


if __name__ == "__main__":
    unittest.main()
