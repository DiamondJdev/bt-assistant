# Entry point. Serve FastAPI, Voice activation (wake word, push-to-talk)

from __future__ import annotations
from pathlib import Path

from dotenv import load_dotenv
load_dotenv(Path(__file__).resolve().parent.parent / ".env", override=False)

import uvicorn
from bt.gateway.gateway import app

def run() -> None:
	uvicorn.run(app, host="127.0.0.1", port=8080)

if __name__ == "__main__":
	run()
