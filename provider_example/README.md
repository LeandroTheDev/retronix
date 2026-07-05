# Retro OS — Provider Server

HTTP server that exposes local consoles and games to retro_os via a JSON manifest.

## Requirements

- Python 3.10+

## Expected directory structure

```
provider_example/
├── server.py
└── Consoles/
    └── {Console Name}/
    ├── console_image.jpg
    └── Games/
        └── {Game Name}/
            ├── game_image.jpg
            ├── game_achievements.json   (optional)
            └── Game/
                └── rom.z64
```

## Starting the server

```bash
python3 server.py
```

Defaults to port `3000`. To change it, edit the `PORT` variable at the top of the file.

## Endpoints

| Endpoint | Description |
|---|---|
| `GET /` | Status: console and game count |
| `GET /manifest.json` | Full manifest generated dynamically |
| `GET /files/<path>` | Download any asset (image, ROM, achievements) |

## Manifest

The manifest is generated on every request, always reflecting the current state of the consoles directory.

```json
{
  "consoles": [
    {
      "name": "Nintendo 64",
      "image": "/files/Nintendo%2064/console_image.jpg",
      "games": [
        {
          "name": "Super Mario 64",
          "image": "/files/.../game_image.jpeg",
          "rom": "/files/.../Super Mario 64 (USA).z64",
          "achievements": "/files/.../game_achievements.json"
        }
      ]
    }
  ]
}
```

The `achievements` field is only present if `game_achievements.json` exists in the game directory.

## File downloads

The server supports **Range requests** (HTTP 206), allowing clients to resume interrupted downloads.

Typical flow:
1. Client requests `GET /manifest.json` and receives the file URLs
2. Client requests `GET /files/<path>` to download each file
3. If the connection drops, the client resumes with the `Range: bytes=<offset>-` header

Files are streamed in 1 MB chunks — the server never loads an entire file into memory, supporting ROMs of any size.
