import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer

APP_VERSION = os.environ.get("APP_VERSION", "v1")


def get_orders():
    return [
        {"id": 101, "item": "cloud-kit", "amount": 199.0, "version": APP_VERSION},
        {"id": 102, "item": "k8s-pro", "amount": 349.0, "version": APP_VERSION},
    ]


class Handler(BaseHTTPRequestHandler):
    def _json(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            self._json(200, {"status": "ok", "version": APP_VERSION})
            return
        if self.path.startswith("/orders"):
            self._json(200, {"service": "orders-api", "version": APP_VERSION, "orders": get_orders()})
            return
        self._json(404, {"error": "not found"})

    def do_POST(self):
        self._json(201, {"service": "orders-api", "version": APP_VERSION, "created": True})

    def log_message(self, format, *args):
        pass


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    HTTPServer(("0.0.0.0", port), Handler).serve_forever()
