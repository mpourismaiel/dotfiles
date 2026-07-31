#!/usr/bin/env python3
# clipbridge.py — clipboard-history backend for the pill (cliphist + wl-clipboard).
#
# The pill can't read the clipboard itself, so:
#   watch        run the two wl-paste watchers (text + image) that feed cliphist;
#                launched once by init.qml (Process, running:true) so the watchers
#                live and die with the pill — kills its children on exit.
#   list         print a JSON array (newest first, capped) of history entries:
#                  image -> {id,kind:"image",w,h,path}   (decoded to a cache file)
#                  text  -> {id,kind:"text",text,images}  (embedded data:image URIs
#                           stripped from the preview; `images` counts how many)
#   copy <id>    decode entry <id> and put it back on the clipboard (wl-copy)
#   delete <id>  drop entry <id> from history
#   wipe         clear the whole history (and the decoded-image cache)
import sys, os, re, json, subprocess, signal

CACHE = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
    "quickshell-pill",
    "clip",
)
MAX_ENTRIES = 60  # entries exposed to the menu (it shows 10; search covers these)

# a cliphist image preview line: "[[ binary data 2 KiB png 600x400 ]]"
IMG_RE = re.compile(r"^\[\[ binary data .* (\w+) (\d+)x(\d+) \]\]$")
# an embedded image inside copied text (a data URI)
DATAURI_RE = re.compile(r"data:image/[\w.+-]+;base64,[A-Za-z0-9+/=]+")

EXT = {"jpeg": "jpg"}
MAGIC = [
    (b"\x89PNG\r\n\x1a\n", "image/png"),
    (b"\xff\xd8\xff", "image/jpeg"),
    (b"GIF8", "image/gif"),
    (b"RIFF", "image/webp"),  # close enough; wl-copy re-sniffs anyway
    (b"BM", "image/bmp"),
]


def run(args, **kw):
    try:
        return subprocess.run(args, capture_output=True, **kw)
    except FileNotFoundError:
        return None


def raw_list():
    p = run(["cliphist", "list"])
    if not p or p.returncode != 0:
        return []
    out = []
    for line in p.stdout.split(b"\n"):
        if not line:
            continue
        i = line.find(b"\t")
        if i < 0:
            continue
        cid = line[:i].decode("utf-8", "replace")
        preview = line[i + 1 :].decode("utf-8", "replace")
        out.append((cid, preview))
    return out


def decode(cid):
    p = run(["cliphist", "decode", cid])
    return p.stdout if (p and p.returncode == 0) else b""


def _id(cid):
    return int(cid) if cid.isdigit() else cid


def cmd_list():
    os.makedirs(CACHE, exist_ok=True)
    keep, result = set(), []
    for cid, preview in raw_list()[:MAX_ENTRIES]:
        m = IMG_RE.match(preview)
        if m:
            typ = m.group(1).lower()
            path = os.path.join(CACHE, cid + "." + EXT.get(typ, typ))
            keep.add(os.path.basename(path))
            if not os.path.exists(path):
                data = decode(cid)
                if not data:
                    continue
                with open(path, "wb") as f:
                    f.write(data)
            result.append(
                {
                    "id": _id(cid),
                    "kind": "image",
                    "w": int(m.group(2)),
                    "h": int(m.group(3)),
                    "path": path,
                }
            )
        else:
            # only the full decode reliably finds/strips embedded images, so skip
            # it for the common case (a preview with no data URI) — cheap + correct.
            if "data:image" in preview:
                text = decode(cid).decode("utf-8", "replace")
                n = len(DATAURI_RE.findall(text))
                text = DATAURI_RE.sub("", text)
            else:
                text, n = preview, 0
            text = re.sub(r"\s+", " ", text).strip()[:300]
            result.append({"id": _id(cid), "kind": "text", "text": text, "images": n})
    try:  # prune cache files for gone entries
        for f in os.listdir(CACHE):
            if f not in keep:
                os.remove(os.path.join(CACHE, f))
    except OSError:
        pass
    sys.stdout.write(json.dumps(result))


def cmd_copy(cid):
    data = decode(cid)
    if not data:
        return
    typ = next((mime for magic, mime in MAGIC if data.startswith(magic)), None)
    args = ["wl-copy"] + (["--type", typ] if typ else [])
    # wl-copy forks a daemon to serve the selection; don't capture (the daemon
    # would hold the pipe open and hang us) — just let it detach.
    try:
        subprocess.run(
            args, input=data, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL
        )
    except FileNotFoundError:
        pass


def cmd_delete(cid):
    # cliphist delete keys off the id before the tab; the preview is ignored.
    run(["cliphist", "delete"], input=(cid + "\t.\n").encode())


def cmd_wipe():
    run(["cliphist", "wipe"])
    try:
        for f in os.listdir(CACHE):
            os.remove(os.path.join(CACHE, f))
    except OSError:
        pass


def cmd_watch():
    try:
        watchers = [
            subprocess.Popen(
                ["wl-paste", "--type", "text", "--watch", "cliphist", "store"]
            ),
            subprocess.Popen(
                ["wl-paste", "--type", "image", "--watch", "cliphist", "store"]
            ),
        ]
    except FileNotFoundError:
        return

    def stop(*_):
        for w in watchers:
            try:
                w.terminate()
            except OSError:
                pass
        sys.exit(0)

    signal.signal(signal.SIGTERM, stop)
    signal.signal(signal.SIGINT, stop)
    for w in watchers:
        w.wait()


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    arg = sys.argv[2] if len(sys.argv) > 2 else None
    if cmd == "list":
        cmd_list()
    elif cmd == "copy" and arg:
        cmd_copy(arg)
    elif cmd == "delete" and arg:
        cmd_delete(arg)
    elif cmd == "wipe":
        cmd_wipe()
    elif cmd == "watch":
        cmd_watch()


if __name__ == "__main__":
    main()
