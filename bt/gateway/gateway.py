"""
Exposes assistant over Web

Must be assessible over tailscale for multiple devices to access the assistant
"""

from __future__ import annotations

from fastapi import FastAPI
from pydantic import BaseModel

from bt.config import CONFIG
from bt.llm.router import respond
from bt.transcript.store import TranscriptStore

app = FastAPI()
store = TranscriptStore(CONFIG.db_path)


class ChatRequest(BaseModel):
	text: str
	session_id: str | None = None


class ChatResponse(BaseModel):
	session_id: str
	text: str
	compute: str


@app.get("/health")
def health() -> dict[str, str]:
	return {"status": "ok"}


@app.post("/chat", response_model=ChatResponse)
async def chat(req: ChatRequest) -> ChatResponse:
	try:
		session_id = req.session_id or store.new_session()
		store.add_turn(session_id, "user", req.text, input_mode="text")
		result = await respond(store.as_chat_messages(session_id), req.text)
		if not result:
				raise RuntimeError("LLM did not return a response")
		store.add_turn(session_id, "bt", result.text, compute=result.compute)
		return ChatResponse(session_id=session_id, text=result.text, compute=result.compute)
	except Exception as e:
			return ChatResponse(session_id=req.session_id or "", text=f"Error: {e}", compute="error")