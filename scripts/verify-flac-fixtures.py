"""Verify device-produced FLAC against its known PCM with an independent decoder.

Usage: python scripts/verify-flac-fixtures.py <downloaded flac-tests directory>
Requires ffmpeg and ffprobe on PATH. No microphone or user recording is opened.
"""
import hashlib
import json
from pathlib import Path
import subprocess
import sys


def digest(stream):
    result = hashlib.sha256()
    count = 0
    while chunk := stream.read(1024 * 1024):
        count += len(chunk)
        result.update(chunk)
    return count, result.hexdigest()


directory = Path(sys.argv[1]).resolve()
results = []
fixtures = [(48000, 13861, ""), (44100, 13861, ""), (48000, 137, ""),
            (48000, 4608, ""), (48000, 4609, ""), (44100, 137, ""),
            (48000, 1, ""), (48000, 15, ""), (48000, 16, ""), (44100, 17, ""),
            (48000, 4609, "_silence"), (44100, 13861, "_constant")]
for rate, samples, suffix in fixtures:
    stem = f"native_{rate}_{samples}{suffix}"
    source = directory / f"{stem}.pcm"
    encoded = directory / f"{stem}.flac"
    metadata = json.loads(subprocess.check_output([
        "ffprobe", "-v", "error", "-show_streams", "-show_packets", "-of", "json", str(encoded)
    ]))
    audio = metadata["streams"][0]
    assert audio["codec_name"] == "flac", metadata
    assert int(audio["sample_rate"]) == rate and audio["channels"] == 1, metadata
    with encoded.open("rb") as flac_file:
        header = flac_file.read(42)
    assert header[:4] == b"fLaC" and header[4] & 0x7f == 0 and header[5:8] == b"\x00\x00\x22"
    streaminfo = header[8:42]
    packed = int.from_bytes(streaminfo[10:18], "big")
    assert packed & ((1 << 36) - 1) == samples, f"Wrong STREAMINFO total samples: {stem}"
    assert (packed >> 36) & 31 == 15, f"Not 16-bit: {stem}"
    assert int.from_bytes(streaminfo[:2], "big") >= 16
    assert int.from_bytes(streaminfo[2:4], "big") >= 16
    packet_sizes = [int(packet["size"]) for packet in metadata["packets"]]
    assert int.from_bytes(streaminfo[4:7], "big") == min(packet_sizes), stem
    assert int.from_bytes(streaminfo[7:10], "big") == max(packet_sizes), stem
    with source.open("rb") as raw:
        expected = digest(raw)
    assert expected[0] == samples * 2, "Fixture is truncated"
    decoder = subprocess.Popen([
        "ffmpeg", "-v", "error", "-i", str(encoded), "-f", "s16le", "-acodec", "pcm_s16le", "pipe:1"
    ], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    actual = digest(decoder.stdout)
    errors = decoder.stderr.read().decode("utf-8", errors="replace")
    assert decoder.wait() == 0 and not errors, errors
    assert actual == expected, f"Decoded samples differ for {stem}: {actual} != {expected}"
    results.append({"file": encoded.name, "sample_rate": rate, "samples": samples,
                    "encoded_bytes": encoded.stat().st_size, "pcm_bytes": actual[0],
                    "pcm_sha256": actual[1], "bit_exact": True,
                    "streaminfo_samples_exact": True})
print(json.dumps(results, ensure_ascii=False, indent=2))
