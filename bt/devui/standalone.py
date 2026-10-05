'''
Standalone dev dashboard (`bt-devui`).

Localhost is a secure context, so the mic works without HTTPS.
'''

from __future__ import annotations

import uvicorn
from fastapi import FastAPI

from bt.devui.routes import router

app = FastAPI()
app.include_router(router)


def run(port: int = 8082) -> None:
	uvicorn.run(app, host="127.0.0.1", port=port)
