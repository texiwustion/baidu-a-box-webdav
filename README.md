# baidu-a-box-webdav

Skill for transferring files to/from Baidu Netdisk `/a-box` via OpenList WebDAV mount.

## Included

- `SKILL.md`
- `scripts/a-box-webdav.sh`

## Configuration

The script loads config in this order:

1. `WEBDAV_CONFIG_FILE` (if set)
2. `.env` in this repository root (preferred)
3. `.local/baidu-a-box-webdav.env` in workspace root (legacy fallback)

Use `.env.example` as template.
