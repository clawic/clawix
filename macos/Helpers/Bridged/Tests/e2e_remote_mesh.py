#!/usr/bin/env python3
import json
import os
import random
import subprocess
import tempfile
import textwrap
import time
import urllib.error
import urllib.request
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / ".build" / "debug" / "clawix-bridge"


def build():
    subprocess.run(["swift", "build"], cwd=ROOT, check=True)


def write_fake_backend(tmp: Path, label: str) -> Path:
    backend = tmp / f"fake-backend-{label}.py"
    backend.write_text(
        textwrap.dedent(
            f"""\
            #!/usr/bin/env python3
            import json, sys, threading, time
            label = {label!r}

            def send(obj):
                print(json.dumps(obj), flush=True)

            for line in sys.stdin:
                if not line.strip():
                    continue
                msg = json.loads(line)
                mid = msg.get("id")
                method = msg.get("method")
                if method == "initialize":
                    send({{"jsonrpc":"2.0","id":mid,"result":{{}}}})
                elif method == "initialized":
                    pass
                elif method == "thread/list":
                    send({{"jsonrpc":"2.0","id":mid,"result":{{"data":[],"nextCursor":None}}}})
                elif method == "thread/start":
                    cwd = msg.get("params", {{}}).get("cwd")
                    send({{"jsonrpc":"2.0","id":mid,"result":{{"thread":{{"id":"thread-" + label,"cwd":cwd,"createdAt":"2026-05-05T10:00:00Z","cliVersion":"e2e"}},"model":None}}}})
                elif method == "turn/start":
                    thread_id = msg["params"]["threadId"]
                    turn_id = "turn-" + label
                    send({{"jsonrpc":"2.0","id":mid,"result":{{"turn":{{"id":turn_id}}}}}})
                    def stream():
                        send({{"jsonrpc":"2.0","method":"turn/started","params":{{"threadId":thread_id,"turn":{{"id":turn_id}}}}}})
                        time.sleep(0.05)
                        send({{"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{{"threadId":thread_id,"turnId":turn_id,"itemId":"assistant-" + label,"delta":"remote mesh says hi"}}}})
                        time.sleep(0.05)
                        send({{"jsonrpc":"2.0","method":"item/completed","params":{{"threadId":thread_id,"turnId":turn_id,"item":{{"id":"assistant-" + label,"type":"agentMessage","text":"remote mesh says hi"}}}}}})
                        send({{"jsonrpc":"2.0","method":"turn/completed","params":{{"threadId":thread_id,"turn":{{"id":turn_id}}}}}})
                    threading.Thread(target=stream, daemon=True).start()
                elif method == "turn/interrupt":
                    send({{"jsonrpc":"2.0","id":mid,"result":{{}}}})
                else:
                    send({{"jsonrpc":"2.0","id":mid,"result":{{}}}})
            """
        )
    )
    backend.chmod(0o755)
    return backend


def post(port: int, path: str, payload: dict):
    data = json.dumps(payload).encode()
    req = urllib.request.Request(
        f"http://127.0.0.1:{port}{path}",
        data=data,
        method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=8) as res:
            return json.loads(res.read().decode())
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        raise urllib.error.HTTPError(exc.url, exc.code, body or exc.msg, exc.headers, None)


def get(port: int, path: str):
    with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=8) as res:
        return json.loads(res.read().decode())


def wait_http(port: int):
    deadline = time.time() + 8
    while time.time() < deadline:
        try:
            return get(port, "/v1/mesh/identity")
        except Exception:
            time.sleep(0.05)
    raise AssertionError(f"http port {port} did not become ready")


def start_daemon(home: Path, label: str, ws_port: int, http_port: int, token: str):
    backend = write_fake_backend(home, label)
    env = os.environ.copy()
    env.update(
        {
            "CLAWIX_BRIDGE_BACKEND_PATH": str(backend),
            "CLAWIX_BRIDGE_PORT": str(ws_port),
            "CLAWIX_BRIDGE_HTTP_PORT": str(http_port),
            "CLAWIX_BRIDGE_BEARER": token,
            "CLAWIX_BRIDGE_DISABLE_BONJOUR": "1",
            "CLAWIX_BRIDGE_DEFAULTS_SUITE": f"clawix.mesh.e2e.{label}.{os.getpid()}",
            "CLAWIX_MESH_HOME": str(home / "mesh"),
            "HOME": str(home),
        }
    )
    return subprocess.Popen([str(BIN)], cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def main():
    build()
    with tempfile.TemporaryDirectory(prefix="clawix-remote-mesh-e2e-") as raw:
        root = Path(raw)
        a_home = root / "a"
        b_home = root / "b"
        a_home.mkdir()
        b_home.mkdir()
        a_ws = random.randint(41000, 45000)
        a_http = random.randint(45001, 49000)
        b_ws = random.randint(49001, 53000)
        b_http = random.randint(53001, 57000)
        a_token = "token-a-" + os.urandom(8).hex()
        b_token = "token-b-" + os.urandom(8).hex()
        daemons = [
            start_daemon(a_home, "a", a_ws, a_http, a_token),
            start_daemon(b_home, "b", b_ws, b_http, b_token),
        ]
        try:
            wait_http(a_http)
            b_identity = wait_http(b_http)

            allowed_workspace = str(b_home / "project")
            Path(allowed_workspace).mkdir()
            post(b_http, "/v1/mesh/workspaces", {"path": allowed_workspace, "label": "Project B"})

            linked = post(a_http, "/v1/mesh/link", {"host": "127.0.0.1", "httpPort": b_http, "token": b_token})
            assert linked["peer"]["nodeId"] == b_identity["nodeId"]
            peers = get(a_http, "/v1/mesh/peers")
            assert any(p["nodeId"] == b_identity["nodeId"] for p in peers["peers"])

            try:
                post(a_http, "/v1/mesh/remote-jobs", {
                    "peerId": b_identity["nodeId"],
                    "workspacePath": str(b_home / "denied"),
                    "prompt": "should fail",
                })
                raise AssertionError("disallowed workspace unexpectedly accepted")
            except urllib.error.HTTPError as exc:
                assert exc.code == 400

            started = post(a_http, "/v1/mesh/remote-jobs", {
                "peerId": b_identity["nodeId"],
                "workspacePath": allowed_workspace,
                "prompt": "run remotely",
            })
            job_id = started["job"]["id"]
            assert started["job"]["workspacePath"] == allowed_workspace

            deadline = time.time() + 8
            last = None
            while time.time() < deadline:
                last = get(b_http, f"/v1/mesh/jobs/{job_id}")
                if last["job"] and last["job"]["status"] == "completed":
                    break
                time.sleep(0.1)
            assert last and last["job"]["status"] == "completed", last
            assert last["job"].get("resultText") == "remote mesh says hi", last
            assert any(e["type"] == "delta" and "remote mesh" in e["message"] for e in last["events"]), last
        finally:
            for proc in daemons:
                proc.terminate()
            for proc in daemons:
                try:
                    proc.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    proc.kill()
                    proc.wait(timeout=5)


if __name__ == "__main__":
    main()
