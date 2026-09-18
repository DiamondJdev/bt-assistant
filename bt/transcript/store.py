"""
Thin client to handle SQLite transcript storage.
Every turn's text, input mode, and processing info gets digested here
"""

from __future__ import annotations

import sqlite3
import threading
import time
import uuid
from dataclasses import dataclass
from pathlib import Path
from typing import cast

from pipecat.processors.aggregators.llm_context import LLMContextMessage

from bt.config import CONFIG

# DB Schema storing sessions and turns. We create an index on session_id+ts for efficient retrieval of recent turns
SCHEMA = """
CREATE TABLE IF NOT EXISTS sessions (
	id TEXT PRIMARY KEY,
	started_at REAL NOT NULL,
	label TEXT
);

CREATE TABLE IF NOT EXISTS turns (
	id TEXT PRIMARY KEY,
	session_id TEXT NOT NULL REFERENCES sessions(id),
	ts REAL NOT NULL,
	role TEXT NOT NULL,          -- 'user' | 'bt'
	text TEXT NOT NULL,
	input_mode TEXT,             -- 'voice_wake' | 'voice_ptt' | 'text' (user turns)
	compute TEXT                 -- 'ollama' | 'openai' (bt turns)
);

CREATE INDEX IF NOT EXISTS idx_turns_session ON turns(session_id, ts);
"""

# Data Class for a single turn in a session.
#
# A 'turn' is a single user or assistant message,
# with its situation metadata (session, role, timestamp, etc.)
@dataclass
class Turn:
	id: str
	session_id: str
	ts: float
	role: str
	text: str
	input_mode: str | None = None
	compute: str | None = None


class TranscriptStore:
	def __init__(self, db_path: str):
		Path(db_path).parent.mkdir(parents=True, exist_ok=True)
		self._conn = sqlite3.connect(db_path, check_same_thread=False)
		# The connection is shared across threads (HTTP handlers and the voice
		# pipeline), so every statement below runs under _lock. WAL lets readers
		# proceed while a write is in flight.
		self._lock = threading.Lock()
		self._conn.execute("PRAGMA journal_mode=WAL")
		self._conn.executescript(SCHEMA)
		self._conn.commit()

	def new_session(self, label: str | None = None) -> str:
		session_id = str(uuid.uuid4())
		with self._lock:
			self._conn.execute(
				"INSERT INTO sessions (id, started_at, label) VALUES (?, ?, ?)",
				(session_id, time.time(), label),
			)
			self._conn.commit()
		return session_id

	def add_turn(
		self,
		session_id: str,
		role: str,
		text: str,
		input_mode: str | None = None,
		compute: str | None = None,
	) -> Turn:
		turn = Turn(
			id=str(uuid.uuid4()),
			session_id=session_id,
			ts=time.time(),
			role=role,
			text=text,
			input_mode=input_mode,
			compute=compute,
		)
		with self._lock:
			self._conn.execute(
				"""INSERT INTO turns (id, session_id, ts, role, text, input_mode, compute)
						VALUES (?, ?, ?, ?, ?, ?, ?)""",
				(turn.id, turn.session_id, turn.ts, turn.role, turn.text, turn.input_mode, turn.compute),
			)
			self._conn.commit()
		return turn

	# Returns the most recent 'limit' turns for a given session with session id equal to 'session_id'
	def history(self, session_id: str, limit: int = 200) -> list[Turn]:
		with self._lock:
			rows = self._conn.execute(
				"""SELECT id, session_id, ts, role, text, input_mode, compute
						FROM turns WHERE session_id = ? ORDER BY ts ASC LIMIT ?""", (session_id, limit),
			).fetchall()
		return [Turn(*row) for row in rows]

	# Same as history(), but formatted for an LLM chat call (role/content only)
	def as_chat_messages(self, session_id: str, limit: int = 50) -> list[LLMContextMessage]:
		"""Recent turns formatted for an LLM chat call (role/content only)."""
		turns = self.history(session_id, limit=limit)
		return cast(
			"list[LLMContextMessage]",
			[
				{"role": "user" if t.role == "user" else "assistant", "content": t.text}
				for t in turns
			],
		)


_STORE: TranscriptStore | None = None


# Shared by the HTTP gateway and the voice pipeline so both modalities read and
# write one transcript. Session ids are therefore interchangeable between them.
def get_store() -> TranscriptStore:
	global _STORE
	if _STORE is None:
		_STORE = TranscriptStore(CONFIG.db_path)
	return _STORE
