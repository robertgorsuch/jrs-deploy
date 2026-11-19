#!/usr/bin/env python3
"""mock_jrs.py -- a recorded JasperReports Server for offline tests.

Replays a recording (tests/recordings/<version>-<edition>/mappings.json, made by
scripts/record_server.ps1 against a live server) and logs EVERY request as one
JSON line so a test can prove that a plan-mode run issued no PUT/POST/DELETE.
Ported from jrsctl's recorded-server harness (ADR-0011): the adapter code under
test is the real thing; only the server is replayed.

    python mock_jrs.py --port 18081 --recording tests/recordings/10.0.0-PRO --log out/requests.jsonl

Behaviour (enough of REST v2 for the promote/compose/teardown/deploy scripts):
  * a request whose METHOD + PATH(+query) is in mappings.json answers as recorded
    (unless the resource was deleted/created during this session: the mock is
    stateful so apply-mode runs see their own effects)
  * GET  /rest_v2/serverInfo            -> recorded, else a 10.0.0 PRO default
  * GET  /rest_v2/resources<uri>        -> recorded/created body, else JRS-style 404
  * PUT  /rest_v2/resources<uri>        -> 201 (or 200 when it existed), remembers the uri
  * DELETE /rest_v2/resources<uri>      -> 204 when known, else 404; forgets it
  * POST|PUT /rest_v2/resources<folder> with a Content-Location: <src> header
                                        -> copy (POST) / move (PUT, forgets src) to
                                           <folder>/<leaf of src>; 201 + descriptor,
                                           404 when src is unknown
  * POST /rest_v2/export                -> {id}, state finished, exportFile = a small
                                           valid archive (index.xml naming the uris)
  * POST /rest_v2/import                -> {id}, state finished; the uploaded
                                           archive's index.xml <resource> uris become
                                           known (so a composed dashboard "appears")
  * with --jobs <fixture.json> a stateful scheduler:
      GET  /rest_v2/jobs[?reportUnitURI=]  -> {"jobsummary":[...]} (204 when none)
      GET  /rest_v2/jobs/{id}/state        -> {"value", "nextFireTime"} or 404
      POST /rest_v2/jobs/pause|resume|restart {"jobId":[..]} -> echoes the known ids;
           an EMPTY list acts on every job, like the real server, so a regression
           shows up in the states (the log line carries "jobIds": <count sent>)
  * anything else                       -> 404 {"errorCode":"mock.unmapped"}

The log line: {"ts","method","path","status"} (+ "jobIds" for job batch POSTs). Auth headers are ignored and
never logged.
"""
import argparse
import io
import json
import os
import re
import sys
import threading
import time
import zipfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit, unquote, parse_qs

DEFAULT_SERVER_INFO = {
    "version": "10.0.0", "edition": "PRO", "build": "mock", "licenseType": "Commercial",
    "dateFormatPattern": "yyyy-MM-dd", "datetimeFormatPattern": "yyyy-MM-dd'T'HH:mm:ss",
    "editionName": "Enterprise", "expiration": None, "features": "Fusion AHD EXP DB AUD ANA MT ",
}


class State:
    def __init__(self, recording_dir, log_path, webapp):
        self.lock = threading.Lock()
        self.webapp = webapp.rstrip("/")
        self.log_path = log_path
        self.mappings = {}          # (METHOD, path) -> mapping dict
        self.resources = {}         # uri -> body dict (created or recorded), current truth
        self.deleted = set()
        self.exports = {}           # id -> uris
        self.imports = {}           # id -> uris
        self.counter = 0
        self.jobs = None            # id -> job dict, only when --jobs gives a fixture
        self.recording_dir = recording_dir
        if recording_dir:
            mp = os.path.join(recording_dir, "mappings.json")
            if os.path.isfile(mp):
                with io.open(mp, encoding="utf-8") as f:
                    for m in json.load(f):
                        key = (m["method"].upper(), m["path"])
                        self.mappings[key] = m
                        if m["method"].upper() == "GET" and m["path"].startswith("/rest_v2/resources/") and "?" not in m["path"] and 200 <= int(m.get("status", 200)) < 300:
                            body = m.get("body")
                            if isinstance(body, dict):
                                self.resources[m["path"][len("/rest_v2/resources"):]] = body

    def next_id(self, prefix):
        with self.lock:
            self.counter += 1
            return "%s-%d" % (prefix, self.counter)

    def load_jobs(self, path):
        with io.open(path, encoding="utf-8-sig") as f:
            self.jobs = {int(j["id"]): dict(j) for j in json.load(f)}

    def log(self, method, path, status, extra=None):
        rec = {"ts": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "method": method, "path": path, "status": status}
        if extra:
            rec.update(extra)
        line = json.dumps(rec)
        with self.lock:
            with io.open(self.log_path, "a", encoding="utf-8") as f:
                f.write(line + "\n")


def make_zip(uris):
    """A minimal archive that import_resource/compose accept structurally."""
    buf = io.BytesIO()
    with zipfile.ZipFile(buf, "w", zipfile.ZIP_DEFLATED) as z:
        # a real JRS export writes the whole <export> element on ONE line; keep that shape
        idx = '<?xml version="1.0" encoding="UTF-8"?>\n<export exportedVersion="10.0.0"><module id="repositoryResources">'
        idx += "".join("<resource>%s</resource>" % u for u in uris)
        idx += "</module></export>"
        z.writestr("index.xml", idx)
        for u in uris:
            z.writestr("resources" + u + ".xml", '<reportUnit exportedWithPermissions="false"><folder>%s</folder><name>%s</name></reportUnit>' % (u.rsplit("/", 1)[0], u.rsplit("/", 1)[1]))
    return buf.getvalue()


def uris_from_zip(data):
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as z:
            names = z.namelist()
            if "index.xml" in names:
                idx = z.read("index.xml").decode("utf-8", "replace")
                found = re.findall(r"<resource>([^<]+)</resource>", idx)
                if found:
                    return found
            # fall back: every resources/<uri>.xml entry
            return ["/" + n[len("resources/"):-4] for n in names if n.startswith("resources/") and n.endswith(".xml") and "_files/" not in n]
    except Exception:
        return []


def multipart_file(body, content_type):
    m = re.search(r'boundary="?([^";]+)"?', content_type or "")
    if not m:
        return body
    boundary = ("--" + m.group(1)).encode()
    for part in body.split(boundary):
        if b"filename=" in part:
            i = part.find(b"\r\n\r\n")
            if i >= 0:
                data = part[i + 4:]
                if data.endswith(b"\r\n"):
                    data = data[:-2]
                return data
    return body


class Handler(BaseHTTPRequestHandler):
    server_version = "mock_jrs/1.0"
    state = None  # set by main

    def log_message(self, fmt, *args):  # silence default stderr logging
        pass

    def _send(self, status, body=None, ctype="application/json", raw=None):
        self.send_response(status)
        if raw is not None:
            data = raw
        elif body is None:
            data = b""
        elif isinstance(body, (dict, list)):
            data = json.dumps(body).encode("utf-8")
        else:
            data = str(body).encode("utf-8")
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        if data:
            self.wfile.write(data)
        return status

    def _path(self):
        p = self.path
        w = self.state.webapp
        if w and p.startswith(w):
            p = p[len(w):]
        return p

    def _read_body(self):
        n = int(self.headers.get("Content-Length") or 0)
        return self.rfile.read(n) if n > 0 else b""

    def _handle(self, method):
        st = self.state
        full = self._path()
        body = self._read_body()
        self._log_extra = None
        status = self._dispatch(method, full, body)
        st.log(method, full, status, self._log_extra)

    def _recorded(self, method, full):
        m = self.state.mappings.get((method, full))
        if not m:
            return None
        ctype = m.get("contentType", "application/json")
        b = m.get("body")
        if m.get("bodyFile"):
            with io.open(os.path.join(self.state.recording_dir, m["bodyFile"]), "rb") as f:
                return self._send(int(m.get("status", 200)), raw=f.read(), ctype=ctype)
        return self._send(int(m.get("status", 200)), body=b, ctype=ctype)

    def _dispatch(self, method, full, body):
        st = self.state
        split = urlsplit(full)
        path = unquote(split.path)
        # --- resources ------------------------------------------------------
        if path.startswith("/rest_v2/resources"):
            uri = path[len("/rest_v2/resources"):] or "/"
            if method == "GET":
                if uri in st.deleted:
                    return self._send(404, {"message": "Resource %s not found." % uri, "errorCode": "resource.not.found"})
                r = self._recorded(method, full)
                if r is not None:
                    return r
                if uri in st.resources and not split.query:
                    return self._send(200, st.resources[uri])
                if uri in st.resources and "expanded=true" in split.query:
                    return self._send(200, st.resources[uri])
                return self._send(404, {"message": "Resource %s not found." % uri, "errorCode": "resource.not.found"})
            src_hdr = self.headers.get("Content-Location")
            if src_hdr and method in ("POST", "PUT"):
                # copy (POST) / move (PUT): the URL is the destination folder, the leaf is kept
                src = "/" + "/".join(p for p in unquote(src_hdr).split("/") if p)
                known = src in st.resources and src not in st.deleted
                if not known:
                    return self._send(404, {"message": "Resource %s not found." % src, "errorCode": "resource.not.found"})
                target = uri.rstrip("/") + "/" + src.rsplit("/", 1)[-1]
                with st.lock:
                    doc = dict(st.resources[src])
                    doc["uri"] = target
                    st.resources[target] = doc
                    st.deleted.discard(target)
                    if method == "PUT":
                        st.deleted.add(src)
                        st.resources.pop(src, None)
                return self._send(201, doc)
            if method == "PUT":
                existed = uri in st.resources and uri not in st.deleted
                try:
                    doc = json.loads(body.decode("utf-8-sig")) if body else {}
                except Exception:
                    doc = {}
                if not isinstance(doc, dict):
                    doc = {}
                doc.setdefault("uri", uri)
                doc.setdefault("label", uri.rsplit("/", 1)[-1])
                with st.lock:
                    st.resources[uri] = doc
                    st.deleted.discard(uri)
                return self._send(200 if existed else 201, doc)
            if method == "DELETE":
                known = (uri in st.resources) and (uri not in st.deleted)
                with st.lock:
                    st.deleted.add(uri)
                    st.resources.pop(uri, None)
                return self._send(204 if known else 404, None if known else {"message": "Resource %s not found." % uri, "errorCode": "resource.not.found"})
            if method == "POST":
                return self._send(201, {"uri": uri})
        # --- serverInfo -------------------------------------------------------
        if path == "/rest_v2/serverInfo" and method == "GET":
            r = self._recorded(method, full)
            return r if r is not None else self._send(200, DEFAULT_SERVER_INFO)
        # --- export ------------------------------------------------------------
        if path == "/rest_v2/export" and method == "POST":
            try:
                # Windows PowerShell 5.1 writes the request file with a UTF-8 BOM: tolerate it
                req = json.loads(body.decode("utf-8-sig"))
                uris = list(req.get("uris") or [])
            except Exception:
                uris = []
            eid = st.next_id("exp")
            st.exports[eid] = uris
            return self._send(200, {"id": eid, "phase": "inprogress", "message": "Export in progress"})
        m = re.match(r"^/rest_v2/export/([^/]+)/state$", path)
        if m and method == "GET":
            return self._send(200, {"id": m.group(1), "phase": "finished", "message": "Export succeeded."})
        m = re.match(r"^/rest_v2/export/([^/]+)/exportFile$", path)
        if m and method == "GET":
            uris = st.exports.get(m.group(1), [])
            return self._send(200, raw=make_zip(uris), ctype="application/zip")
        # --- import ------------------------------------------------------------
        if path == "/rest_v2/import" and method == "POST":
            data = multipart_file(body, self.headers.get("Content-Type"))
            uris = uris_from_zip(data)
            iid = st.next_id("imp")
            st.imports[iid] = uris
            with st.lock:
                for u in uris:
                    st.deleted.discard(u)
                    st.resources.setdefault(u, {"uri": u, "label": u.rsplit("/", 1)[-1], "resources": [], "version": 0})
            return self._send(200, {"id": iid, "phase": "inprogress", "message": "Import in progress"})
        m = re.match(r"^/rest_v2/import/([^/]+)/state$", path)
        if m and method == "GET":
            return self._send(200, {"id": m.group(1), "phase": "finished", "message": "Import succeeded.", "warnings": []})
        # --- scheduler (only with --jobs) ---------------------------------------
        if st.jobs is not None and path.startswith("/rest_v2/jobs"):
            p = path.rstrip("/")
            if p == "/rest_v2/jobs" and method == "GET":
                q = parse_qs(split.query).get("reportUnitURI", [None])[0]
                items = [j for _, j in sorted(st.jobs.items()) if not q or j.get("reportUnitURI") == q]
                if not items:
                    return self._send(204)
                return self._send(200, {"jobsummary": [
                    {"id": j["id"], "version": 0, "label": j.get("label"), "reportUnitURI": j.get("reportUnitURI"),
                     "owner": j.get("owner"), "state": {"value": j.get("state", "NORMAL")}} for j in items]})
            m = re.match(r"^/rest_v2/jobs/(\d+)/state$", p)
            if m and method == "GET":
                j = st.jobs.get(int(m.group(1)))
                if j is None:
                    return self._send(404, {"message": "Job not found", "errorCode": "resource.not.found"})
                return self._send(200, {"nextFireTime": "2030-01-01T00:00:00-08:00", "value": j.get("state", "NORMAL")})
            m = re.match(r"^/rest_v2/jobs/(pause|resume|restart)$", p)
            if m and method == "POST":
                action = m.group(1)
                try:
                    ids = [int(i) for i in (json.loads(body.decode("utf-8-sig")).get("jobId") or [])] if body else []
                except Exception:
                    ids = []
                self._log_extra = {"jobIds": len(ids)}
                if not ids and action in ("pause", "resume"):
                    ids = sorted(st.jobs)          # mirror the real server: an empty list means EVERY job
                acted = [i for i in ids if i in st.jobs]
                with st.lock:
                    for i in acted:
                        if action == "pause":
                            st.jobs[i]["state"] = "PAUSED"
                        elif action == "resume" and st.jobs[i].get("state") == "PAUSED":
                            st.jobs[i]["state"] = "NORMAL"
                return self._send(200, {"jobId": acted})
        # --- anything recorded (jobs, permissions, ...) --------------------------
        r = self._recorded(method, full)
        if r is not None:
            return r
        return self._send(404, {"message": "unmapped %s %s" % (method, full), "errorCode": "mock.unmapped"})

    def do_GET(self):    self._handle("GET")
    def do_PUT(self):    self._handle("PUT")
    def do_POST(self):   self._handle("POST")
    def do_DELETE(self): self._handle("DELETE")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, required=True)
    ap.add_argument("--recording", default=None, help="directory holding mappings.json (optional)")
    ap.add_argument("--log", required=True, help="request log (JSON lines, appended)")
    ap.add_argument("--webapp", default="/jasperserver-pro")
    ap.add_argument("--jobs", default=None, help="JSON fixture [{id,label,reportUnitURI,owner,state}] enabling a stateful scheduler")
    a = ap.parse_args()
    Handler.state = State(a.recording, a.log, a.webapp)
    if a.jobs:
        Handler.state.load_jobs(a.jobs)
    with io.open(a.log, "a", encoding="utf-8"):
        pass
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), Handler)
    print("mock_jrs listening on http://127.0.0.1:%d%s (%d recorded mappings)" % (a.port, a.webapp, len(Handler.state.mappings)), flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == "__main__":
    main()
