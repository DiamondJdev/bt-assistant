"""Same-origin guard. Access is open to the tailnet, but not to websites the owner visits."""

from urllib.parse import urlsplit

from starlette.requests import HTTPConnection
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send
from starlette.websockets import WebSocket


def same_origin(connection: HTTPConnection) -> bool:
	origin = connection.headers.get("origin")
	if origin is None:
		return True  # native clients and curl send no Origin
	# A TLS-terminating proxy may forward http and rewrite Host. Browsers cannot
	# forge X-Forwarded-Host on cross-site requests without a CORS preflight.
	hosts = {connection.headers.get("host"), connection.headers.get("x-forwarded-host")}
	return urlsplit(origin).netloc in hosts - {None}


class OriginMiddleware:
	def __init__(self, app: ASGIApp) -> None:
		self.app = app

	async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
		if scope["type"] not in {"http", "websocket"}:
			return await self.app(scope, receive, send)

		async def no_cache(message: Message) -> None:
			if message["type"] == "http.response.start":
				message["headers"].append((b"cache-control", b"no-store"))
			await send(message)

		if same_origin(HTTPConnection(scope)):
			return await self.app(scope, receive, no_cache)
		if scope["type"] == "websocket":
			# Browsers lose the close code when the HTTP upgrade is rejected.
			websocket = WebSocket(scope, receive, send)
			await websocket.accept()
			await websocket.close(code=1008, reason="Cross-origin access denied.")
		else:
			await JSONResponse({"detail": "Cross-origin access denied"}, status_code=403)(scope, receive, no_cache)
