#!/usr/bin/env python3
"""
Retro OS — HTTP provider server
Serves console/game assets and generates manifests from:
  ~/.local/share/retro_os/Consoles/{Console}/{Games}/{Game}/...
"""

import json
import os
import urllib.parse
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

CHUNK_SIZE = 1024 * 1024  # 1 MB chunks for streaming

# ─── Config ────────────────────────────────────────────────────────────────────
PORT = 3000
CONSOLES_DIR = Path(__file__).parent / "Consoles"
# ───────────────────────────────────────────────────────────────────────────────

IMAGE_EXTS = {".jpg", ".jpeg", ".png", ".webp"}
BIOS_EXTS = {".bin", ".mec", ".nvm"}

# Maps console folder name → RetroArch system subdirectory for BIOS files
BIOS_DEST_MAP = {
    "Playstation 2": "pcsx2/bios",
}


def build_manifest() -> dict:
    """Scan CONSOLES_DIR and produce the full manifest."""
    consoles = []

    if not CONSOLES_DIR.exists():
        return {"consoles": consoles}

    for console_dir in sorted(CONSOLES_DIR.iterdir()):
        if not console_dir.is_dir():
            continue

        console_name = console_dir.name
        console_image = _find_image(console_dir, "console_image")
        games_dir = console_dir / "Games"

        games = []
        if games_dir.is_dir():
            for game_dir in sorted(games_dir.iterdir()):
                if not game_dir.is_dir():
                    continue

                game_name = game_dir.name
                game_image = _find_image(game_dir, "game_image")
                rom_path = _find_rom(game_dir / "Game")
                achievements_path = game_dir / "game_achievements.json"

                game_entry = {
                    "name": game_name,
                    "image": _to_url(game_image) if game_image else None,
                    "rom": _to_url(rom_path) if rom_path else None,
                }
                if achievements_path.exists():
                    game_entry["achievements"] = _to_url(achievements_path)

                games.append(game_entry)

        console_entry: dict = {
            "name": console_name,
            "image": _to_url(console_image) if console_image else None,
            "games": games,
        }

        bios_dest = BIOS_DEST_MAP.get(console_name)
        if bios_dest:
            bios_files = _find_bios_files(console_dir)
            if bios_files:
                console_entry["bios_dest"] = bios_dest
                console_entry["bios"] = [_to_url(f) for f in bios_files]

        consoles.append(console_entry)

    return {"consoles": consoles}


def _find_bios_files(console_dir: Path) -> list[Path]:
    bios_dir = console_dir / ".bios"
    if not bios_dir.is_dir():
        return []
    return sorted(
        entry for entry in bios_dir.rglob("*")
        if entry.is_file() and entry.suffix.lower() in BIOS_EXTS
    )


def _find_image(directory: Path, stem: str) -> Path | None:
    for ext in IMAGE_EXTS:
        candidate = directory / f"{stem}{ext}"
        if candidate.exists():
            return candidate
    return None


def _find_rom(game_subdir: Path) -> Path | None:
    if not game_subdir.is_dir():
        return None
    for entry in game_subdir.iterdir():
        if entry.is_file():
            return entry
    return None


def _to_url(path: Path) -> str:
    """Convert an absolute path inside CONSOLES_DIR to a /files/... URL."""
    relative = path.relative_to(CONSOLES_DIR)
    encoded = "/".join(urllib.parse.quote(part) for part in relative.parts)
    return f"/files/{encoded}"


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        path = parsed.path.rstrip("/") or "/"

        if path == "/manifest.json":
            self._serve_manifest()
        elif path.startswith("/files/"):
            self._serve_file(path[len("/files/"):])
        elif path == "/":
            self._serve_index()
        else:
            self._not_found()

    # ── Routes ─────────────────────────────────────────────────────────────────

    def _serve_manifest(self):
        data = json.dumps(build_manifest(), indent=2, ensure_ascii=False).encode()
        self._send(200, "application/json", data)

    def _serve_file(self, encoded_rel: str):
        parts = [urllib.parse.unquote(p) for p in encoded_rel.split("/") if p]
        file_path = CONSOLES_DIR.joinpath(*parts)

        # Security: stay inside CONSOLES_DIR
        try:
            file_path.resolve().relative_to(CONSOLES_DIR.resolve())
        except ValueError:
            self._forbidden()
            return

        if not file_path.is_file():
            self._not_found()
            return

        file_size = file_path.stat().st_size
        mime = _mime(file_path.suffix.lower())
        range_header = self.headers.get("Range")

        if range_header:
            self._serve_range(file_path, file_size, mime, range_header)
        else:
            self._serve_full(file_path, file_size, mime)

    def _serve_index(self):
        manifest = build_manifest()
        console_count = len(manifest["consoles"])
        game_count = sum(len(c["games"]) for c in manifest["consoles"])
        body = (
            f"Retro OS Provider\n"
            f"Consoles : {console_count}\n"
            f"Games    : {game_count}\n\n"
            f"GET /manifest.json   → full manifest\n"
            f"GET /files/<path>    → static asset\n"
        ).encode()
        self._send(200, "text/plain; charset=utf-8", body)

    def _serve_full(self, file_path: Path, file_size: int, mime: str):
        self.send_response(200)
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(file_size))
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        with open(file_path, "rb") as f:
            while chunk := f.read(CHUNK_SIZE):
                self.wfile.write(chunk)

    def _serve_range(self, file_path: Path, file_size: int, mime: str, range_header: str):
        # Parse "bytes=start-end"
        try:
            byte_range = range_header.strip().removeprefix("bytes=")
            start_str, end_str = byte_range.split("-")
            start = int(start_str) if start_str else 0
            end = int(end_str) if end_str else file_size - 1
        except (ValueError, AttributeError):
            self.send_response(416)  # Range Not Satisfiable
            self.send_header("Content-Range", f"bytes */{file_size}")
            self.end_headers()
            return

        end = min(end, file_size - 1)
        if start > end or start < 0:
            self.send_response(416)
            self.send_header("Content-Range", f"bytes */{file_size}")
            self.end_headers()
            return

        length = end - start + 1
        self.send_response(206)  # Partial Content
        self.send_header("Content-Type", mime)
        self.send_header("Content-Length", str(length))
        self.send_header("Content-Range", f"bytes {start}-{end}/{file_size}")
        self.send_header("Accept-Ranges", "bytes")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        with open(file_path, "rb") as f:
            f.seek(start)
            remaining = length
            while remaining > 0:
                chunk = f.read(min(CHUNK_SIZE, remaining))
                if not chunk:
                    break
                self.wfile.write(chunk)
                remaining -= len(chunk)

    # ── Helpers ────────────────────────────────────────────────────────────────

    def _send(self, code: int, content_type: str, body: bytes):
        self.send_response(code)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def _not_found(self):
        self._send(404, "text/plain", b"404 Not Found")

    def _forbidden(self):
        self._send(403, "text/plain", b"403 Forbidden")

    def log_message(self, fmt, *args):
        print(f"[{self.address_string()}] {fmt % args}")


def _mime(ext: str) -> str:
    return {
        ".json": "application/json",
        ".jpg": "image/jpeg",
        ".jpeg": "image/jpeg",
        ".png": "image/png",
        ".webp": "image/webp",
        ".z64": "application/octet-stream",
        ".n64": "application/octet-stream",
        ".v64": "application/octet-stream",
        ".sfc": "application/octet-stream",
        ".smc": "application/octet-stream",
        ".gba": "application/octet-stream",
        ".gb":  "application/octet-stream",
        ".gbc": "application/octet-stream",
        ".nes": "application/octet-stream",
        ".iso": "application/octet-stream",
    }.get(ext, "application/octet-stream")


if __name__ == "__main__":
    print(f"Consoles dir : {CONSOLES_DIR}")
    print(f"Serving on   : http://0.0.0.0:{PORT}")
    print(f"Manifest     : http://0.0.0.0:{PORT}/manifest.json")
    server = HTTPServer(("0.0.0.0", PORT), Handler)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopped.")
