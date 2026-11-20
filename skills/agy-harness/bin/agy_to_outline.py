#!/usr/bin/env python3
"""Push an agy task result into OutlineKeton (collection "Dokumentasi Agents").

  agy_to_outline.py --task <slug> --title "261120_Nama-Kegiatan" [--parent "<title>"] [--file <md>]

Body source priority: --file → first .md artifact of the task → agy response text.
Metadata (exit/tokens/wall/model/artifacts) comes from the task's last ledger line.
Idempotent: existing document with the same title is updated, not duplicated.
"""
import argparse
import json
import os
import sys

_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("AGY_BIN_DIR", _here))
import outline_keton as ok  # noqa: E402  (loads env + api helper)

STATE = os.environ.get("AGY_STATE_DIR") or os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "agy")
LEDGER = os.path.join(STATE, "ledger.jsonl")
ROOT = STATE
COLLECTION = os.environ.get("OUTLINE_COLLECTION", "Dokumentasi Agents")


def ledger_row(task):
    last = None
    try:
        for line in open(LEDGER):
            line = line.strip()
            if not line:
                continue
            r = json.loads(line)
            if r.get("task") == task:
                last = r
    except FileNotFoundError:
        pass
    return last or {}


def pick_body(task, explicit):
    if explicit:
        return open(explicit).read(), explicit
    out = f"{ROOT}/{task}/out"
    wd = f"{out}/workdir"
    if os.path.isdir(wd):
        mds = sorted(f for f in os.listdir(wd) if f.endswith(".md"))
        if mds:
            p = os.path.join(wd, mds[0])
            return open(p).read(), p
    res = f"{out}/RESULT.json"
    if os.path.exists(res):
        return json.load(open(res)).get("response", ""), res
    return "", None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--task", required=True)
    ap.add_argument("--title", required=True)
    ap.add_argument("--parent")
    ap.add_argument("--file")
    a = ap.parse_args()

    row = ledger_row(a.task)
    body, source = pick_body(a.task, a.file)
    if not body.strip():
        sys.exit("FAIL|no content to publish")

    # naming convention: "DDMMYY · Judul Manusiawi" — warn (not block) on slug-ish titles
    import re
    if not re.match(r"^\d{6} · \S", a.title):
        print(f"WARN|judul belum ikut konvensi 'DDMMYY · Judul Manusiawi': {a.title}", file=sys.stderr)
    if len(a.title) > 70:
        print(f"WARN|judul {len(a.title)} karakter, maksimal disarankan 60", file=sys.stderr)

    meta = (
        f"> Sumber: `{source}` · task `{a.task}` · transport local · model `{row.get('model','-')}`"
        f" · exit {row.get('exit','-')} · {row.get('tokens','-')} token · {row.get('wall','-')}s"
        f" · ledger {row.get('ts','-')}\n\n"
    )
    text = f"{meta}---\n\n{body}\n"

    cid = ok.resolve_collection(COLLECTION)
    docs = ok.documents(cid)
    existing = next((d for d in docs if d["title"] == a.title), None)

    if existing:
        ok.api("documents.update", {"id": existing["id"], "text": text})
        print(f"UPDATED|{ok.URL}{existing['url']}")
        return

    payload = {"title": a.title, "collectionId": cid, "text": text, "publish": True}
    if a.parent:
        parent = next((d for d in docs if d["title"] == a.parent), None)
        if not parent:
            sys.exit(f"FAIL|parent not found: {a.parent}")
        payload["parentDocumentId"] = parent["id"]
    d = ok.api("documents.create", payload)["data"]
    d = d.get("document", d)
    print(f"CREATED|{ok.URL}{d['url']}")


if __name__ == "__main__":
    main()
