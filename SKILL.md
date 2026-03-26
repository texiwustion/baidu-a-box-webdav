---
name: baidu-a-box-webdav
description: Upload to or download from this project's Baidu Netdisk /a-box through the OpenList WebDAV mount at /bd. Use when the user asks to transfer files between the local workspace and Baidu Netdisk, verify the WebDAV endpoint, or list the current contents of the shared dropbox.
---

# Baidu /a-box via WebDAV

This is a project-specific skill for moving files through the OpenList WebDAV mount:

- Baidu Netdisk internal directory: `/a-box`
- OpenList mount path: `/bd`
- WebDAV root for agents: value of `WEBDAV_BASE_URL` in config env file

## Use This Skill When

- The user asks to upload a local file to Baidu Netdisk `/a-box`
- The user asks to fetch a file from `/a-box` into the local workspace
- The user asks to verify connectivity or list the current files in the shared dropbox

## Required Local Config

By default, the script reads:

1. `.env` in the skill root (preferred)
2. fallback `.local/baidu-a-box-webdav.env` in workspace root (legacy)

You can override with `WEBDAV_CONFIG_FILE=/path/to/config.env`.

Required variables:

- `WEBDAV_BASE_URL`
- `WEBDAV_USERNAME`
- `WEBDAV_PASSWORD`

Do not print the password unless the user explicitly asks for it.

Optional:

- `WEBDAV_RETRY_ATTEMPTS`
- `WEBDAV_RETRY_DELAY_SECONDS`

## Preferred Execution Path

Use the bundled script instead of retyping curl commands:

```bash
bash .codex/skills/baidu-a-box-webdav/scripts/a-box-webdav.sh check
bash .codex/skills/baidu-a-box-webdav/scripts/a-box-webdav.sh list
bash .codex/skills/baidu-a-box-webdav/scripts/a-box-webdav.sh upload ./local-file.txt
bash .codex/skills/baidu-a-box-webdav/scripts/a-box-webdav.sh upload-versioned ./local-file.txt
bash .codex/skills/baidu-a-box-webdav/scripts/a-box-webdav.sh upload-versioned ./local-file.txt --git-sha
bash .codex/skills/baidu-a-box-webdav/scripts/a-box-webdav.sh download remote-file.txt ./downloads/remote-file.txt
bash .codex/skills/baidu-a-box-webdav/scripts/a-box-webdav.sh delete remote-file.txt
```

## Workflow

1. Ensure `.env` exists in skill root (or set `WEBDAV_CONFIG_FILE`).
2. Run `check`.
3. If the task is ambiguous, run `list` first so the user and agent are talking about the same file set.
4. Upload with `upload <local_path> [remote_name]`.
5. For traceable uploads, prefer `upload-versioned <local_path> [--git-sha]`.
6. Download with `download <remote_name> [local_path]`.
7. Re-run `list` after writes when verification matters.
8. Use `delete <remote_name>` to clean up temporary verification files.

## Constraints

- Treat the WebDAV root as the only allowed scope. Do not try to escape above `/bd`.
- Prefer small verification files first when debugging write failures.
- Direct browser `GET` on the WebDAV directory returns `405 Method Not Allowed`; that is expected. Use WebDAV methods such as `PROPFIND` or the bundled script.
- If `PUT` or `DELETE` returns `403`, check whether the OpenList user has `WebDAV write` permission enabled.
- Baidu/OpenList may show a short consistency window right after writes. A file can appear in `PROPFIND` slightly before it is downloadable, and a delete can briefly return `423 Locked`.
- If the user wants bulk sync, warn that this skill is optimized for explicit file transfers, not recursive mirroring.
