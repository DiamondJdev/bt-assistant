# Entry point. Serve FastAPI, Voice activation (wake word, push-to-talk)

from __future__ import annotations
import uvicorn
from bt.config import CONFIG
from bt.gateway.gateway import app

def run() -> None:
	uvicorn.run(app, host="127.0.0.1", port=8080)

if __name__ == "__main__":
	run()
