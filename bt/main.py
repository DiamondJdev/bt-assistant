# Entry point. Serve FastAPI, Voice activation (wake word, push-to-talk)

from __future__ import annotations
from pathlib import Path

from dotenv import load_dotenv
load_dotenv(Path(__file__).resolve().parent.parent / ".env", override=False)

import logging

import uvicorn
from bt.gateway.gateway import app

def run(port: int = 8080) -> None:
	logging.basicConfig(
		level=logging.INFO,
		format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
		datefmt="%H:%M:%S",
	)
	uvicorn.run(app, host="127.0.0.1", port=port, timeout_graceful_shutdown=2)

if __name__ == "__main__":
	run()
