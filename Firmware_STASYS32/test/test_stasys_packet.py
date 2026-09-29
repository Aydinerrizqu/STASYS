import math
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from tools.stasys_packet import (
    FRAME_SIZE,
    Packet,
    PacketParser,
    PacketParseError,
    SppAuthenticationError,
    SppReceiver,
    encode_packet,
    parse_packet,
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


class SppReceiverTests(unittest.TestCase):
    def test_authentication_handles_fragments_and_coalesced_first_frame(self):
        import hmac
        from tools.stasys_packet import auth_transcript, auth_proof
        key = b"test-secret"
        identity = bytes.fromhex("010203040506")
        generation = 7
        nonce = bytes(range(32))
        proof = auth_proof(key, auth_transcript(identity, generation, nonce)).hex().encode("ascii")
        packet = Packet(1, 2, 3, 4, 5, 6, -1, 2, -3, 400, 88)
        serial = FakeSerial([
            b"READY v=2 gen=7\nAUTH " + nonce.hex().encode("ascii")[:17],
            nonce.hex().encode("ascii")[17:] + b"\n",
            b"OK\n" + encode_packet(packet),
        ])
        receiver = SppReceiver(serial, key=key, identity=identity, generation=generation, read_size=128)
        decoded = receiver.read_packets(limit=1)
        self.assertEqual(decoded, [parse_packet(encode_packet(packet))])
        self.assertEqual(serial.writes, [b"PROOF " + proof + b"\n"])
        self.assertFalse(serial.closed)

    def test_generation_parsed_from_greeting_is_used_in_transcript(self):
        from tools.stasys_packet import auth_proof, auth_transcript
        key = b"test-secret"
        identity = bytes.fromhex("aabbccddeeff")
        nonce = bytes(range(32))
        serial = FakeSerial([
            b"READY v=2 gen=42\nAUTH " + nonce.hex().encode("ascii") + b"\n",
            b"OK\n",
        ])
        receiver = SppReceiver(serial, key=key, identity=identity, generation=1, read_size=128)
        receiver.authenticate()
        # Generation comes from the greeting (42), not the constructor default (1).
        expected = auth_proof(key, auth_transcript(identity, 42, nonce)).hex().encode("ascii")
        self.assertEqual(serial.writes, [b"PROOF " + expected + b"\n"])
        self.assertEqual(receiver.generation, 42)

    def test_greeting_missing_generation_is_rejected(self):
        serial = FakeSerial([b"READY v=2\nAUTH " + bytes(32).hex().encode("ascii") + b"\n"])
        receiver = SppReceiver(serial, key=b"test-secret", identity=bytes(6), generation=1, read_size=128)
        with self.assertRaises(SppAuthenticationError):
            receiver.authenticate()

    def test_same_nonce_different_generations_give_different_proofs(self):
        from tools.stasys_packet import auth_proof, auth_transcript
        key = b"test-secret"
        identity = bytes(6)
        nonce = bytes(range(32))
        proof_a = auth_proof(key, auth_transcript(identity, 1, nonce))
        proof_b = auth_proof(key, auth_transcript(identity, 2, nonce))
        self.assertNotEqual(proof_a, proof_b)

    def test_authentication_rejects_wrong_proof(self):
        serial = FakeSerial([b"READY v=2 gen=1\nAUTH " + bytes(32).hex().encode("ascii") + b"\n", b"FAIL\n"])
        receiver = SppReceiver(serial, key=b"test-secret", identity=bytes(6), generation=1, read_size=128)
        with self.assertRaises(SppAuthenticationError):
            receiver.read_packets(limit=1)


if __name__ == "__main__":
    unittest.main()
