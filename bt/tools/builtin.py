"""
The tools BT ships with.

This do not run shell command or arbitrary code due to the frequent
typos from voice input.
"""

from __future__ import annotations

import logging
import shutil
from datetime import datetime
from pathlib import Path

import httpx

from bt.config import CONFIG
from bt.library import MEMORY_TYPES
from bt.tools.registry import ToolContext, tool

log = logging.getLogger("bt.tools")

VOICE_SKILL_CHARS = 2000

# ------------------------------ enviroment processing ----------------------------------

# Only what changes within a session lives here. The host, the OS, the model and
# the operator are constant for the session and are injected into the system
# prompt instead, so BT does not spend a round trip learning what it was told.
@tool(
	name="environment_report",
	description=(
		"Report the current date and time and the live state of the machine BT runs "
		"on: uptime, free memory, free disk, and whether the local model is reachable."
	),
	manifest="You can report the current time and the live state of the machine with environment_report.",
	timeout_secs=5.0,
)
async def environment_report(ctx: ToolContext) -> str:
	now = datetime.now().astimezone()
	parts = [f"It is {now.strftime('%H:%M on %A, %d %B %Y')}, timezone {now.tzname()}."]

	uptime = _uptime()
	if uptime:
		parts.append(f"The system has been up {uptime}.")

	memory_gb = _available_memory_gb()
	if memory_gb is not None:
		parts.append(f"{memory_gb:.0f} gigabytes of memory are available.")

	try:
		parts.append(f"{shutil.disk_usage(Path.cwd()).free / 1024 ** 3:.0f} gigabytes of disk are free.")
	except OSError:
		log.warning("could not read disk usage")

	reachable = await _ollama_reachable()
	parts.append(
		f"The local model {CONFIG.ollama_model} is reachable."
		if reachable
		else f"The local model {CONFIG.ollama_model} is not reachable."
	)
	return " ".join(parts)


# /proc reads are file reads, not subprocesses, and they are absent off Linux.
def _uptime() -> str | None:
	try:
		seconds = int(float(Path("/proc/uptime").read_text().split()[0]))
	except (OSError, ValueError, IndexError):
		return None
	days, remainder = divmod(seconds, 86_400)
	hours, remainder = divmod(remainder, 3_600)
	if days:
		return f"{_plural(days, 'day')} and {_plural(hours, 'hour')}"
	return f"{_plural(hours, 'hour')} and {_plural(remainder // 60, 'minute')}"


def _plural(count: int, noun: str) -> str:
	return f"{count} {noun}" if count == 1 else f"{count} {noun}s"


def _available_memory_gb() -> float | None:
	try:
		for line in Path("/proc/meminfo").read_text().splitlines():
			if line.startswith("MemAvailable:"):
				return int(line.split()[1]) / (1024 * 1024)
	except (OSError, ValueError, IndexError):
		return None
	return None


async def _ollama_reachable() -> bool:
	try:
		async with httpx.AsyncClient(timeout=2) as client:
			return (await client.get(CONFIG.ollama_url("/"))).status_code < 500
	except httpx.HTTPError:
		return False


# ---------------------------- memory skills ---------------------------------


@tool(
	name="memory_search",
	description=(
		"Search stored memories about the Pilot and the system. Returns names and "
		"one-line descriptions; use memory_read for the full text of one."
	),
	properties={"query": {"type": "string", "description": "Words to look for."}},
	required=("query",),
	manifest="You can search your stored memories with memory_search and read one in full with memory_read.",
	timeout_secs=5.0,
)
async def memory_search(ctx: ToolContext, query: str) -> str:
	found = ctx.memory.search(query)
	if not found:
		return f"No stored memory matches {query}."
	return "Matching memories. " + " ".join(f"{m.name}: {m.description}" for m in found)


@tool(
	name="memory_read",
	description="Read one stored memory in full, by the name memory_search reported.",
	properties={"name": {"type": "string", "description": "The memory's name."}},
	required=("name",),
	timeout_secs=5.0,
)
async def memory_read(ctx: ToolContext, name: str) -> str:
	memory = ctx.memory.read(name)
	if memory is None:
		return f"There is no memory named {name}."
	return f"{memory.description} {memory.body}".strip()


@tool(
	name="memory_write",
	description=(
		"Record a durable fact about the Pilot or the system so it survives this "
		"conversation. Writing to an existing name replaces it, so use the same "
		"name to correct a fact rather than inventing a new one."
	),
	properties={
		"name": {
			"type": "string",
			"description": "Short identifier in kebab case, for example operator-callsign.",
		},
		"description": {
			"type": "string",
			"description": "One sentence stating the fact. This is what search returns.",
		},
		"body": {
			"type": "string",
			"description": "The fact in full, with any context worth keeping.",
		},
		"type": {
			"type": "string",
			"enum": list(MEMORY_TYPES),
			"description": (
				"user for who the Pilot is, feedback for how they want you to work, "
				"project for ongoing work, reference for pointers to external resources."
			),
		},
	},
	required=("name", "description", "body"),
	manifest=(
		"You can record a durable fact with memory_write. Do this when the Pilot "
		"states something that should outlive this conversation."
	),
	timeout_secs=5.0,
)
async def memory_write(
	ctx: ToolContext, name: str, description: str, body: str, type: str = "user"
) -> str:
	memory = ctx.memory.write(name, description, body, type)
	return f"Saved as {memory.name}."


# ---------------------------- skills skills (see what I did there) -------------------------------

@tool(
	name="load_skill",
	description=(
		"Open a skill and read its instructions in full. Call this before working "
		"through a task one of the listed skills covers."
	),
	properties={"name": {"type": "string", "description": "The skill name as listed."}},
	required=("name",),
	timeout_secs=3.0,
)
async def load_skill(ctx: ToolContext, name: str) -> str:
	body = ctx.skills.body(name)
	if body is None:
		available = ", ".join(s.name for s in ctx.skills.manifest(ctx.surface))
		return f"There is no skill named {name}. Available skills: {available or 'none'}."

	if name in ctx.loaded_skills:
		return f"{name} is already loaded. Its instructions are above."
	ctx.loaded_skills.add(name)

	if ctx.surface == "voice":
		body = _truncate(body, VOICE_SKILL_CHARS)
	return body


def _truncate(text: str, limit: int) -> str:
	if len(text) <= limit:
		return text
	cut = text.rfind("\n\n", 0, limit)
	kept = text[:cut] if cut > 0 else text[:limit]
	return kept.rstrip() + "\n\nThe rest of this skill is not included in a spoken session."
