#!/usr/bin/env python3
"""Minimal OutlineKeton client — one file, stdlib only.

  outline_keton.py collections
  outline_keton.py docs <collectionId>
  outline_keton.py create-doc --collection <name|id> --title "261120_Foo" [--parent <title|id>] --file body.md
  outline_keton.py update-doc --title "261120_Foo" --file body.md
  outline_keton.py info --title "261120_Foo"

Credentials: /opt/data/.config/outline-keton.env (OUTLINE_URL, OUTLINE_API_KEY).
The key never appears in argv, logs, or this script.
"""
import argparse
import json
import os
import sys
import urllib.error
import urllib.request

def _default_env_file():
    for c in (os.environ.get("OUTLINE_ENV_FILE"),
              os.path.expanduser("~/.config/outline-keton.env"),
              "/opt/data/.config/outline-keton.env"):
        if c and os.path.exists(c):
            return c
    return os.path.expanduser("~/.config/outline-keton.env")


ENV_FILE = _default_env_file()


def load_env(path=ENV_FILE):
    env = {}
    for line in open(path):
        line = line.strip()
        if line and not line.startswith("#") and "=" in line:
            k, v = line.split("=", 1)
            env[k.strip()] = v.strip()
    return env


ENV = load_env()
URL = ENV["OUTLINE_URL"].rstrip("/")
KEY = ENV["OUTLINE_API_KEY"]


def api(endpoint, payload=None):
    req = urllib.request.Request(
        f"{URL}/api/{endpoint}",
        data=json.dumps(payload or {}).encode(),
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=45) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        sys.exit(f"HTTP {e.code} on {endpoint}: {e.read().decode()[:400]}")


def collections():
    return api("collections.list", {"limit": 100})["data"]


def documents(cid):
    return api("documents.list", {"collectionId": cid, "limit": 100}).get("data", [])


def resolve_collection(ref):
    for c in collections():
        if ref in (c["id"], c["name"]):
            return c["id"]
    sys.exit(f"collection not found: {ref}")


def resolve_doc(cid, ref):
    for d in documents(cid):
        if ref in (d["id"], d["title"]):
            return d
    sys.exit(f"document not found: {ref}")


def main():
    p = argparse.ArgumentParser()
    p.add_argument("cmd", choices=["collections", "docs", "create-doc", "update-doc", "info"])
    p.add_argument("ref", nargs="?")
    p.add_argument("--collection")
    p.add_argument("--title")
    p.add_argument("--parent")
    p.add_argument("--file")
    a = p.parse_args()

    if a.cmd == "collections":
        for c in collections():
            print(c["id"], "|", c["name"], "|", c["permission"], "|", URL + c["url"])
        return

    cid = resolve_collection(a.collection or a.ref)

    if a.cmd == "docs":
        for d in documents(cid):
            print(("  " if d.get("parentDocumentId") else "") + d["title"], "|", URL + d["url"])
        return

    if a.cmd == "info":
        d = resolve_doc(cid, a.title or a.ref)
        print(json.dumps({k: d.get(k) for k in ("id", "title", "url", "parentDocumentId", "publishedAt")}, indent=2))
        return

    text = open(a.file).read() if a.file else ""
    if a.cmd == "update-doc":
        d = resolve_doc(cid, a.title)
        api("documents.update", {"id": d["id"], "text": text})
        print("updated", URL + d["url"])
        return

    payload = {"title": a.title, "collectionId": cid, "text": text, "publish": True}
    if a.parent:
        payload["parentDocumentId"] = resolve_doc(cid, a.parent)["id"]
    d = api("documents.create", payload)["data"]
    d = d.get("document", d)   # shape varies across Outline versions
    print("created", URL + d["url"])


if __name__ == "__main__":
    main()
