#!/usr/bin/env python3
"""Cleans up raw HTTP traffic dumps that have debug timestamps interleaved
mid-stream (one timestamp line printed every time a socket read/write is
logged), de-chunks any chunked-transfer-encoding bodies, and pretty-prints
any JSON bodies it finds.

Usage:
    python tool/clean_http_debug_dump.py <input file> [output file]

If [output file] is omitted, writes next to the input as "<name>.clean.txt".
"""
import json
import os
import re
import sys

TIMESTAMP_NOISE = re.compile(
    r"(?:\r?\n)+\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}:\d{2}\.\d+(?:\r?\n)+"
)
REQUEST_LINE = r"(?:GET|POST|PUT|DELETE|HEAD|PATCH|OPTIONS) \S+ HTTP/1\.[01]"
STATUS_LINE = r"HTTP/1\.[01] \d{3}"
MESSAGE_START = re.compile(f"(?:{REQUEST_LINE}|{STATUS_LINE})")
HEX_LINE = re.compile(r"^[0-9a-fA-F]{1,8}$")


def strip_timestamp_noise(text):
    """Removes debug-logger timestamp lines printed mid-stream, joining the
    surrounding content back together with no separator (that gap never
    existed in the real byte stream - it's a logging artifact)."""
    return TIMESTAMP_NOISE.sub("", text)


def fix_glued_http_lines(text):
    """A timestamp sometimes sits exactly on top of a real line break (e.g.
    between a request line and the headers that follow), so stripping it
    above can glue two lines together. Re-split on any request/status line
    that isn't already at the start of a line."""
    text = re.sub(f"([^\r\n])({REQUEST_LINE})", r"\1\r\n\r\n\2", text)
    text = re.sub(f"([^\r\n])({STATUS_LINE})", r"\1\r\n\r\n\2", text)
    return text


def split_into_messages(text):
    """Splits the cleaned text into individual HTTP messages using
    request/status lines as boundaries. Content before the first boundary
    (if any) is kept as an "orphan" body - this happens when the capture
    starts mid-response, after the headers have already scrolled past."""
    starts = [m.start() for m in MESSAGE_START.finditer(text)]
    if not starts:
        return [text]

    messages = []
    if starts[0] > 0:
        messages.append(text[: starts[0]])
    for i, start in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(text)
        messages.append(text[start:end])
    return messages


def dechunk(body):
    """Strips chunked-transfer-encoding size markers (bare hex lines whose
    value roughly matches the length of the data that follows) and joins the
    actual data chunks with no separator, since that's how they appear on
    the wire. Bodies that aren't chunked are returned unchanged."""
    lines = body.split("\r\n")
    confirmed_pairs = 0
    for i in range(len(lines) - 1):
        if not HEX_LINE.match(lines[i]):
            continue
        expected = int(lines[i], 16)
        if expected == 0:
            continue
        actual = len(lines[i + 1])
        if abs(expected - actual) <= 16:
            confirmed_pairs += 1

    if confirmed_pairs < 2:
        return body

    data = []
    i = 0
    while i < len(lines):
        line = lines[i]
        if HEX_LINE.match(line):
            size = int(line, 16)
            if size == 0:
                i += 1
                continue
            if i + 1 < len(lines):
                data.append(lines[i + 1])
            i += 2
        else:
            data.append(line)
            i += 1
    return "".join(data)


def pretty_print_if_json(body):
    trimmed = body.strip()
    if not trimmed.startswith("{") and not trimmed.startswith("["):
        return body
    try:
        decoded = json.loads(trimmed)
        return json.dumps(decoded, indent=2, ensure_ascii=False)
    except ValueError:
        return body


def process_body(body):
    return pretty_print_if_json(dechunk(body))


def process_message(message):
    header_end = message.find("\r\n\r\n")
    if header_end == -1 or not MESSAGE_START.match(message[:30]):
        # No recognizable header block: treat the whole thing as a body.
        return process_body(message)

    head = message[:header_end]
    body = message[header_end + 4:]
    return f"{head}\r\n\r\n{process_body(body)}"


def main():
    if len(sys.argv) < 2:
        print(
            "Usage: python tool/clean_http_debug_dump.py <input file> [output file]",
            file=sys.stderr,
        )
        sys.exit(1)

    input_path = sys.argv[1]
    if not os.path.isfile(input_path):
        print(f"Input file not found: {input_path}", file=sys.stderr)
        sys.exit(1)

    if len(sys.argv) > 2:
        output_path = sys.argv[2]
    else:
        root, _ = os.path.splitext(input_path)
        output_path = f"{root}.clean.txt"

    # newline="" disables universal-newline translation so "\r\n" stays intact
    # -- the chunk-marker detection below depends on splitting on real "\r\n".
    with open(input_path, "r", encoding="utf-8", newline="") as f:
        text = f.read()

    text = strip_timestamp_noise(text)
    text = fix_glued_http_lines(text)

    messages = split_into_messages(text)
    cleaned = "\r\n\r\n".join(process_message(m) for m in messages)

    with open(output_path, "w", encoding="utf-8", newline="") as f:
        f.write(cleaned)

    print(f"Wrote {len(messages)} message(s) to {output_path}")


if __name__ == "__main__":
    main()
