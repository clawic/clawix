#!/usr/bin/env python3
import base64
import json
import os
import random
import socket
import struct
import subprocess
import sys
import tempfile
import textwrap
import threading
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
BIN = ROOT / ".build" / "debug" / "clawix-bridged"


def build():
    subprocess.run(["swift", "build"], cwd=ROOT, check=True)


def write_fake_backend(tmp: Path) -> Path:
    rollout = tmp / "rollout.jsonl"
    rollout.write_text(
        "\n".join(
            [
                json.dumps({"type": "session_meta", "payload": {"id": "thread-e2e", "cwd": str(tmp)}}),
                json.dumps({"type": "event_msg", "timestamp": "2026-05-05T10:00:00Z", "payload": {"type": "user_message", "message": "existing prompt"}}),
                json.dumps({"type": "event_msg", "timestamp": "2026-05-05T10:00:01Z", "payload": {"type": "agent_message", "message": "existing answer"}}),
                json.dumps({"type": "event_msg", "timestamp": "2026-05-05T10:00:02Z", "payload": {"type": "final_answer"}}),
            ]
        )
        + "\n"
    )
    backend = tmp / "fake-backend.py"
    backend.write_text(
        textwrap.dedent(
            f"""\
            #!/usr/bin/env python3
            import json, os, sys, threading, time
            rollout = {str(rollout)!r}
            cwd = {str(tmp)!r}

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
                    if os.environ.get("CLAWIX_E2E_HANG_THREAD_LIST") == "1":
                        continue
                    send({{"jsonrpc":"2.0","id":mid,"result":{{"data":[{{
                        "id":"thread-e2e",
                        "cwd":cwd,
                        "name":"E2E thread",
                        "preview":"existing prompt",
                        "path":rollout,
                        "createdAt":1777975200,
                        "updatedAt":1777975200,
                        "archived":False
                    }}],"nextCursor":None}}}})
                elif method == "thread/start":
                    send({{"jsonrpc":"2.0","id":mid,"result":{{"thread":{{"id":"thread-new","cwd":cwd,"createdAt":"2026-05-05T10:00:00Z","cliVersion":"e2e"}},"model":None}}}})
                elif method in ("thread/archive", "thread/unarchive"):
                    send({{"jsonrpc":"2.0","id":mid,"result":{{}}}})
                elif method == "turn/start":
                    thread_id = msg["params"]["threadId"]
                    turn_id = "turn-" + thread_id
                    send({{"jsonrpc":"2.0","id":mid,"result":{{"turn":{{"id":turn_id}}}}}})
                    def stream():
                        send({{"jsonrpc":"2.0","method":"turn/started","params":{{"threadId":thread_id,"turn":{{"id":turn_id}}}}}})
                        time.sleep(0.05)
                        send({{"jsonrpc":"2.0","method":"item/agentMessage/delta","params":{{"threadId":thread_id,"turnId":turn_id,"itemId":"assistant-e2e","delta":"hello from daemon"}}}})
                        time.sleep(0.05)
                        send({{"jsonrpc":"2.0","method":"item/completed","params":{{"threadId":thread_id,"turnId":turn_id,"item":{{"id":"assistant-e2e","type":"agentMessage","text":"hello from daemon"}}}}}})
                        send({{"jsonrpc":"2.0","method":"turn/completed","params":{{"threadId":thread_id,"turn":{{"id":turn_id}}}}}})
                    threading.Thread(target=stream, daemon=True).start()
                else:
                    send({{"jsonrpc":"2.0","id":mid,"result":{{}}}})
            """
        )
    )
    backend.chmod(0o755)
    return backend


class WebSocket:
    def __init__(self, port: int):
        self.sock = socket.create_connection(("127.0.0.1", port), timeout=5)
        key = base64.b64encode(os.urandom(16)).decode()
        request = (
            f"GET / HTTP/1.1\r\n"
            f"Host: 127.0.0.1:{port}\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            f"Sec-WebSocket-Key: {key}\r\n"
            "Sec-WebSocket-Version: 13\r\n\r\n"
        )
        self.sock.sendall(request.encode())
        response = self.sock.recv(4096)
        if b"101 Switching Protocols" not in response:
            raise AssertionError(response.decode(errors="replace"))

    def send_json(self, obj):
        payload = json.dumps(obj, separators=(",", ":")).encode()
        mask = os.urandom(4)
        header = bytearray([0x81])
        if len(payload) < 126:
            header.append(0x80 | len(payload))
        elif len(payload) < 65536:
            header.append(0x80 | 126)
            header.extend(struct.pack("!H", len(payload)))
        else:
            header.append(0x80 | 127)
            header.extend(struct.pack("!Q", len(payload)))
        masked = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        self.sock.sendall(bytes(header) + mask + masked)

    def recv_json(self, timeout=8):
        self.sock.settimeout(timeout)
        first = self.sock.recv(2)
        if len(first) < 2:
            raise AssertionError("short websocket header")
        opcode = first[0] & 0x0F
        length = first[1] & 0x7F
        if length == 126:
            length = struct.unpack("!H", self.sock.recv(2))[0]
        elif length == 127:
            length = struct.unpack("!Q", self.sock.recv(8))[0]
        if first[1] & 0x80:
            mask = self.sock.recv(4)
        else:
            mask = None
        payload = b""
        while len(payload) < length:
            payload += self.sock.recv(length - len(payload))
        if mask:
            payload = bytes(b ^ mask[i % 4] for i, b in enumerate(payload))
        if opcode == 8:
            raise AssertionError("websocket closed")
        return json.loads(payload.decode())

    def recv_until(self, predicate, timeout=8):
        deadline = time.time() + timeout
        last = None
        while time.time() < deadline:
            last = self.recv_json(timeout=max(0.1, deadline - time.time()))
            if predicate(last):
                return last
        raise AssertionError(f"timed out waiting for frame, last={last}")

    def close(self):
        self.sock.close()


def main():
    build()
    with tempfile.TemporaryDirectory(prefix="clawix-bridged-e2e-") as raw:
        tmp = Path(raw)
        backend = write_fake_backend(tmp)
        port = random.randint(39000, 49000)
        token = "test-token-" + os.urandom(16).hex()
        env = os.environ.copy()
        env.update(
            {
                "CLAWIX_BRIDGED_BACKEND_PATH": str(backend),
                "CLAWIX_BRIDGED_PORT": str(port),
                "CLAWIX_BRIDGED_BEARER": token,
                "CLAWIX_BRIDGED_DISABLE_BONJOUR": "1",
                "HOME": str(tmp),
            }
        )
        daemon = subprocess.Popen([str(BIN)], cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            deadline = time.time() + 8
            ws = None
            while time.time() < deadline:
                try:
                    ws = WebSocket(port)
                    break
                except OSError:
                    time.sleep(0.05)
            if ws is None:
                _, err = daemon.communicate(timeout=1)
                raise AssertionError(err)

            ws.send_json({"schemaVersion": 2, "type": "auth", "token": token, "deviceName": "E2E iPhone", "clientKind": "ios"})
            ws.recv_until(lambda f: f["type"] == "authOk")

            desktop = WebSocket(port)
            desktop.send_json({"schemaVersion": 2, "type": "auth", "token": token, "deviceName": "E2E Mac", "clientKind": "desktop"})
            desktop.recv_until(lambda f: f["type"] == "authOk")
            desktop.send_json({"schemaVersion": 2, "type": "pairingStart"})
            pairing = desktop.recv_until(lambda f: f["type"] == "pairingPayload")
            qr = json.loads(pairing["qrJson"])
            qr_ws = WebSocket(port)
            qr_ws.send_json({"schemaVersion": 2, "type": "auth", "token": qr["token"], "deviceName": "QR iPhone", "clientKind": "ios"})
            qr_ws.recv_until(lambda f: f["type"] == "authOk")
            qr_ws.close()
            desktop.close()

            snapshot = ws.recv_until(lambda f: f["type"] == "chatsSnapshot" and f["chats"])
            chat_id = snapshot["chats"][0]["id"]

            ws.send_json({"schemaVersion": 2, "type": "openChat", "chatId": chat_id})
            ws.recv_until(
                lambda f: f["type"] == "messagesSnapshot"
                and f["chatId"] == chat_id
                and any(m["content"] == "existing answer" for m in f["messages"])
            )

            ws.send_json({"schemaVersion": 2, "type": "sendPrompt", "chatId": chat_id, "text": "new prompt"})
            ws.recv_until(
                lambda f: (
                    f["type"] == "messageStreaming"
                    and f["content"] == "hello from daemon"
                    and f["finished"] is True
                )
                or (
                    f["type"] == "messageAppended"
                    and f["message"]["role"] == "assistant"
                    and f["message"]["content"] == "hello from daemon"
                )
            )

            new_chat_id = "11111111-2222-4333-8444-555555555555"
            ws.send_json({"schemaVersion": 2, "type": "openChat", "chatId": new_chat_id})
            ws.send_json({"schemaVersion": 2, "type": "sendPrompt", "chatId": new_chat_id, "text": "brand new prompt"})
            ws.recv_until(
                lambda f: (
                    f["type"] == "chatsSnapshot"
                    and any(c["id"] == new_chat_id and c["title"] == "brand new prompt" for c in f["chats"])
                )
            )
            ws.recv_until(
                lambda f: (
                    f["type"] == "messageStreaming"
                    and f["chatId"] == new_chat_id
                    and f["content"] == "hello from daemon"
                    and f["finished"] is True
                )
                or (
                    f["type"] == "messageAppended"
                    and f["chatId"] == new_chat_id
                    and f["message"]["role"] == "assistant"
                    and f["message"]["content"] == "hello from daemon"
                )
            )

            ws.send_json({"schemaVersion": 2, "type": "archiveChat", "chatId": new_chat_id})
            ws.recv_until(
                lambda f: (
                    f["type"] == "chatUpdated"
                    and f["chat"]["id"] == new_chat_id
                    and f["chat"]["isArchived"] is True
                )
            )
            ws.send_json({"schemaVersion": 2, "type": "unarchiveChat", "chatId": new_chat_id})
            ws.recv_until(
                lambda f: (
                    f["type"] == "chatUpdated"
                    and f["chat"]["id"] == new_chat_id
                    and f["chat"]["isArchived"] is False
                )
            )
            ws.close()

            timeout_port = port + 1
            timeout_env = env.copy()
            timeout_env.update(
                {
                    "CLAWIX_BRIDGED_PORT": str(timeout_port),
                    "CLAWIX_E2E_HANG_THREAD_LIST": "1",
                    "CLAWIX_BRIDGED_THREAD_LIST_TIMEOUT_SECONDS": "0.2",
                    "CLAWIX_BRIDGED_RATE_LIMITS_TIMEOUT_SECONDS": "0.2",
                }
            )
            timeout_daemon = subprocess.Popen([str(BIN)], cwd=ROOT, env=timeout_env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
            timeout_ws = None
            try:
                deadline = time.time() + 8
                while time.time() < deadline:
                    try:
                        timeout_ws = WebSocket(timeout_port)
                        break
                    except OSError:
                        time.sleep(0.05)
                if timeout_ws is None:
                    _, err = timeout_daemon.communicate(timeout=1)
                    raise AssertionError(err)
                timeout_ws.send_json({"schemaVersion": 2, "type": "auth", "token": token, "deviceName": "Timeout iPhone", "clientKind": "ios"})
                timeout_ws.recv_until(lambda f: f["type"] == "authOk")
                timeout_ws.recv_until(lambda f: f["type"] == "bridgeState" and f["state"] == "ready", timeout=5)
            finally:
                if timeout_ws is not None:
                    timeout_ws.close()
                timeout_daemon.terminate()
                try:
                    timeout_daemon.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    timeout_daemon.kill()
                    timeout_daemon.wait(timeout=5)
        finally:
            daemon.terminate()
            try:
                daemon.wait(timeout=5)
            except subprocess.TimeoutExpired:
                daemon.kill()
                daemon.wait(timeout=5)


if __name__ == "__main__":
    main()
