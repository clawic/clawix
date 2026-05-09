#!/usr/bin/env python3
import json
import os
import queue
import random
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

from e2e_bridge_daemon import BIN, ROOT, WebSocket, build


class FakeOpenCode:
    def __init__(self):
        now = int(time.time() * 1000)
        self.sessions = {
            "oc-existing": {
                "id": "oc-existing",
                "slug": "existing",
                "projectID": "project-e2e",
                "directory": "/tmp/clawix-opencode-e2e",
                "title": "OpenCode existing",
                "version": "e2e",
                "time": {"created": now - 10_000, "updated": now - 5_000},
            }
        }
        self.messages = {
            "oc-existing": [
                self.user_message("oc-existing", "user-existing", "existing prompt", now - 9_000),
                self.assistant_message("oc-existing", "assistant-existing", "existing answer", now - 8_000, completed=True),
            ]
        }
        self.events = []
        self.event_connected = threading.Event()
        self.permission_replied = threading.Event()
        self.abort_seen = threading.Event()

    def user_message(self, sid, mid, text, created):
        return {
            "info": {
                "id": mid,
                "sessionID": sid,
                "role": "user",
                "time": {"created": created},
                "agent": "build",
                "model": {"providerID": "deepseekv4", "modelID": "deepseek-v4-pro"},
            },
            "parts": [{"id": f"{mid}-text", "sessionID": sid, "messageID": mid, "type": "text", "text": text}],
        }

    def assistant_message(self, sid, mid, text, created, completed=False, with_work=False):
        info = {
            "id": mid,
            "sessionID": sid,
            "role": "assistant",
            "time": {"created": created},
            "parentID": "parent",
            "modelID": "deepseek-v4-pro",
            "providerID": "deepseekv4",
            "mode": "build",
            "agent": "build",
            "path": {"cwd": "/tmp/clawix-opencode-e2e", "root": "/tmp/clawix-opencode-e2e"},
            "cost": 0,
            "tokens": {"input": 1, "output": 1, "reasoning": 0, "cache": {"read": 0, "write": 0}},
        }
        if completed:
            info["time"]["completed"] = created + 100
            info["finish"] = "stop"
        parts = [{"id": f"{mid}-text", "sessionID": sid, "messageID": mid, "type": "text", "text": text}]
        if with_work:
            parts.append({
                "id": f"{mid}-tool",
                "sessionID": sid,
                "messageID": mid,
                "type": "tool",
                "callID": "call-e2e",
                "tool": "bash",
                "state": {
                    "status": "completed",
                    "input": {"cmd": "pwd"},
                    "output": "/tmp/clawix-opencode-e2e",
                    "title": "pwd",
                    "metadata": {},
                    "time": {"start": created, "end": created + 50},
                },
            })
            parts.append({
                "id": f"{mid}-patch",
                "sessionID": sid,
                "messageID": mid,
                "type": "patch",
                "hash": "abc123",
                "files": ["Sources/App.swift"],
            })
        return {"info": info, "parts": parts}

    def publish(self, event):
        dead = []
        for q in self.events:
            try:
                q.put_nowait(event)
            except Exception:
                dead.append(q)
        for q in dead:
            self.events.remove(q)


def make_handler(fake: FakeOpenCode):
    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *_):
            return

        def send_json(self, obj, status=200):
            data = json.dumps(obj).encode()
            self.send_response(status)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def read_json(self):
            length = int(self.headers.get("Content-Length") or 0)
            if length == 0:
                return {}
            return json.loads(self.rfile.read(length).decode())

        def do_GET(self):
            path = urlparse(self.path).path
            if path == "/config":
                return self.send_json({"model": "deepseekv4/deepseek-v4-pro"})
            if path == "/session":
                return self.send_json(list(fake.sessions.values()))
            if path == "/global/event":
                q = queue.Queue()
                fake.events.append(q)
                fake.event_connected.set()
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Cache-Control", "no-cache")
                self.end_headers()
                try:
                    self.wfile.write(b": ok\n\n")
                    self.wfile.flush()
                    while True:
                        event = q.get(timeout=30)
                        self.wfile.write(f"data: {json.dumps(event)}\n\n".encode())
                        self.wfile.flush()
                except Exception:
                    if q in fake.events:
                        fake.events.remove(q)
                return
            if path.startswith("/session/") and path.endswith("/message"):
                sid = path.split("/")[2]
                return self.send_json(fake.messages.get(sid, []))
            if path.startswith("/session/"):
                sid = path.split("/")[2]
                return self.send_json(fake.sessions[sid])
            self.send_json({"error": path}, status=404)

        def do_POST(self):
            path = urlparse(self.path).path
            if path == "/session":
                body = self.read_json()
                sid = f"oc-{len(fake.sessions)+1}"
                now = int(time.time() * 1000)
                session = {
                    "id": sid,
                    "slug": sid,
                    "projectID": "project-e2e",
                    "directory": "/tmp/clawix-opencode-e2e",
                    "title": body.get("title") or "OpenCode chat",
                    "version": "e2e",
                    "time": {"created": now, "updated": now},
                    "permission": body.get("permission"),
                }
                fake.sessions[sid] = session
                fake.messages[sid] = []
                fake.publish({"type": "session.created", "properties": {"sessionID": sid, "info": session}})
                return self.send_json(session)
            if path.startswith("/session/") and path.endswith("/message"):
                sid = path.split("/")[2]
                body = self.read_json()
                text = "\n".join(p.get("text", "") for p in body.get("parts", []) if p.get("type") == "text")
                now = int(time.time() * 1000)
                fake.messages[sid].append(fake.user_message(sid, f"user-{now}", text, now))
                assistant_id = f"assistant-{now}"
                if "slow" not in text:
                    fake.messages[sid].append(
                        fake.assistant_message(sid, assistant_id, "hello from opencode", now, completed=True, with_work=True)
                    )

                def stream():
                    fake.publish({
                        "type": "message.part.delta",
                        "properties": {
                            "sessionID": sid,
                            "messageID": assistant_id,
                            "partID": f"{assistant_id}-text",
                            "field": "text",
                            "delta": "hello",
                        },
                    })
                    time.sleep(0.05)
                    fake.publish({
                        "type": "message.part.delta",
                        "properties": {
                            "sessionID": sid,
                            "messageID": assistant_id,
                            "partID": f"{assistant_id}-text",
                            "field": "text",
                            "delta": " from opencode",
                        },
                    })
                    fake.publish({
                        "type": "message.part.updated",
                        "properties": {
                            "sessionID": sid,
                            "part": {
                                "id": f"{assistant_id}-tool",
                                "sessionID": sid,
                                "messageID": assistant_id,
                                "type": "tool",
                                "callID": "call-e2e",
                                "tool": "bash",
                                "state": {
                                    "status": "completed",
                                    "input": {"cmd": "pwd"},
                                    "output": "/tmp/clawix-opencode-e2e",
                                    "title": "pwd",
                                    "metadata": {},
                                    "time": {"start": now, "end": now + 40},
                                },
                            },
                            "time": now + 40,
                        },
                    })
                    fake.publish({
                        "type": "message.part.updated",
                        "properties": {
                            "sessionID": sid,
                            "part": {
                                "id": f"{assistant_id}-patch",
                                "sessionID": sid,
                                "messageID": assistant_id,
                                "type": "patch",
                                "hash": "abc123",
                                "files": ["Sources/App.swift"],
                            },
                            "time": now + 50,
                        },
                    })
                    fake.publish({
                        "type": "permission.asked",
                        "properties": {
                            "id": "perm-e2e",
                            "sessionID": sid,
                            "permission": "bash",
                            "patterns": ["rm *"],
                            "metadata": {},
                            "always": [],
                        },
                    })
                    if "slow" in text:
                        return
                    msg = fake.messages[sid][-1]
                    fake.sessions[sid]["time"]["updated"] = now + 100
                    fake.publish({"type": "message.updated", "properties": {"sessionID": sid, "info": msg["info"]}})

                threading.Thread(target=stream, daemon=True).start()
                return self.send_json(fake.messages[sid])
            if path.startswith("/session/") and path.endswith("/abort"):
                fake.abort_seen.set()
                return self.send_json(True)
            if path == "/permission/perm-e2e/reply":
                body = self.read_json()
                if body.get("reply") == "reject":
                    fake.permission_replied.set()
                return self.send_json(True)
            self.send_json({"error": path}, status=404)

        def do_PATCH(self):
            path = urlparse(self.path).path
            if path.startswith("/session/"):
                sid = path.split("/")[2]
                body = self.read_json()
                session = fake.sessions[sid]
                if "title" in body:
                    session["title"] = body["title"]
                if "time" in body and "archived" in body["time"]:
                    if body["time"]["archived"] is None:
                        session["time"].pop("archived", None)
                    else:
                        session["time"]["archived"] = body["time"]["archived"]
                fake.publish({"type": "session.updated", "properties": {"sessionID": sid, "info": session}})
                return self.send_json(session)
            self.send_json({"error": path}, status=404)

    return Handler


def main():
    build()
    fake = FakeOpenCode()
    http_port = random.randint(29000, 36000)
    ws_port = random.randint(39000, 49000)
    token = "test-token-" + os.urandom(16).hex()
    server = ThreadingHTTPServer(("127.0.0.1", http_port), make_handler(fake))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    with tempfile.TemporaryDirectory(prefix="clawix-opencode-e2e-") as raw:
        env = os.environ.copy()
        env.update(
            {
                "CLAWIX_AGENT_RUNTIME": "opencode",
                "CLAWIX_OPENCODE_BASE_URL": f"http://127.0.0.1:{http_port}",
                "CLAWIX_BRIDGED_PORT": str(ws_port),
                "CLAWIX_BRIDGED_BEARER": token,
                "CLAWIX_BRIDGED_DISABLE_BONJOUR": "1",
                "HOME": raw,
            }
        )
        daemon = subprocess.Popen([str(BIN)], cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.time() + 8
            ws = None
            while time.time() < deadline:
                try:
                    ws = WebSocket(ws_port)
                    break
                except OSError:
                    time.sleep(0.05)
            if ws is None:
                _, err = daemon.communicate(timeout=1)
                raise AssertionError(err)

            ws.send_json({"schemaVersion": 2, "type": "auth", "token": token, "deviceName": "E2E", "clientKind": "ios"})
            ws.recv_until(lambda f: f["type"] == "authOk")
            snapshot = ws.recv_until(lambda f: f["type"] == "chatsSnapshot" and f["chats"])
            chat_id = snapshot["chats"][0]["id"]
            assert snapshot["chats"][0]["threadId"] == "oc-existing"

            ws.send_json({"schemaVersion": 2, "type": "openChat", "chatId": chat_id})
            ws.recv_until(
                lambda f: (
                    f["type"] == "messagesSnapshot"
                    and f["chatId"] == chat_id
                    and any(m["content"] == "existing answer" for m in f["messages"])
                )
                or (
                    f["type"] == "messageAppended"
                    and f["chatId"] == chat_id
                    and f["message"]["content"] == "existing answer"
                )
            )

            ws.send_json({"schemaVersion": 2, "type": "requestRateLimits"})
            ws.recv_until(
                lambda f: f["type"] == "rateLimitsSnapshot"
                and f.get("rateLimits")
                and "deepseek-v4-pro" in f["rateLimits"]["limitName"]
            )
            assert fake.event_connected.wait(5), "OpenCode event stream was not opened"

            ws.send_json({"schemaVersion": 2, "type": "sendPrompt", "chatId": chat_id, "text": "new prompt"})
            time.sleep(0.2)
            assert fake.permission_replied.wait(5), "permission request was not rejected"

            ws.send_json({"schemaVersion": 2, "type": "openChat", "chatId": chat_id})
            hydrated = ws.recv_until(
                lambda f: f["type"] == "messagesSnapshot"
                and f["chatId"] == chat_id
                and any(m["content"] == "hello from opencode" for m in f["messages"])
                and any(m.get("workSummary") for m in f["messages"] if m["role"] == "assistant")
            )
            assistant = [m for m in hydrated["messages"] if m["role"] == "assistant" and m.get("workSummary")][-1]
            kinds = {item["kind"] for item in assistant["workSummary"]["items"]}
            assert {"command", "fileChange"}.issubset(kinds), assistant

            image_chat = "11111111-2222-4333-8444-555555555555"
            ws.send_json({"schemaVersion": 2, "type": "openChat", "chatId": image_chat})
            ws.send_json({
                "schemaVersion": 2,
                "type": "sendPrompt",
                "chatId": image_chat,
                "text": "describe this",
                "attachments": [{
                    "id": "image-e2e",
                    "kind": "image",
                    "mimeType": "image/png",
                    "filename": "sample.png",
                    "dataBase64": "iVBORw0KGgo=",
                }],
            })
            time.sleep(0.1)
            ws.send_json({"schemaVersion": 2, "type": "openChat", "chatId": image_chat})
            ws.recv_until(
                lambda f: f["type"] == "messagesSnapshot"
                and f["chatId"] == image_chat
                and any(m["role"] == "user" and "[image fallback]" in m["content"] and m["attachments"] for m in f["messages"])
            )

            slow_chat = "22222222-2222-4333-8444-555555555555"
            ws.send_json({"schemaVersion": 2, "type": "openChat", "chatId": slow_chat})
            ws.send_json({"schemaVersion": 2, "type": "sendPrompt", "chatId": slow_chat, "text": "slow turn"})
            time.sleep(0.1)
            ws.send_json({"schemaVersion": 2, "type": "interruptTurn", "chatId": slow_chat})
            ws.recv_until(
                lambda f: f["type"] == "chatUpdated"
                and f["chat"]["id"] == slow_chat
                and f["chat"]["lastTurnInterrupted"] is True
            )
            assert fake.abort_seen.wait(5), "abort endpoint was not called"

            ws.send_json({"schemaVersion": 2, "type": "archiveChat", "chatId": image_chat})
            ws.recv_until(lambda f: f["type"] == "chatUpdated" and f["chat"]["id"] == image_chat and f["chat"]["isArchived"] is True)
            ws.send_json({"schemaVersion": 2, "type": "unarchiveChat", "chatId": image_chat})
            ws.recv_until(lambda f: f["type"] == "chatUpdated" and f["chat"]["id"] == image_chat and f["chat"]["isArchived"] is False)
            ws.close()
        finally:
            daemon.terminate()
            try:
                daemon.wait(timeout=5)
            except subprocess.TimeoutExpired:
                daemon.kill()
                daemon.wait(timeout=5)
            server.shutdown()


if __name__ == "__main__":
    main()
