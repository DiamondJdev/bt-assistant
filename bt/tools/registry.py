"""
One declaration site for every tool BT can call.

A tool is declared once with @tool and this renders it into whatever
shape the caller needs: Pipecat FunctionSchema objects for the voice pipeline,
OpenAI JSON for text
"""

from __future__ import annotations

import asyncio
import json
import logging
import time
from collections.abc import Awaitable, Callable, Mapping
from dataclasses import dataclass, field
from typing import Any

from pipecat.adapters.schemas.function_schema import FunctionSchema
from pipecat.services.llm_service import FunctionCallParams

from bt.library import MemoryStore, SkillLibrary, get_memory, get_skills

log = logging.getLogger("bt.tools")

DEFAULT_TIMEOUT_SECS = 10.0
LOG_PREVIEW_CHARS = 120

ToolHandler = Callable[..., Awaitable[str]]

@dataclass
class ToolContext:
	session_id: str
	memory: MemoryStore
	skills: SkillLibrary
	surface: str  # 'text' | 'voice'
	loaded_skills: set[str] = field(default_factory=set)
	used: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class ToolSpec:
	name: str
	description: str
	properties: dict[str, Any]  # JSON Schema properties block
	required: tuple[str, ...]
	handler: ToolHandler
	manifest: str | None
	timeout_secs: float


_REGISTRY: dict[str, ToolSpec] = {}


# Declares a tool and files it in the registry. Handlers take a ToolContext
# first, then keyword arguments matching `properties`, and return prose.
def tool(
	*,
	name: str,
	description: str,
	properties: dict[str, Any] | None = None,
	required: tuple[str, ...] = (),
	manifest: str | None = None,
	timeout_secs: float = DEFAULT_TIMEOUT_SECS,
) -> Callable[[ToolHandler], ToolHandler]:
	def decorator(handler: ToolHandler) -> ToolHandler:
		if name in _REGISTRY:
			raise ValueError(f"tool {name!r} is already registered")
		_REGISTRY[name] = ToolSpec(
			name=name,
			description=description,
			properties=properties or {},
			required=tuple(required),
			handler=handler,
			manifest=manifest,
			timeout_secs=timeout_secs,
		)
		return handler

	return decorator

def specs() -> list[ToolSpec]:
	return [_REGISTRY[name] for name in sorted(_REGISTRY)]

def load_builtins() -> None:
	from bt.tools import builtin  # noqa: F401

def default_context(session_id: str, surface: str) -> ToolContext:
	load_builtins()
	return ToolContext(
		session_id=session_id, memory=get_memory(), skills=get_skills(), surface=surface
	)

async def run_tool(spec: ToolSpec, ctx: ToolContext, arguments: Mapping[str, Any]) -> str:
	missing = [key for key in spec.required if arguments.get(key) in (None, "")]
	if missing:
		log.warning("tool %s called without %s", spec.name, ", ".join(missing))
		return f"{spec.name} requires {_and_join(missing)}."

	known = {key: value for key, value in arguments.items() if key in spec.properties}
	if len(known) != len(arguments):
		dropped = sorted(set(arguments) - set(known))
		log.warning("tool %s ignoring unknown arguments: %s", spec.name, ", ".join(dropped))

	started = time.monotonic()
	try:
		result = await asyncio.wait_for(spec.handler(ctx, **known), timeout=spec.timeout_secs)
	except asyncio.TimeoutError:
		log.warning("tool %s timed out after %.1fs", spec.name, spec.timeout_secs)
		return f"{spec.name} did not finish within {spec.timeout_secs:.0f} seconds."
	except ValueError as exc:
		log.warning("tool %s rejected its arguments: %s", spec.name, exc)
		return f"{spec.name} could not run: {exc}"
	except Exception as exc:
		log.exception("tool %s failed", spec.name)
		return f"{spec.name} failed: {exc}"

	if not isinstance(result, str):
		log.error("tool %s returned %s, expected str", spec.name, type(result).__name__)
		return f"{spec.name} returned an unusable result."

	ctx.used.append(spec.name)
	log.info(
		"tool %s(%s) -> %s [%.0fms]",
		spec.name,
		", ".join(f"{k}={v!r}" for k, v in known.items()),
		_preview(result),
		(time.monotonic() - started) * 1000,
	)
	return result

async def dispatch_call(name: str, raw_arguments: str | None, ctx: ToolContext) -> str:
	spec = _REGISTRY.get(name)
	if spec is None:
		log.warning("model called unknown tool %r", name)
		return f"No tool named {name} is available."

	try:
		arguments = json.loads(raw_arguments or "{}")
	except json.JSONDecodeError:
		log.warning("tool %s got invalid JSON arguments: %r", name, raw_arguments)
		return f"Arguments for {name} were not valid JSON. Call it again with valid arguments."

	if not isinstance(arguments, dict):
		return f"Arguments for {name} must be an object."
	return await run_tool(spec, ctx, arguments)


def _preview(text: str) -> str:
	flat = " ".join(text.split())
	return flat if len(flat) <= LOG_PREVIEW_CHARS else flat[:LOG_PREVIEW_CHARS] + "..."


def _and_join(items: list[str]) -> str:
	return items[0] if len(items) == 1 else ", ".join(items[:-1]) + f" and {items[-1]}"

def pipecat_tools() -> list[FunctionSchema]:
	load_builtins()
	return [_function_schema(spec) for spec in specs()]

def openai_tools() -> list[dict[str, Any]]:
	return [{"type": "function", "function": s.to_default_dict()} for s in pipecat_tools()]


def _function_schema(spec: ToolSpec) -> FunctionSchema:
	async def bridge(params: FunctionCallParams) -> None:
		ctx = params.app_resources
		if not isinstance(ctx, ToolContext):
			log.error("tool %s ran without a ToolContext in app_resources", spec.name)
			await params.result_callback(f"{spec.name} is not available right now.")
			return
		await params.result_callback(await run_tool(spec, ctx, dict(params.arguments)))

	bridge.__name__ = f"bt_tool_{spec.name}"
	return FunctionSchema(
		name=spec.name,
		description=spec.description,
		properties=spec.properties,
		required=list(spec.required),
		handler=bridge,
	)


# One sentence per tool for SOUL.md's capability section.
# the model imitates prompt formatting and its output
def manifest_lines(surface: str, skills: SkillLibrary | None = None) -> list[str]:
	load_builtins()
	lines = [spec.manifest for spec in specs() if spec.manifest]

	available = (skills or get_skills()).manifest(surface)
	if available:
		listed = " ".join(f"{s.name}: {s.description}" for s in available)
		lines.append(f"You can open a skill with load_skill. Available skills. {listed}")
	return lines
