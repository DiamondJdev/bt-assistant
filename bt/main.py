# Entry point. Serve FastAPI, Voice activation (wake word, push-to-talk)

from __future__ import annotations
import logging
import uvicorn
from bt.config import CONFIG

def run() -> None:
    print('yo this ran')

if __name__ == "__main__":
    run()
