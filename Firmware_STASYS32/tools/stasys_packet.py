"""Decode STASYS Bluetooth SPP sensor packets.

The firmware emits a 36-byte binary frame. SPP is a byte stream, so Android
must accumulate bytes and parse complete frames rather than treating each read
callback as one packet.

Frame layout (little endian):
  0..1   AA BB synchronization header
  2..25  ax, ay, az, gx, gy, gz as six float32 values
  26..31 mag_x, mag_y, mag_z as three signed int16 values
  32..33 piezo as uint16
  34     battery as uint8
  35     XOR of bytes 2..34 (header and checksum excluded)

Authentication text is not a binary frame. After SPP connects, the firmware
sends ``READY\n`` and expects a newline-terminated challenge. Binary packets
start after authentication succeeds.
"""

from __future__ import annotations

import argparse
import hmac
import hashlib
import json
import os
import re
import struct
import sys
from dataclasses import asdict, dataclass
from typing import Iterable

HEADER = b"\xAA\xBB"
FRAME_SIZE = 36
CHECKSUM_OFFSET = 35
PAYLOAD_FORMAT = "<6f3hHB"
PAYLOAD_SIZE = struct.calcsize(PAYLOAD_FORMAT)
AUTH_VERSION = 2
AUTH_NONCE_SIZE = 32
AUTH_PROOF_SIZE = 32
AUTH_PROOF_HEX_SIZE = AUTH_PROOF_SIZE * 2
AUTH_MAX_LINE = 160
AUTH_DOMAIN = b"STASYS-AUTH/v2\0"
MAX_BUFFER_SIZE = FRAME_SIZE * 4


def auth_transcript(identity: bytes, generation: int, nonce: bytes) -> bytes:
    if len(identity) != 6 or not (0 <= generation <= 0xFFFFFFFF):
        raise ValueError("identity must be 6 bytes and generation must be uint32")
    if len(nonce) != AUTH_NONCE_SIZE:
        raise ValueError("invalid authentication nonce length")
    return AUTH_DOMAIN + identity + generation.to_bytes(4, "little") + nonce


def auth_proof(key: bytes, transcript: bytes) -> bytes:
    if not key:
        raise ValueError("a provisioned key is required")
    return hmac.new(key, transcript, hashlib.sha256).digest()


def _parse_hex_proof(value: bytes) -> bytes:
    if len(value) != AUTH_PROOF_HEX_SIZE:
        raise SppAuthenticationError("authentication proof has invalid length")
    try:
        result = bytes.fromhex(value.decode("ascii"))
    except (UnicodeDecodeError, ValueError) as error:
        raise SppAuthenticationError("authentication proof is not hexadecimal") from error
    if len(result) != AUTH_PROOF_SIZE:
        raise SppAuthenticationError("authentication proof has invalid length")
    return result


class PacketParseError(ValueError):
    """Raised when a complete frame is malformed."""


class SppAuthenticationError(RuntimeError):
    """Raised when the Bluetooth SPP authentication exchange fails."""


@dataclass(frozen=True)
class Packet:
    ax: float
    ay: float
    az: float
    gx: float
    gy: float
    gz: float
    mag_x: int
    mag_y: int
    mag_z: int
    piezo: int
    battery: int


def checksum(frame_without_checksum: bytes) -> int:
    """Return the protocol XOR checksum for bytes 2 through 34."""
    if len(frame_without_checksum) != CHECKSUM_OFFSET:
        raise ValueError("expected 35 bytes before checksum")
    result = 0
    for value in frame_without_checksum[2:]:
        result ^= value
    return result


def encode_packet(packet: Packet) -> bytes:
    """Serialize a Packet exactly as the firmware serializer does."""
    payload = struct.pack(
        PAYLOAD_FORMAT,
        packet.ax, packet.ay, packet.az, packet.gx, packet.gy, packet.gz,
        packet.mag_x, packet.mag_y, packet.mag_z, packet.piezo, packet.battery,
    )
    frame = HEADER + payload
    return frame + bytes((checksum(frame),))


def parse_packet(frame: bytes) -> Packet:
    """Parse and validate exactly one 36-byte frame."""
    if len(frame) != FRAME_SIZE:
        raise PacketParseError(f"expected {FRAME_SIZE} bytes, got {len(frame)}")
    if frame[:2] != HEADER:
        raise PacketParseError("invalid packet header")
    expected = checksum(frame[:CHECKSUM_OFFSET])
    if frame[CHECKSUM_OFFSET] != expected:
        raise PacketParseError(
            f"invalid checksum: expected 0x{expected:02x}, "
            f"got 0x{frame[CHECKSUM_OFFSET]:02x}"
        )
    values = struct.unpack_from(PAYLOAD_FORMAT, frame, 2)
    return Packet(*values)


class PacketParser:
    """Incrementally recover valid packets from arbitrary SPP byte chunks."""

    def __init__(self, max_buffer_size: int = MAX_BUFFER_SIZE):
        if max_buffer_size < FRAME_SIZE:
            raise ValueError("max_buffer_size must be at least FRAME_SIZE")
        self._buffer = bytearray()
        self.max_buffer_size = max_buffer_size
        self.discarded_bytes = 0
        self.checksum_errors = 0
        self.invalid_frames = 0

    def feed(self, chunk: bytes | bytearray | memoryview) -> list[Packet]:
        """Add bytes and return every complete valid packet now available."""
        self._buffer.extend(chunk)
        if len(self._buffer) > self.max_buffer_size:
            excess = len(self._buffer) - self.max_buffer_size
            del self._buffer[:excess]
            self.discarded_bytes += excess

        packets: list[Packet] = []
        while True:
            start = self._buffer.find(HEADER)
            if start < 0:
                # Keep a possible first header byte for a split AA BB header.
                keep = 1 if self._buffer[-1:] == HEADER[:1] else 0
                self.discarded_bytes += len(self._buffer) - keep
                if keep:
                    del self._buffer[:-1]
                else:
                    self._buffer.clear()
                break
            if start:
                del self._buffer[:start]
                self.discarded_bytes += start
            if len(self._buffer) < FRAME_SIZE:
                break
            candidate = bytes(self._buffer[:FRAME_SIZE])
            try:
                packet = parse_packet(candidate)
            except PacketParseError as error:
                self.invalid_frames += 1
                if "checksum" in str(error):
                    self.checksum_errors += 1
                # Advance one byte so an embedded AA BB can become the next
                # candidate, including when a corrupt frame contains a header.
                del self._buffer[0]
                self.discarded_bytes += 1
                continue
            del self._buffer[:FRAME_SIZE]
            packets.append(packet)
        return packets

_READY_GREETING = re.compile(rb"READY v=(\d+) gen=(\d+)")
_READY_GREETING_NO_GEN = re.compile(rb"READY v=(\d+)")


class SppReceiver:
    """Authenticate and decode packets from a serial-like Bluetooth stream."""

    def __init__(
        self,
        serial_port,
        *,
        key: bytes,
        identity: bytes,
        generation: int,
        read_size: int = 256,
        max_auth_bytes: int = AUTH_MAX_LINE,
    ):
        if not key:
            raise ValueError("a provisioned key is required")
        if len(identity) != 6:
            raise ValueError("identity must be six Bluetooth-address bytes")
        if read_size <= 0 or max_auth_bytes < 1:
            raise ValueError("read_size and max_auth_bytes must be positive")
        self.serial = serial_port
        self.key = bytes(key)
        self.identity = bytes(identity)
        self.generation = generation
        self.read_size = read_size
        self.max_auth_bytes = max_auth_bytes
        self._pending = bytearray()
        self._authenticated = False
        self.parser = PacketParser()

    def _read(self) -> bytes:
        chunk = self.serial.read(self.read_size)
        if not chunk:
            raise SppAuthenticationError("Bluetooth COM port closed or timed out")
        return bytes(chunk)

    def _read_line(self, label: str) -> bytes:
        while True:
            newline = self._pending.find(b"\n")
            if newline >= 0:
                line = bytes(self._pending[:newline])
                del self._pending[:newline + 1]
                return line.rstrip(b"\r")
            if len(self._pending) >= self.max_auth_bytes:
                raise SppAuthenticationError(f"{label} is too long")
            self._pending.extend(self._read())

    def authenticate(self) -> None:
        if self._authenticated:
            return
        ready = self._read_line("greeting")
        match = _READY_GREETING.fullmatch(ready)
        if match is None:
            if _READY_GREETING_NO_GEN.fullmatch(ready):
                raise SppAuthenticationError("greeting missing gen= field")
            raise SppAuthenticationError("unsupported firmware authentication version")
        if int(match.group(1)) != AUTH_VERSION:
            raise SppAuthenticationError("unsupported firmware authentication version")
        generation = int(match.group(2))
        if not 0 <= generation <= 0xFFFFFFFF:
            raise SppAuthenticationError("invalid connection generation")
        self.generation = generation
        auth_line = self._read_line("nonce")
        if not auth_line.startswith(b"AUTH "):
            raise SppAuthenticationError("missing authentication nonce")
        try:
            nonce = bytes.fromhex(auth_line[5:].decode("ascii"))
        except (UnicodeDecodeError, ValueError) as error:
            raise SppAuthenticationError("invalid authentication nonce") from error
        if len(nonce) != AUTH_NONCE_SIZE:
            raise SppAuthenticationError("invalid authentication nonce length")
        transcript = auth_transcript(self.identity, self.generation, nonce)
        proof = auth_proof(self.key, transcript).hex().encode("ascii")
        self.serial.write(b"PROOF " + proof + b"\n")
        result = self._read_line("authentication result")
        if not hmac.compare_digest(result, b"OK"):
            raise SppAuthenticationError("authentication proof rejected")
        self._authenticated = True

    def read_packets(self, limit: int | None = None) -> list[Packet]:
        self.authenticate()
        packets: list[Packet] = []
        if self._pending:
            packets.extend(self.parser.feed(self._pending))
            self._pending.clear()
        while limit is None or len(packets) < limit:
            packets.extend(self.parser.feed(self._read()))
        return packets[:limit] if limit is not None else packets


def _serial_receiver(args) -> int:
    try:
        import serial
    except ImportError as error:
        raise ValueError("live COM mode requires pyserial; install it with: python -m pip install pyserial") from error
    if not args.key_file and not args.key_env:
        raise ValueError("--key-file or --key-env is required with --port")
    if args.key_file:
        with open(args.key_file, "rb") as stream:
            key = stream.read()
    else:
        key = os.environ.get(args.key_env, "").encode("utf-8")
    if not key:
        raise ValueError("provisioned key is empty")
    try:
        identity = bytes.fromhex(args.identity.replace(":", ""))
    except ValueError as error:
        raise ValueError("identity must be six hexadecimal Bluetooth-address bytes") from error
    connection = serial.Serial(args.port, baudrate=args.baud, timeout=args.timeout)
    try:
        receiver = SppReceiver(connection, key=key, identity=identity, generation=args.generation)
        for packet in receiver.read_packets(limit=args.count):
            print(json.dumps(asdict(packet)), flush=True)
    finally:
        connection.close()
    return 0


def _input_bytes(hex_text: str | None, path: str | None) -> bytes:
    if hex_text is not None and path is not None:
        raise ValueError("use either --hex or --file, not both")
    if hex_text is not None:
        return bytes.fromhex(hex_text)
    if path is not None:
        with open(path, "rb") as stream:
            return stream.read()
    return sys.stdin.buffer.read()


def _demo() -> int:
    packet = Packet(1.25, -2.5, 0.0, 0.1, -0.2, 3.5, -10, 20, 30, 4095, 87)
    frame = encode_packet(packet)
    parser = PacketParser()
    decoded: list[Packet] = []
    for piece in (b"noise", frame[:3], frame[3:19], frame[19:]):
        decoded.extend(parser.feed(piece))
    print(json.dumps([asdict(item) for item in decoded], indent=2))
    print(f"frame_hex={frame.hex()}", file=sys.stderr)
    return 0


def main(argv: Iterable[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hex", dest="hex_text", help="hexadecimal SPP bytes")
    parser.add_argument("--file", help="read binary SPP bytes from a file")
    parser.add_argument("--demo", action="store_true", help="run a fragmented-input demo")
    parser.add_argument("--port", help="read live packets from a Bluetooth Windows COM port")
    parser.add_argument("--key-file", help="read the provisioned development key from a file")
    parser.add_argument("--key-env", help="read the provisioned development key from this environment variable")
    parser.add_argument("--identity", required=False, default="000000000000", help="Bluetooth address as 12 hex digits")
    parser.add_argument("--generation", type=int, default=1, help="legacy fallback; actual generation is negotiated in greeting")
    parser.add_argument("--baud", type=int, default=115200, help="nominal COM baud rate")
    parser.add_argument("--timeout", type=float, default=1.0, help="COM read timeout in seconds")
    parser.add_argument("--count", type=int, help="stop after this many packets")
    args = parser.parse_args(argv)
    if args.demo:
        return _demo()
    if args.port:
        try:
            return _serial_receiver(args)
        except (OSError, ValueError, SppAuthenticationError) as error:
            parser.error(str(error))
    if any(value is not None for value in (args.key_file, args.key_env, args.count)):
        parser.error("--key-file, --key-env, and --count require --port")
    try:
        packets = PacketParser().feed(_input_bytes(args.hex_text, args.file))
    except (OSError, ValueError) as error:
        parser.error(str(error))
    print(json.dumps([asdict(packet) for packet in packets], indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
