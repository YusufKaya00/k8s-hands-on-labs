import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer


def get_items():
    return [
        {"id": 1, "name": "k8s-handbook", "price": 29.90},
        {"id": 2, "name": "devsecops-guide", "price": 39.90},
    ]


class AppHandler(BaseHTTPRequestHandler):
    def _send_json(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            self._send_json(200, {"status": "ok"})
            return
        if self.path == "/items":
            self._send_json(200, {"items": get_items()})
            return
        self._send_json(404, {"error": "not found"})

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    HTTPServer(("0.0.0.0", port), AppHandler).serve_forever()
