#!/usr/bin/env python3
"""Activity Logger for agy agent profiles.

  agy_activity.py --agent pilot --ensure-tree [--dry-run]
  agy_activity.py --agent pilot --publish --task <slug>
  agy_activity.py --agent pilot --verify --task <slug>

Tree (inside collection "Dokumentasi Agents"):
  Activity Logger
  └── <Agent>            (Pilot / Coder / Professor)
      ├── activities     (index + log)
      ├── artefacts      (spec artefak agent itu)
      └── <YYMMDDhhmm>-<task>   (satu dokumen per run)
"""
import argparse
import json
import os
import re
import sys
from datetime import datetime

_here = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.environ.get("AGY_BIN_DIR", _here))
import outline_keton as ok  # noqa: E402

# file config yang sama dengan agy_task.sh, supaya state/ledger ketemu walau dipanggil langsung
_CFG = os.environ.get("AGY_CONFIG_FILE", os.path.expanduser("~/.config/agy-harness/env"))
if os.path.exists(_CFG):
    for _line in open(_CFG):
        _line = _line.strip()
        if _line and not _line.startswith("#") and "=" in _line:
            _k, _, _v = _line.partition("=")
            os.environ.setdefault(_k.strip(), _v.strip())

COLLECTION = os.environ.get("OUTLINE_COLLECTION", "Dokumentasi Agents")
STATE = os.environ.get("AGY_STATE_DIR") or os.path.join(
    os.environ.get("XDG_STATE_HOME", os.path.expanduser("~/.local/state")), "agy")
LEDGER = os.path.join(STATE, "ledger.jsonl")
ROOT_TITLE = "Activity Logger"

AGENTS = {
    "pilot": {
        "title": "Pilot",
        "role": "eksekutor operasional: menjalankan tugas lewat harness agy, lalu memverifikasi hasil",
        "artefacts": [
            ("HASIL.md", "ya", "hasil kerja; setiap klaim menyebut bukti `path:baris`"),
            ("ARTEFAK.json", "ya", "daftar file + sha256 + perintah yang dijalankan"),
        ],
        "limits": "tidak mengubah kode produksi, tidak menyentuh database, tidak destruktif di luar workdir",
    },
    "coder": {
        "title": "Coder",
        "role": "perubahan kode terbatas dan review teknis",
        "artefacts": [
            ("LAPORAN.md", "ya", "ringkasan perubahan + verifikasi + sisa risiko"),
            ("changes.patch", "ya", "diff lengkap perubahan"),
            ("verifikasi.txt", "ya", "output mentah perintah verifikasi, atau 'TIDAK ADA TES'"),
        ],
        "limits": "tidak menjalankan migrasi/DDL, tidak push git, tidak menyentuh file di luar daftar brief",
    },
    "professor": {
        "title": "Professor",
        "role": "riset & analisis bersumber, penyusunan laporan",
        "artefacts": [
            ("LAPORAN-RISET.md", "ya", "temuan; klaim tanpa sumber wajib ditandai TIDAK TERVERIFIKASI"),
            ("sumber.json", "ya", "daftar klaim → URL → tanggal akses"),
        ],
        "limits": "tidak menyimpulkan tanpa sumber yang bisa dicek; tidak menulis kode",
    },
}


def api_docs():
    cid = ok.resolve_collection(COLLECTION)
    return cid, ok.documents(cid)


def find(docs, title, parent_id=None):
    for d in docs:
        if d["title"] == title and (parent_id is None or d.get("parentDocumentId") == parent_id):
            return d
    return None


def ensure(cid, docs, title, parent_id, body):
    d = find(docs, title, parent_id)
    if d:
        ok.api("documents.update", {"id": d["id"], "text": body})
        print(f"EXISTS|{title}")
        return d["id"]
    payload = {"title": title, "collectionId": cid, "text": body, "publish": True}
    if parent_id:
        payload["parentDocumentId"] = parent_id
    created = ok.api("documents.create", payload)["data"]
    created = created.get("document", created)
    print(f"CREATED|{title}")
    docs.append(created)
    return created["id"]


def body_activities(agent):
    a = AGENTS[agent]
    return f"""# Activities — {a['title']}

Log kronologis setiap pemanggilan harness `agy` oleh agent ini.

- Nama dokumen anak: `YYMMDDhhmm-<task>` (tanggal + jam + menit, waktu lokal mesin)
- Model agy: `gemini-3.8-flash-high`
- Sumber data: ledger `/opt/data/tmp/agy/ledger.jsonl` + artefak tiap run

| Waktu | Task | Model | Token | Exit | Dokumen |
|---|---|---|---|---|---|
| _(diisi otomatis oleh `agy_activity.py --publish`)_ |
"""


def body_artefacts(agent):
    a = AGENTS[agent]
    rows = "\n".join(f"| `{f}` | {w} | {desc} |" for f, w, desc in a["artefacts"])
    return f"""# Artefak — {a['title']}

Peran: {a['role']}

| File | Wajib | Keterangan |
|---|---|---|
{rows}

## Aturan
- **Tanpa artefak = belum selesai.** Verifikasi dengan `agy_verify.sh --expect-file <nama>`.
- Artefak ditulis di workdir tugas, lalu dimirror ke `out/workdir/`.
- Laporan tanpa bukti (`path:baris`, output perintah, atau URL) dianggap tidak valid.

## Batas agent
{a['limits']}
"""


def body_root():
    rows = "\n".join(
        f"| [{a['title']}]({a['title']}) | {a['role']} |" for a in AGENTS.values()
    )
    return f"""# Activity Logger

Setiap pemanggilan harness `agy` oleh agent profile dicatat di sini — satu dokumen per run.

| Agent | Peran |
|---|---|
{rows}

## Struktur
```
Activity Logger
└── <Agent>
    ├── activities     index + log kronologis
    ├── artefacts      spesifikasi artefak agent itu
    └── YYMMDDhhmm-<task>   satu dokumen per run
```

## Konvensi nama
- Aktivitas: `YYMMDDhhmm-<slug>` (kronologis, unik per menit).
- Dokumen pengetahuan lainnya di koleksi ini memakai `DDMMYY · Judul Manusiawi`.
  Dua format ini sengaja berbeda: aktivitas = mesin-sortable, pengetahuan = enak dibaca.
"""


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


def body_activity(agent, task, row):
    a = AGENTS[agent]
    tdir = os.path.join(STATE, task)
    brief = ""
    bp = os.path.join(tdir, "brief.md")
    if os.path.exists(bp):
        brief = "\n".join(open(bp).read().splitlines()[:10])

    resp = ""
    rp = os.path.join(tdir, "out", "RESULT.json")
    if os.path.exists(rp):
        try:
            resp = (json.load(open(rp)).get("response") or "").strip()
        except Exception:
            resp = ""

    arts = []
    wd = os.path.join(tdir, "out", "workdir")
    if os.path.isdir(wd):
        for f in sorted(os.listdir(wd)):
            fp = os.path.join(wd, f)
            if os.path.isfile(fp):
                arts.append(f"`{f}` ({os.path.getsize(fp)} B)")
    if not arts:
        arts = ["_tidak ada file (run read-only)_"]

    # sertakan isi artefak markdown (maks 2 file, 6000 char masing-masing) supaya dokumen
    # aktivitas bisa dibaca berdiri sendiri tanpa membuka workdir
    md_blocks = []
    if os.path.isdir(wd):
        # file yang (baru) ditulis run ini punya mtime paling baru -> itu yang diutamakan
        cands = [os.path.join(wd, f) for f in os.listdir(wd)
                 if f.endswith(".md") and os.path.isfile(os.path.join(wd, f))]
        for fp in sorted(cands, key=lambda x: os.path.getmtime(x), reverse=True):
            try:
                body_md = open(fp, encoding="utf-8", errors="replace").read()[:6000]
            except OSError:
                continue
            f = os.path.basename(fp)
            md_blocks.append(f"## Isi `{f}`\n\n```markdown\n{body_md}\n```")
            if len(md_blocks) >= 2:
                break

    return f"""> Agent: {a['title']} · task: `{task}` · model agy: `{row.get('model','-')}`
> exit {row.get('exit','-')} · {row.get('tokens','-')} token · {row.get('wall','-')}s · ledger {row.get('ts','-')}

## Ringkasan
{resp[:800] if resp else '_response kosong_'}

## Artefak
""" + "\n".join(f"- {x}" for x in arts) + f"""

## Brief (10 baris pertama)
```
{brief or '_brief tidak tersedia_'}
```

{chr(10).join(md_blocks)}
"""


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--agent", required=True, choices=sorted(AGENTS))
    ap.add_argument("--ensure-tree", action="store_true")
    ap.add_argument("--publish", action="store_true")
    ap.add_argument("--verify", action="store_true")
    ap.add_argument("--task")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    agent = a.agent
    title = AGENTS[agent]["title"]

    if a.dry_run:
        print(f"DRYRUN|would ensure: {ROOT_TITLE} / {title} / activities / artefacts")
        if a.task:
            print(f"DRYRUN|would publish: {title}/activities/{datetime.now().strftime('%y%m%d%H%M')}-{a.task}")
        return

    cid, docs = api_docs()

    if a.ensure_tree or a.publish:
        root = ensure(cid, docs, ROOT_TITLE, None, body_root())
        agent_id = ensure(cid, docs, title, root, f"""# {title}

{AGENTS[agent]['role']}

Cabang ini berisi `activities`, `artefacts`, dan satu dokumen per run.
""")
        ensure(cid, docs, "activities", agent_id, body_activities(agent))
        ensure(cid, docs, "artefacts", agent_id, body_artefacts(agent))

    if not a.publish and not a.verify:
        return

    if not a.task:
        sys.exit("FAIL|--task wajib untuk --publish/--verify")

    root = find(docs, ROOT_TITLE)
    agent_doc = find(docs, title, root["id"]) if root else None
    acts = find(docs, "activities", agent_doc["id"]) if agent_doc else None
    if not acts:
        sys.exit("FAIL|tree belum ada — jalankan --ensure-tree dulu")

    if a.verify:
        hits = [d for d in docs if d.get("parentDocumentId") == acts["id"] and d["title"].endswith("-" + a.task)]
        if not hits:
            print(f"VERDICT|FAIL|doc tidak ditemukan untuk task {a.task}")
            sys.exit(1)
        print(f"VERDICT|PASS|{ok.URL}{hits[0]['url']}")
        return

    row = ledger_row(a.task)
    # judul diturunkan dari waktu RUN (ledger), bukan waktu publish -> republish = UPDATE, bukan duplikat
    try:
        stamp = datetime.fromisoformat(str(row.get("ts")).replace("Z", "+00:00")).strftime("%y%m%d%H%M")
    except Exception:
        stamp = datetime.now().strftime("%y%m%d%H%M")
    doc_title = f"{stamp}-{a.task}"
    existing = find(docs, doc_title, acts["id"])
    body = body_activity(agent, a.task, row)
    if existing:
        ok.api("documents.update", {"id": existing["id"], "text": body})
        print(f"ACTIVITY|UPDATED|{ok.URL}{existing['url']}")
        return
    created = ok.api("documents.create", {
        "title": doc_title, "collectionId": cid, "text": body,
        "parentDocumentId": acts["id"], "publish": True,
    })["data"]
    created = created.get("document", created)
    print(f"ACTIVITY|CREATED|{ok.URL}{created['url']}")


if __name__ == "__main__":
    main()
