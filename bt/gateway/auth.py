"""Shared-token access for the owner's devices."""

import secrets

from starlette.requests import HTTPConnection
from starlette.responses import JSONResponse
from starlette.websockets import WebSocket

from bt.config import CONFIG

COOKIE = 'bt_access'


def same_origin(connection: HTTPConnection) -> bool:
    origin = connection.headers.get('origin')
    scheme = 'https' if connection.url.scheme in {'https', 'wss'} else 'http'
    return origin is None or origin == f'{scheme}://{connection.url.netloc}'


def authorized(connection: HTTPConnection) -> bool:
    if not same_origin(connection):
        return False
    if not CONFIG.api_token:
        return connection.client is not None and connection.client.host in {'127.0.0.1', '::1'}
    authorization = connection.headers.get('authorization', '')
    token = authorization[7:] if authorization.startswith('Bearer ') else connection.cookies.get(COOKIE, '')
    return secrets.compare_digest(token.encode(), CONFIG.api_token.encode())


class AccessMiddleware:
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope['type'] not in {'http', 'websocket'}:
            return await self.app(scope, receive, send)
        connection = HTTPConnection(scope)
        async def no_cache(message):
            if message['type'] == 'http.response.start':
                message['headers'].append((b'cache-control', b'no-store'))
            await send(message)

        path = scope['path']
        public = path in {'/', '/health', '/auth/login'} or path.startswith('/static/')
        if not same_origin(connection):
            status = 403
        elif public or authorized(connection):
            return await self.app(scope, receive, no_cache)
        else:
            status = 401
        if scope['type'] == 'websocket':
            # Browsers lose the close code when the HTTP upgrade is rejected.
            websocket = WebSocket(scope, receive, send)
            await websocket.accept()
            await websocket.close(code=1008, reason='Access denied. Unlock BT again.')
        else:
            await JSONResponse({'detail': 'Access denied'}, status_code=status)(scope, receive, no_cache)
