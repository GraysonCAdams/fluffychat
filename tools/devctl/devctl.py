#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
#
# SPDX-License-Identifier: AGPL-3.0-or-later
"""Drive a Seam build made with --dart-define=SEAM_DEV_CONTROL=true.

Reads the port and token the app wrote (devctl.json) and sends one request
per command. See docs/dev-control.md for every request and example.

Runs on Windows, in WSL and on Linux/macOS with only the standard library.
From WSL in NAT networking mode the app's 127.0.0.1 is not reachable, so the
request goes through Windows' own curl.exe instead.

Examples:
  devctl.py info
  devctl.py tap --tooltip "Emoji"
  devctl.py type "hello" --into --key composer --submit
  devctl.py measure emoji -- tap --tooltip "Emoji"
  devctl.py shot /tmp/seam.png
  devctl.py --android info
"""

import argparse
import glob
import json
import os
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ANDROID_PACKAGES = ("chat.fluffy.fluffychat.fork", "chat.fluffy.fluffychat")
DEFAULT_PORT = 47913


def is_wsl():
    try:
        with open("/proc/version") as f:
            return "microsoft" in f.read().lower()
    except OSError:
        return False


def token_file():
    """The newest devctl.json the Windows app wrote, or $DEVCTL_FILE."""
    if os.environ.get("DEVCTL_FILE"):
        return os.environ["DEVCTL_FILE"]
    if os.name == "nt":
        return os.path.join(os.environ["LOCALAPPDATA"], "Seam", "devctl.json")
    if is_wsl():
        found = glob.glob("/mnt/c/Users/*/AppData/Local/Seam/devctl.json")
        if found:
            return max(found, key=os.path.getmtime)
    sys.exit("No devctl.json found: is a dev control build running? "
             "(set DEVCTL_FILE to point at it)")


def android_config(serial):
    """Forwards the device's port to this machine and reads its token."""
    adb = ["adb"] + (["-s", serial] if serial else [])
    for package in ANDROID_PACKAGES:
        path = f"/sdcard/Android/data/{package}/files/devctl.json"
        result = subprocess.run(adb + ["shell", "cat", path],
                                capture_output=True, text=True)
        if result.returncode == 0 and result.stdout.strip().startswith("{"):
            config = json.loads(result.stdout)
            port = config["port"]
            subprocess.run(adb + ["forward", f"tcp:{port}", f"tcp:{port}"],
                           check=True, capture_output=True)
            return config
    sys.exit("No devctl.json on the device: is a dev control build running?")


class Client:
    def __init__(self, config, via_curl):
        self.base = f"http://127.0.0.1:{config['port']}"
        self.token = config["token"]
        self.via_curl = via_curl

    def request(self, method, route, body=None, query=None):
        """Returns (status, content type, bytes)."""
        url = self.base + route
        if query:
            url += "?" + urllib.parse.urlencode(
                {k: v for k, v in query.items() if v is not None})
        data = json.dumps(body or {}).encode() if method == "POST" else None
        if self.via_curl:
            return self._curl(method, url, data)
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Authorization", f"Bearer {self.token}")
        if data is not None:
            req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=120) as r:
                return r.status, r.headers.get("Content-Type", ""), r.read()
        except urllib.error.HTTPError as e:
            return e.code, e.headers.get("Content-Type", ""), e.read()

    def _curl(self, method, url, data):
        marker = b"\n--devctl-status:"
        cmd = ["curl.exe", "-s", "-S", "-X", method, url,
               "-H", f"Authorization: Bearer {self.token}",
               "-w", marker.decode() + "%{http_code}:%{content_type}"]
        if data is not None:
            cmd += ["-H", "Content-Type: application/json",
                    "--data-binary", "@-"]
        result = subprocess.run(cmd, input=data, capture_output=True)
        if result.returncode != 0:
            sys.exit(f"curl.exe failed: {result.stderr.decode().strip()}")
        body, _, tail = result.stdout.rpartition(marker)
        status, _, ctype = tail.decode().partition(":")
        return int(status), ctype, body


def reachable(config):
    try:
        with socket.create_connection(("127.0.0.1", config["port"]), 0.5):
            return True
    except OSError:
        return False


TARGET_FLAGS = {
    "key": "key", "text": "text", "contains": "textContains",
    "type": "type", "label": "label", "label_contains": "labelContains",
    "tooltip": "tooltip", "id": "identifier", "x": "x", "y": "y",
    "index": "index", "view": "view",
}


def add_target(p):
    g = p.add_argument_group("target (one of key/text/contains/type, "
                             "label/label-contains/tooltip/id, or x+y)")
    g.add_argument("--key", help="a ValueKey's value")
    g.add_argument("--text", help="a Text widget's exact text")
    g.add_argument("--contains", help="text that a Text widget contains")
    g.add_argument("--type", help="a widget's class name, e.g. TextField")
    g.add_argument("--label", help="a semantics label, exactly")
    g.add_argument("--label-contains",
                   help="text in a semantics label, value, hint or tooltip")
    g.add_argument("--tooltip", help="a semantics tooltip, exactly")
    g.add_argument("--id", help="a semantics identifier")
    g.add_argument("--x", type=float)
    g.add_argument("--y", type=float)
    g.add_argument("--index", type=int, help="which match (default 0)")
    g.add_argument("--view", type=int, help="the Flutter view id")


def target_of(a):
    return {wire: getattr(a, flag) for flag, wire in TARGET_FLAGS.items()
            if getattr(a, flag, None) is not None}


def build_parser():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--android", action="store_true",
                   help="talk to the app on an adb device")
    p.add_argument("--serial", help="adb device serial")
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("info", help="app, views, refresh rate, route")
    sub.add_parser("route", help="the router's current location")

    s = sub.add_parser("widgets", help="find widgets in the element tree")
    add_target(s)
    s.add_argument("--limit", type=int)

    s = sub.add_parser("sem", help="list semantics nodes (turns semantics on)")
    add_target(s)
    s.add_argument("--limit", type=int)
    sub.add_parser("sem-release", help="turn semantics back off")

    for name, helptext in [("tap", "tap/click a target"),
                           ("longpress", "press and hold"),
                           ("rightclick", "secondary mouse click"),
                           ("hover", "move the injected mouse over a target")]:
        s = sub.add_parser(name, help=helptext)
        add_target(s)
        s.add_argument("--kind", choices=["mouse", "touch"])
        if name == "tap":
            s.add_argument("--count", type=int, help="2 for a double tap")
            s.add_argument("--hold-ms", type=int)
        if name == "hover":
            s.add_argument("--leave", action="store_true",
                           help="take the injected mouse off the app")

    s = sub.add_parser("scroll", help="mouse wheel over a target")
    add_target(s)
    s.add_argument("--dx", type=float, default=0)
    s.add_argument("--dy", type=float, default=0,
                   help="pixels; positive scrolls down")
    s.add_argument("--steps", type=int)
    s.add_argument("--interval-ms", type=int)

    s = sub.add_parser("drag", help="press, move and release")
    add_target(s)
    s.add_argument("--dx", type=float, default=0)
    s.add_argument("--dy", type=float, default=0)
    s.add_argument("--ms", type=int, help="duration (default 300)")
    s.add_argument("--kind", choices=["mouse", "touch"])

    s = sub.add_parser("type", help="type into the focused field")
    s.add_argument("value")
    s.add_argument("--into", action="store_true",
                   help="tap the target given by the target flags first")
    add_target(s)
    s.add_argument("--submit", action="store_true")
    s.add_argument("--replace", action="store_true")

    s = sub.add_parser("key", help="press keys, e.g. ctrl+k enter escape")
    s.add_argument("keys", nargs="+")

    s = sub.add_parser("go", help="open a route, e.g. /rooms/settings")
    s.add_argument("location")
    s = sub.add_parser("room", help="open a room by id")
    s.add_argument("room_id")

    s = sub.add_parser("wait", help="wait for a target to appear (or go)")
    add_target(s)
    s.add_argument("--gone", action="store_true")
    s.add_argument("--timeout-ms", type=int)

    s = sub.add_parser("shot", help="screenshot the app's own rendering")
    s.add_argument("out", help="PNG path to write")
    add_target(s)
    s.add_argument("--scale", type=float,
                   help="1 = physical pixels (default)")

    s = sub.add_parser("mark", help="start a frame-timing span")
    s.add_argument("name", nargs="?", default="start")
    s = sub.add_parser("frames", help="frame timings since a mark")
    s.add_argument("--since")
    s.add_argument("--until")
    s.add_argument("--wait", type=int, help="ms to wait for timings")
    s.add_argument("--detail", action="store_true")
    sub.add_parser("frames-clear", help="drop recorded frames and marks")

    s = sub.add_parser("measure",
                       help="mark, run one command, wait, print frames: "
                            "measure NAME [--settle-ms N] -- tap --tooltip X")
    s.add_argument("name")
    s.add_argument("--settle-ms", type=int, default=1500,
                   help="how long to record after the command")
    # The command after "--" is split off in parse() before argparse runs.

    s = sub.add_parser("logs", help="the app's last log lines")
    s.add_argument("--lines", type=int)
    s.add_argument("--level",
                   choices=["wtf", "error", "warning", "info", "debug",
                            "verbose"])
    s.add_argument("--since", type=int, help="only lines after this seq")

    s = sub.add_parser("raw", help="send any request: raw POST /tap '{...}'")
    s.add_argument("method")
    s.add_argument("route")
    s.add_argument("body", nargs="?")
    return p


def run(client, a):
    """Sends the request for parsed args [a]; returns (status, ctype, body)."""
    c = a.cmd
    t = target_of(a)
    if c == "info":
        return client.request("GET", "/info")
    if c == "route":
        return client.request("GET", "/route")
    if c == "widgets":
        return client.request("GET", "/widgets", query={**t, "limit": a.limit})
    if c == "sem":
        return client.request("GET", "/semantics",
                              query={**t, "limit": a.limit})
    if c == "sem-release":
        return client.request("POST", "/semantics/release")
    if c in ("tap", "longpress", "rightclick", "hover"):
        body = {**t}
        if a.kind:
            body["kind"] = a.kind
        if c == "tap":
            if a.count:
                body["count"] = a.count
            if a.hold_ms:
                body["holdMs"] = a.hold_ms
        if c == "hover" and a.leave:
            body["leave"] = True
        return client.request("POST", "/" + c, body)
    if c == "scroll":
        body = {**t, "dx": a.dx, "dy": a.dy}
        if a.steps:
            body["steps"] = a.steps
        if a.interval_ms:
            body["intervalMs"] = a.interval_ms
        return client.request("POST", "/scroll", body)
    if c == "drag":
        body = {**t, "dx": a.dx, "dy": a.dy}
        if a.ms:
            body["durationMs"] = a.ms
        if a.kind:
            body["kind"] = a.kind
        return client.request("POST", "/drag", body)
    if c == "type":
        body = {"value": a.value, "submit": a.submit, "replace": a.replace}
        if a.into:
            body.update(t)
        return client.request("POST", "/type", body)
    if c == "key":
        return client.request("POST", "/key", {"keys": a.keys})
    if c == "go":
        return client.request("POST", "/go", {"location": a.location})
    if c == "room":
        return client.request("POST", "/go", {"roomId": a.room_id})
    if c == "wait":
        body = {**t, "gone": a.gone}
        if a.timeout_ms:
            body["timeoutMs"] = a.timeout_ms
        return client.request("POST", "/wait", body)
    if c == "shot":
        status, ctype, data = client.request(
            "GET", "/screenshot", query={**t, "scale": a.scale})
        if status == 200 and ctype.startswith("image/png"):
            with open(a.out, "wb") as f:
                f.write(data)
            return 200, "application/json", json.dumps(
                {"ok": True, "file": os.path.abspath(a.out),
                 "bytes": len(data)}).encode()
        return status, ctype, data
    if c == "mark":
        return client.request("POST", "/frames/mark", {"name": a.name})
    if c == "frames":
        return client.request("GET", "/frames", query={
            "since": a.since, "until": a.until, "wait": a.wait,
            "detail": "1" if a.detail else None})
    if c == "frames-clear":
        return client.request("POST", "/frames/clear")
    if c == "measure":
        if not a.rest:
            sys.exit("measure needs a command after --")
        inner = build_parser().parse_args(a.rest)
        client.request("POST", "/frames/mark", {"name": a.name})
        status, ctype, data = run(client, inner)
        if status != 200:
            return status, ctype, data
        time.sleep(a.settle_ms / 1000)
        client.request("POST", "/frames/mark", {"name": a.name + ":end"})
        return client.request("GET", "/frames", query={
            "since": a.name, "until": a.name + ":end"})
    if c == "logs":
        return client.request("GET", "/logs", query={
            "lines": a.lines, "level": a.level, "since": a.since})
    if c == "raw":
        body = json.loads(a.body) if a.body else None
        query = None
        if a.method.upper() == "GET" and body:
            query, body = body, None
        return client.request(a.method.upper(), a.route, body, query)
    raise SystemExit(f"unknown command {c}")


def parse(argv):
    """Parses [argv]; for measure, what follows "--" is the inner command."""
    rest = []
    if "measure" in argv and "--" in argv:
        cut = argv.index("--")
        argv, rest = argv[:cut], argv[cut + 1:]
    a = build_parser().parse_args(argv)
    a.rest = rest
    return a


def main():
    a = parse(sys.argv[1:])
    if a.android:
        config = android_config(a.serial)
        via_curl = False
    else:
        with open(token_file()) as f:
            config = json.load(f)
        via_curl = is_wsl() and not reachable(config)
    status, ctype, data = run(Client(config, via_curl), a)
    text = data.decode(errors="replace")
    if "json" in ctype:
        try:
            text = json.dumps(json.loads(text), indent=2, ensure_ascii=False)
        except ValueError:
            pass
    print(text)
    sys.exit(0 if status == 200 else 1)


if __name__ == "__main__":
    main()
