#!/usr/bin/env python3
# voicebridge.py — faster-whisper transcription + optional Claude polish for the
# pill's voice-recording mode. Run with the venv python (see setup-transcribe.sh):
#
#   voicebridge.py WAV MODE MODEL LANGUAGE DEVICE VAD CLAUDE_MODEL
#   voicebridge.py init          # just write the default prompt files
#
# Raw transcript is clipboarded as soon as whisper finishes; polish mode then
# replaces the clipboard with Claude's cleanup. Notifications (success and
# failure) are posted from here via notify-send -a Transcribe; stdout carries one
# JSON line {"ok": bool, "mode": str, "error": str} for the pill. The wav is
# deleted on every path.
import datetime, json, os, subprocess, sys

CONF_DIR = os.path.expanduser("~/.config/quickshell/transcribe")
WHISPER_PROMPT = os.path.join(CONF_DIR, "whisper-prompt.md")
POLISH_PROMPT = os.path.join(CONF_DIR, "polish-prompt.md")
ICON = os.path.expanduser("~/.config/quickshell/pill/transcribe.svg")
# permanent per-memo store (created on demand) + the org-agenda append target
MEMO_DIR = os.path.expanduser("~/Documents/memos")
ORG_PROMPT = os.path.join(CONF_DIR, "org-prompt.md")
# where org memos land — matches the user's Doom capture setup (~/org is the
# agenda root; inbox.org is the TODO capture file, notes.org the note file).
ORG_INBOX = os.path.expanduser("~/org/inbox.org")
ORG_NOTES = os.path.expanduser("~/org/notes.org")

DEFAULT_WHISPER_PROMPT = """Casual technical dictation, in full sentences with proper punctuation and
capitalization. Vocabulary that comes up: Quickshell, KDE, Plasma, KWin, Wayland,
PipeWire, Emacs, org-mode, Doom, GitHub, Claude, API, QML, Python.
"""

DEFAULT_ORG_PROMPT = """You turn a short spoken memo into a single actionable org-agenda task.
Today is {TODAY} ({WEEKDAY}).

Return ONLY a JSON object — no prose, no markdown, no code fences:
{"title": "<imperative task, capitalized, with the date/time words removed>",
 "deadline": "<YYYY-MM-DD, or an empty string if the memo names no time>"}

Resolve relative dates against today ({TODAY}):
- "today" -> {TODAY}; "tomorrow" -> today + 1 day.
- "next week" -> today + 7 days; "in N days"/"in N weeks" -> computed.
- "next <weekday>" / "on <weekday>" -> the next such weekday after today.
- an explicit date ("July 3", "3rd of August", "2026-09-01") -> that date.
Strip the time phrase out of the title:
  "tomorrow I have to deploy Elvou" -> {"title": "Deploy Elvou", "deadline": "<today+1>"}
  "go to doctor next week"          -> {"title": "Go to doctor", "deadline": "<today+7>"}
  "remember to water the plants"    -> {"title": "Water the plants", "deadline": ""}
"""

DEFAULT_POLISH_PROMPT = """You clean up raw voice transcriptions. The user message is the unedited output
of a speech-to-text model. Rewrite it as polished text:

- fix transcription mistakes, punctuation and capitalization;
- drop filler words (um, uh, like, you know) and false starts;
- apply self-corrections the speaker makes mid-stream ("actually, scratch that,
  make it three") so only the corrected version remains;
- keep the speaker's meaning, tone and language — do not add content, do not
  summarize, do not translate.

Reply with ONLY the cleaned-up text: no preamble, no quotes, no commentary.
"""


def ensure_prompts():
    os.makedirs(CONF_DIR, exist_ok=True)
    for path, body in ((WHISPER_PROMPT, DEFAULT_WHISPER_PROMPT),
                       (POLISH_PROMPT, DEFAULT_POLISH_PROMPT),
                       (ORG_PROMPT, DEFAULT_ORG_PROMPT)):
        if not os.path.exists(path):
            with open(path, "w") as f:
                f.write(body)


def read_prompt(path):
    try:
        with open(path) as f:
            return f.read().strip()
    except OSError:
        return ""


def clip(text):
    subprocess.run(["wl-copy"], input=text.encode(), check=False)


def notify(summary, body, critical=False, copy_text=None):
    # the pill advertises body-markup, so escape the transcript's &, < and >
    body = body.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    cmd = ["notify-send", "-a", "Transcribe", "-i", ICON, "-t", "0"]
    if critical:
        cmd += ["-u", "critical"]
    # attach the exact (un-escaped) transcript so the card's copy button copies
    # the real text, not the markup-escaped body
    if copy_text is not None:
        cmd += ["-h", "string:x-transcript:" + copy_text]
    subprocess.run(cmd + [summary, body], check=False)


# credentials per cloud provider — an env var wins, else the keyring entry the
# pill writes from the Transcribe tab (service = provider, user = pill-transcribe).
KEY_ENV = {"anthropic": ["ANTHROPIC_API_KEY"],
           "google": ["GOOGLE_API_KEY", "GEMINI_API_KEY"],
           "openai": ["OPENAI_API_KEY"]}


def _get_key(provider):
    for env in KEY_ENV.get(provider, []):
        v = os.environ.get(env, "")
        if v:
            return v
    try:
        import keyring
        return keyring.get_password(provider, "pill-transcribe") or ""
    except Exception:
        return ""


def api_key():
    return _get_key("anthropic")


# the polish/extraction model id decides the backend: "local" -> ollama,
# "gemini*" -> the Gemini API, "gpt*" -> the OpenAI API, anything else -> Claude.
def provider_of(model):
    if model == "local":
        return "local"
    if model.startswith("gemini"):
        return "gemini"
    if model.startswith("gpt"):
        return "openai"
    return "claude"


def preload_cuda_libs():
    # ctranslate2 dlopens libcudnn/libcublas at model init, and dlopen ignores
    # LD_LIBRARY_PATH changes made after process start — so load the nvidia pip
    # wheels' libraries by absolute path; once resident they resolve by soname.
    # Failures are fine (missing wheel => the cuda attempt fails => cpu fallback).
    import ctypes, glob
    for lib in sorted(glob.glob(os.path.join(
            sys.prefix, "lib", "python*", "site-packages", "nvidia", "*", "lib", "*.so*"))):
        try:
            ctypes.CDLL(lib)
        except OSError:
            pass


def transcribe(wav, model, language, device, vad):
    from faster_whisper import WhisperModel
    attempts = []
    if device in ("auto", "cuda"):
        attempts.append(("cuda", "float16"))
    attempts.append(("cpu", "int8"))       # always keep the CPU fallback
    prompt = read_prompt(WHISPER_PROMPT)
    last = None
    for dev, ctype in attempts:
        try:
            if dev == "cuda":
                preload_cuda_libs()
            m = WhisperModel(model, device=dev, compute_type=ctype)
            segments, _info = m.transcribe(
                wav,
                language=None if language == "auto" else language,
                initial_prompt=prompt or None,
                vad_filter=vad,
            )
            return " ".join(s.text.strip() for s in segments).strip()
        except Exception as e:              # cuda missing, bad model name, …
            last = e
    raise RuntimeError("whisper failed: %s" % last)


## ---- LLM completion (shared by polish + org extraction) --------------------
# one system+user turn -> text. claude_model "local" routes to a local ollama
# model (offline, no key); any other id uses the Claude API. json_mode asks the
# local model for strict JSON (used by the org extractor).

def _llm_local(system, user, local_model, json_mode=False):
    import json as _json, urllib.request
    payload = {
        "model": local_model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        "stream": False,
        "options": {"temperature": 0.2},
    }
    if json_mode:
        payload["format"] = "json"
    req = urllib.request.Request(
        "http://localhost:11434/api/chat",
        data=_json.dumps(payload).encode(),
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            data = _json.loads(r.read())
    except urllib.error.URLError as e:
        raise RuntimeError("ollama unreachable (%s) — is `ollama serve` running "
                           "and '%s' pulled? (setup-transcribe.sh local)" % (e, local_model))
    out = ((data.get("message") or {}).get("content") or "").strip()
    if not out:
        raise RuntimeError("local model '%s' returned no text" % local_model)
    return out


def _llm_claude(system, user, claude_model):
    import anthropic
    key = _get_key("anthropic")
    if not key:
        raise RuntimeError("no Anthropic API key — add one in the pill's "
                           "Transcribe tab, or switch the polish model to 'local'")
    client = anthropic.Anthropic(api_key=key)
    resp = client.messages.create(
        model=claude_model,
        max_tokens=4000,
        system=system,
        messages=[{"role": "user", "content": user}],
    )
    out = "".join(b.text for b in resp.content if b.type == "text").strip()
    if not out:
        raise RuntimeError("Claude returned no text (stop_reason: %s)" % resp.stop_reason)
    return out


def _llm_gemini(system, user, model, json_mode=False):
    # Google Gemini via the REST API (stdlib only — no SDK). Key from the pill.
    import json as _json, urllib.request, urllib.error
    key = _get_key("google")
    if not key:
        raise RuntimeError("no Google API key — add one in the pill's Transcribe tab")
    gen = {"temperature": 0.2}
    if json_mode:
        gen["responseMimeType"] = "application/json"
    body = {
        "systemInstruction": {"parts": [{"text": system}]},
        "contents": [{"role": "user", "parts": [{"text": user}]}],
        "generationConfig": gen,
    }
    url = ("https://generativelanguage.googleapis.com/v1beta/models/%s:generateContent" % model)
    req = urllib.request.Request(
        url, data=_json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "x-goog-api-key": key})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            data = _json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise RuntimeError("gemini HTTP %s: %s" % (e.code, e.read()[:200].decode("utf-8", "replace")))
    except urllib.error.URLError as e:
        raise RuntimeError("gemini unreachable (%s)" % e)
    cands = data.get("candidates") or []
    if not cands:
        raise RuntimeError("gemini returned no candidates (%s)" % data.get("promptFeedback"))
    parts = ((cands[0].get("content") or {}).get("parts") or [])
    out = "".join(p.get("text", "") for p in parts).strip()
    if not out:
        raise RuntimeError("gemini empty response")
    return out


def _llm_openai(system, user, model, json_mode=False):
    # OpenAI via the Chat Completions REST API (stdlib only — no SDK). Key from
    # the pill. No temperature is sent (the reasoning gpt-* models reject anything
    # but the default), and json_mode asks for a strict JSON object.
    import json as _json, urllib.request, urllib.error
    key = _get_key("openai")
    if not key:
        raise RuntimeError("no OpenAI API key — add one in the pill's Transcribe tab")
    body = {
        "model": model,
        "messages": [
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
    }
    if json_mode:
        body["response_format"] = {"type": "json_object"}
    req = urllib.request.Request(
        "https://api.openai.com/v1/chat/completions",
        data=_json.dumps(body).encode(),
        headers={"Content-Type": "application/json", "Authorization": "Bearer " + key})
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            data = _json.loads(r.read())
    except urllib.error.HTTPError as e:
        raise RuntimeError("openai HTTP %s: %s" % (e.code, e.read()[:200].decode("utf-8", "replace")))
    except urllib.error.URLError as e:
        raise RuntimeError("openai unreachable (%s)" % e)
    choices = data.get("choices") or []
    if not choices:
        raise RuntimeError("openai returned no choices (%s)" % data.get("error"))
    out = ((choices[0].get("message") or {}).get("content") or "").strip()
    if not out:
        raise RuntimeError("openai empty response")
    return out


def _llm(system, user, model, local_model, json_mode=False):
    p = provider_of(model)
    if p == "local":
        return _llm_local(system, user, local_model, json_mode)
    if p == "gemini":
        return _llm_gemini(system, user, model, json_mode)
    if p == "openai":
        return _llm_openai(system, user, model, json_mode)
    return _llm_claude(system, user, model)


## ---- in-pill setup: provider keys + local-model download -------------------
# the Transcribe tab drives these instead of setup-transcribe.sh: report which
# keys/models are present (status), store a cloud key (setkey -> keyring), and
# stream an ollama model download (pull -> newline JSON progress).

def _ollama_tags():
    import json as _json, urllib.request
    try:
        with urllib.request.urlopen("http://localhost:11434/api/tags", timeout=5) as r:
            data = _json.loads(r.read())
    except Exception:
        return []
    return [m.get("name", "") for m in (data.get("models") or [])]


def _ollama_has(model):
    if not model:
        return False
    names = _ollama_tags()
    if model in names or (model + ":latest") in names:
        return True
    if ":" not in model:                         # bare name matches any tag
        return any(n.split(":", 1)[0] == model for n in names)
    return False


def cmd_status(local_model):
    sys.stdout.write(json.dumps({
        "anthropic": bool(_get_key("anthropic")),
        "google": bool(_get_key("google")),
        "openai": bool(_get_key("openai")),
        "local": _ollama_has(local_model),
    }))


def cmd_setkey(provider, value):
    if provider not in ("anthropic", "google", "openai"):
        sys.stdout.write(json.dumps({"ok": False, "error": "unknown provider"}))
        return
    try:
        import keyring
        keyring.set_password(provider, "pill-transcribe", value)
        sys.stdout.write(json.dumps({"ok": True}))
    except Exception as e:
        sys.stdout.write(json.dumps({"ok": False, "error": str(e)}))


def cmd_pull(model):
    # stream ollama's /api/pull; emit one compact JSON progress line at a time so
    # the pill can drive a progress bar (SplitParser reads it line-by-line).
    import json as _json, urllib.request, urllib.error
    try:
        req = urllib.request.Request(
            "http://localhost:11434/api/pull",
            data=_json.dumps({"model": model, "stream": True}).encode(),
            headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=3600) as r:
            for raw in r:
                raw = raw.strip()
                if not raw:
                    continue
                try:
                    d = _json.loads(raw)
                except Exception:
                    continue
                line = {"status": d.get("status", "")}
                for k in ("completed", "total", "error"):
                    if k in d:
                        line[k] = d[k]
                sys.stdout.write(_json.dumps(line) + "\n")
                sys.stdout.flush()
        sys.stdout.write(_json.dumps({"done": True}) + "\n")
        sys.stdout.flush()
    except urllib.error.URLError as e:
        sys.stdout.write(_json.dumps({"error": "ollama unreachable (%s) — is it installed and running?" % e}) + "\n")
        sys.stdout.flush()


def polish(text, claude_model, local_model):
    return _llm(read_prompt(POLISH_PROMPT), text, claude_model, local_model)


## ---- permanent memo store (~/Documents/memos, one file per memo) ----------
# each memo is a markdown file `YYYYMMDD-HHMMSS-<type>.md` with a tiny frontmatter
# (created / type / polished) so the pill's clipboard→Memos tab can list them.

# a polished memo keeps its original transcript after this marker, so the pill's
# Memos tab can offer "see unpolished" and copy either version.
UNPOL_MARK = "<!-- unpolished -->"


def _memo_body(text, raw):
    body = text.strip()
    if raw and raw.strip() and raw.strip() != text.strip():
        body += "\n\n" + UNPOL_MARK + "\n" + raw.strip()
    return body + "\n"


def _write_memo(path, created, memo_type, polished, text, raw=""):
    fm = "---\ncreated: %s\ntype: %s\npolished: %s\n---\n" % (
        created, memo_type, "true" if polished else "false")
    with open(path, "w") as f:
        f.write(fm + _memo_body(text, raw))


def store_memo(text, memo_type, polished, raw=""):
    os.makedirs(MEMO_DIR, exist_ok=True)
    now = datetime.datetime.now()
    base = now.strftime("%Y%m%d-%H%M%S") + "-" + memo_type
    path = os.path.join(MEMO_DIR, base + ".md")
    n = 1
    while os.path.exists(path):          # two within the same second
        path = os.path.join(MEMO_DIR, "%s-%d.md" % (base, n)); n += 1
    _write_memo(path, now.isoformat(timespec="seconds"), memo_type, polished, text, raw)
    return path


def _read_memo(path):
    try:
        with open(path) as f:
            content = f.read()
    except OSError:
        return None
    meta = {"created": "", "type": "note", "polished": False}
    body = content
    if content.startswith("---\n"):
        end = content.find("\n---\n", 4)
        if end != -1:
            for line in content[4:end].splitlines():
                if ":" in line:
                    k, v = line.split(":", 1)
                    k, v = k.strip(), v.strip()
                    if k == "polished":
                        meta["polished"] = (v == "true")
                    elif k in meta:
                        meta[k] = v
            body = content[end + 5:]
    text, unpol = body, ""
    marker = "\n" + UNPOL_MARK + "\n"
    i = body.find(marker)
    if i != -1:
        text, unpol = body[:i], body[i + len(marker):]
    return {"created": meta["created"], "type": meta["type"], "polished": meta["polished"],
            "text": text.strip(), "raw": unpol.strip()}


def list_memos():
    try:
        names = sorted((n for n in os.listdir(MEMO_DIR) if n.endswith(".md")), reverse=True)
    except OSError:
        names = []                       # dir not created yet -> empty list
    out = []
    for name in names:
        m = _read_memo(os.path.join(MEMO_DIR, name))
        if m is not None:
            m["id"] = name
            out.append(m)
    sys.stdout.write(json.dumps(out))


def delete_memo(fid):
    try:
        os.remove(os.path.join(MEMO_DIR, os.path.basename(fid)))
    except OSError:
        pass
    sys.stdout.write(json.dumps({"ok": True}))


def repolish_memo(fid, claude_model, local_model):
    path = os.path.join(MEMO_DIR, os.path.basename(fid))
    m = _read_memo(path)
    if m is None:
        sys.stdout.write(json.dumps({"ok": False, "error": "memo not found"}))
        return
    src = m["raw"] or m["text"]           # re-polish from the original transcript
    try:
        out = polish(src, claude_model, local_model)
    except Exception as e:
        notify("Polish failed", str(e), critical=True)
        sys.stdout.write(json.dumps({"ok": False, "error": str(e)}))
        return
    created = m["created"] or datetime.datetime.now().isoformat(timespec="seconds")
    _write_memo(path, created, m["type"], True, out, src)   # keep the original as unpolished
    clip(out)
    notify("Polished", out, copy_text=out)
    sys.stdout.write(json.dumps({"ok": True}))


## ---- org-agenda integration --------------------------------------------------
# a task memo becomes a real TODO in ~/org/inbox.org with a DEADLINE parsed from
# natural language ("tomorrow", "next week", "next Friday", …); a note becomes a
# heading in ~/org/notes.org. Written through the running Emacs daemon so an open
# buffer stays consistent (falls back to a direct file append if the daemon is
# down). Matches the user's Doom capture format (see doom/config.org).

def _extract_json(s):
    s = s.strip()
    a, b = s.find("{"), s.rfind("}")
    if a != -1 and b > a:
        return json.loads(s[a:b + 1])
    raise ValueError("no JSON in model output")


def org_extract(text, claude_model, local_model):
    # -> (title, deadline_iso_or_empty). Resolve relative dates against today.
    today = datetime.date.today()
    system = (read_prompt(ORG_PROMPT)
              .replace("{TODAY}", today.isoformat())
              .replace("{WEEKDAY}", today.strftime("%A")))
    data = _extract_json(_llm(system, text, claude_model, local_model, json_mode=True))
    title = (data.get("title") or "").strip() or " ".join(text.split())[:80]
    deadline = (data.get("deadline") or "").strip()
    return title, deadline


def _org_date(iso):
    try:
        return datetime.date.fromisoformat(iso).strftime("<%Y-%m-%d %a>")
    except Exception:
        return ""


def _elisp_str(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def _emacs_append(path, entry):
    # insert at end of the file's (daemon) buffer and save, so an already-open
    # buffer doesn't clobber the append and the agenda picks it up immediately.
    el = ("(condition-case nil "
          "(progn (with-current-buffer (find-file-noselect %s) "
          "(goto-char (point-max)) (unless (bolp) (insert \"\\n\")) (insert %s) "
          "(save-buffer)) t) "
          "(error nil))") % (_elisp_str(path), _elisp_str(entry))
    try:
        r = subprocess.run(["emacsclient", "-e", el],
                           capture_output=True, text=True, timeout=10)
        return r.returncode == 0 and r.stdout.strip() == "t"
    except Exception:
        return False


def _append_org(path, entry):
    if _emacs_append(path, entry):
        return
    os.makedirs(os.path.dirname(path), exist_ok=True)   # daemon down -> write directly
    with open(path, "a") as f:
        f.write("\n" + entry)


def org_add(title, deadline, category, body=""):
    created = datetime.datetime.now().strftime("[%Y-%m-%d %a %H:%M]")
    if category == "todo":
        dl = _org_date(deadline)
        entry = "* TODO %s\n" % title
        if dl:
            entry += "DEADLINE: %s\n" % dl
        entry += "CREATED: %s\n" % created
        _append_org(ORG_INBOX, entry)
    else:
        entry = "* %s\nCREATED: %s\n" % (title, created)
        if body and body.strip() and body.strip() != title:
            entry += body.strip() + "\n"
        _append_org(ORG_NOTES, entry)


def main():
    argv = sys.argv
    if len(argv) >= 2 and argv[1] == "init":
        ensure_prompts()
        sys.stdout.write(json.dumps({"ok": True, "mode": "init", "error": ""}))
        return
    # memo-management subcommands (clipboard→Memos tab)
    if len(argv) >= 2 and argv[1] == "list":
        list_memos()
        return
    if len(argv) >= 3 and argv[1] == "delete":
        delete_memo(argv[2])
        return
    if len(argv) >= 3 and argv[1] == "repolish":
        cm = argv[3] if len(argv) > 3 else "claude-opus-4-8"
        lm = argv[4] if len(argv) > 4 else "qwen2.5:3b"
        repolish_memo(argv[2], cm, lm)
        return
    # in-pill setup subcommands (Transcribe tab): key status / store / model pull
    if len(argv) >= 2 and argv[1] == "status":
        cmd_status(argv[2] if len(argv) > 2 else "")
        return
    if len(argv) >= 4 and argv[1] == "setkey":
        cmd_setkey(argv[2], argv[3])
        return
    if len(argv) >= 3 and argv[1] == "pull":
        cmd_pull(argv[2])
        return

    # transcription:
    #   wav mode model language device vad claudeModel localModel memoType org orgCategory
    wav, mode, model, language, device, vadflag, claude_model = argv[1:8]
    local_model = argv[8] if len(argv) > 8 else "qwen2.5:3b"
    memo_type = argv[9] if len(argv) > 9 else "note"
    org_flag = argv[10] if len(argv) > 10 else "noorg"
    org_cat = argv[11] if len(argv) > 11 else "note"
    ensure_prompts()
    ok, err = True, ""
    try:
        text = transcribe(wav, model, language, device, vadflag == "vad")
        if not text:
            raise RuntimeError("nothing transcribed (silence?)")
        clip(text)                  # raw text lands first, whatever happens next
        final_text = text           # what gets stored / sent to org (polished if it lands)
        if mode == "polish":
            try:
                out = polish(text, claude_model, local_model)
                final_text = out
                clip(out)
                notify("Polished", out, copy_text=out)
            except Exception as e:
                ok, err = False, "polish: %s" % e
                notify("Polish failed",
                       "%s\n\n%s" % (e, text), critical=True, copy_text=text)
        else:
            notify("Transcribed", text, copy_text=text)
        # every transcription is stored permanently; when polish landed, keep the
        # original transcript too (the Memos tab can show/copy the unpolished text)
        try:
            polished_ok = (mode == "polish" and ok)
            store_memo(final_text, memo_type, polished_ok, raw=(text if polished_ok else ""))
        except Exception:
            pass
        if org_flag == "org":
            try:
                if org_cat == "todo":
                    # extract a clean task title + a deadline from the memo
                    title, deadline = org_extract(final_text, claude_model, local_model)
                    org_add(title, deadline, "todo")
                else:
                    flat = " ".join(final_text.split())
                    org_add(flat[:80], "", "note", body=final_text)
            except Exception:
                # extraction / daemon failed — fall back to a plain TODO/note so
                # nothing is lost (the full memo is also in ~/Documents/memos)
                try:
                    flat = " ".join(final_text.split())
                    org_add(flat[:80], "", org_cat, body=final_text)
                except Exception:
                    pass
    except Exception as e:
        ok, err = False, str(e)
        notify("Transcription failed", str(e), critical=True)
    finally:
        try:
            os.remove(wav)
        except OSError:
            pass
    sys.stdout.write(json.dumps({"ok": ok, "mode": mode, "error": err}))


if __name__ == "__main__":
    main()
