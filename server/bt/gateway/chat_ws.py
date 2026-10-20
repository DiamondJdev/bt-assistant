"""Streaming text chat over a WebSocket, with tools the client offers."""

from __future__ import annotations

import asyncio
import logging
import re
from contextlib import ExitStack, suppress
from typing import Annotated, Any, Literal

from fastapi import APIRouter, Query, WebSocket
from pydantic import AfterValidator, BaseModel, Field, TypeAdapter, ValidationError

from bt.config import CONFIG
from bt.llm.router import respond
from bt.tools.registry import default_context, openai_tools
from bt.transcript.store import get_store

log = logging.getLogger("bt.gateway")
router = APIRouter()
store = get_store()

CLIENT_TOOL_TIMEOUT_SECS = 30.0
MAX_CONTEXT_CHARS = 4000
TOOL_NAME = re.compile(r"^[a-zA-Z0-9_-]+$")

BUSY = "Conversation is busy. Disconnect voice or wait for the current reply."
FAILED = "Response failed. Try again."
UNRECOGNIZED = "Unrecognized message."


def _not_blank(value: str) -> str:
	if not value.strip():
		raise ValueError("Enter a message")
	return value


# Shared with POST /chat so both paths accept the same text.
ChatText = Annotated[str, Field(min_length=1, max_length=16000), AfterValidator(_not_blank)]


class ClientTool(BaseModel):
	name: str = Field(max_length=64)
	description: str = Field(default="", max_length=2000)
	parameters: dict[str, Any] = Field(default_factory=lambda: {"type": "object", "properties": {}})


class Hello(BaseModel):
	type: Literal["hello"]
	tools: list[ClientTool] = Field(default_factory=list, max_length=64)


class Message(BaseModel):
	type: Literal["message"]
	text: ChatText
	context: str | None = Field(default=None, max_length=MAX_CONTEXT_CHARS)


class ToolResult(BaseModel):
	type: Literal["tool_result"]
	id: str
	ok: bool
	content: str = ""


Frame = TypeAdapter(Annotated[Hello | Message | ToolResult, Field(discriminator="type")])


def _frame_error(exc: ValidationError) -> str:
	err = exc.errors()[0]
	where = err["loc"][:2]
	too_long = err["type"] == "string_too_long"
	if where == ("message", "text"):
		return "Message is too long." if too_long else "Enter a message"
	if where == ("message", "context") and too_long:
		return "Context is too long."
	if where[:1] == ("hello",):
		return "Tools were rejected: the tool list is malformed."
	return UNRECOGNIZED


# Returns the reason the list is unusable, or None.
def _tools_problem(tools: list[ClientTool]) -> str | None:
	server = {t["function"]["name"] for t in openai_tools()}
	seen: set[str] = set()
	for t in tools:
		if not TOOL_NAME.match(t.name):
			return f"{t.name!r} is not a valid tool name."
		if t.name in server:
			return f"{t.name} is already a server tool."
		if t.name in seen:
			return f"{t.name} is listed twice."
		seen.add(t.name)
	return None


class _Connection:
	def __init__(self, ws: WebSocket, session_id: str):
		self.ws = ws
		self.session_id = session_id
		self.client_tools: list[dict[str, Any]] | None = None
		self.started = False
		self.turn: asyncio.Task | None = None

	async def send(self, frame: dict[str, Any]) -> None:
		await self.ws.send_json(frame)

	async def error(self, message: str) -> None:
		await self.send({"type": "error", "message": message})

	async def on_frame(self, raw: str | None) -> None:
		try:
			if raw is None:
				raise ValueError("binary frame")
			frame = Frame.validate_json(raw)
		except ValidationError as exc:
			await self.error(_frame_error(exc))
			return
		except ValueError:
			await self.error(UNRECOGNIZED)
			return

		if isinstance(frame, Hello):
			await self.on_hello(frame)
		elif isinstance(frame, Message):
			if self.turn and not self.turn.done():
				await self.error("Wait for the current reply.")
				return
			self.started = True
			self.turn = asyncio.create_task(self.run_turn(frame))

	async def on_hello(self, hello: Hello) -> None:
		if not CONFIG.tools_enabled:
			return
		problem = "send hello before the first message." if self.started else _tools_problem(hello.tools)
		if problem:
			await self.error(f"Tools were rejected: {problem}")
			if not self.started:
				self.client_tools = None
			return
		self.client_tools = [{"type": "function", "function": t.model_dump()} for t in hello.tools] or None

	async def run_turn(self, message: Message) -> None:
		with ExitStack() as lease:
			try:
				lease.enter_context(store.conversation(self.session_id))
			except KeyError:
				await self.error("Conversation not found")
				return
			except RuntimeError:
				await self.error(BUSY)
				return
			try:
				await self.answer(message)
			except Exception:
				log.exception("chat socket turn failed for %s", self.session_id)
				with suppress(Exception):
					await self.error(FAILED)

	async def answer(self, message: Message) -> None:
		sid = self.session_id
		await asyncio.to_thread(store.add_turn, sid, "user", message.text, input_mode="text", context=message.context)
		history = await asyncio.to_thread(store.as_chat_messages, sid)
		ctx = default_context(sid, "text") if CONFIG.tools_enabled else None

		async def delta(text: str) -> None:
			await self.send({"type": "delta", "text": text})

		result = await respond(
			history,
			message.text,
			ctx=ctx,
			session_id=sid,
			context=message.context,
			on_delta=delta,
			client_tools=self.client_tools,
		)
		if not result:
			raise ValueError("LLM did not return a response")
		await asyncio.to_thread(store.add_turn, sid, "bt", result.text, compute=result.compute)
		await self.send({
			"type": "done",
			"text": result.text,
			"compute": result.compute,
			"tools_used": list(result.tools_used),
		})


@router.websocket("/chat/ws")
async def chat_socket(websocket: WebSocket, session_id: str | None = Query(default=None, max_length=128)) -> None:
	# OriginMiddleware has already rejected cross-site connections.
	await websocket.accept()
	try:
		if session_id:
			await asyncio.to_thread(store.history, session_id, 1)
		else:
			session_id = await asyncio.to_thread(store.new_session)
	except KeyError:
		await websocket.send_json({"type": "error", "message": "Conversation not found"})
		await websocket.close(code=1008, reason="Conversation not found")
		return

	conn = _Connection(websocket, session_id)
	await conn.send({"type": "session", "session_id": session_id})
	try:
		while True:
			event = await websocket.receive()
			if event["type"] == "websocket.disconnect":
				break
			await conn.on_frame(event.get("text"))
	finally:
		# A dropped client cancels its turn; no reply is stored.
		if conn.turn and not conn.turn.done():
			conn.turn.cancel()
			with suppress(asyncio.CancelledError):
				await conn.turn
