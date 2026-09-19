"""
Markdown libraries for BT.

This currently hosts Memory and skills,
both are stored in markdown files
"""

from __future__ import annotations

import difflib
import logging
import re
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path

from bt.config import CONFIG

log = logging.getLogger("bt.library")

FENCE = "---"
INDEX_NAME = "MEMORY.md"
INDEX_LIMIT = 60
MEMORY_TYPES = ("user", "feedback", "project", "reference")
SURFACES = ("text", "voice")

# Skills are packaged with the code rather than written at runtime.
SKILLS_ROOT = Path(__file__).parent / "skills" / "library"


def _utcnow() -> str:
	return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


# ------------------------ frontmatter processing ----------------------------------
def parse_frontmatter(text: str) -> tuple[dict[str, str], str]:
	lines = text.splitlines()
	if not lines or lines[0].strip() != FENCE:
		return {}, text

	meta: dict[str, str] = {}
	for index, line in enumerate(lines[1:], start=1):
		if line.strip() == FENCE:
			return meta, "\n".join(lines[index + 1:]).strip()
		key, separator, value = line.partition(":")
		if separator:
			meta[key.strip()] = _unquote(value.strip())
	return {}, text


def render_frontmatter(meta: dict[str, str], body: str) -> str:
	lines = [FENCE]
	lines += [f"{key}: {_quote(value)}" for key, value in meta.items()]
	lines.append(FENCE)
	return "\n".join(lines) + "\n\n" + body.strip() + "\n"


def _unquote(value: str) -> str:
	if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
		return value[1:-1]
	return value

def _quote(value: str) -> str:
	flat = " ".join(value.split())
	return f'"{flat}"' if ":" in flat else flat

_SLUG_SEPARATORS = re.compile(r"[^a-z0-9]+")

# Ensure name is usable as a filename
def slugify(name: str) -> str:
	slug = _SLUG_SEPARATORS.sub("-", name.strip().lower()).strip("-")[:60].strip("-")
	if not slug:
		raise ValueError(f"name does not produce a usable filename: {name!r}")
	return slug


# ----------------------------- memory processing ---------------------------------

@dataclass(frozen=True)
class Memory:
	name: str
	description: str
	type: str
	updated: str
	body: str

_WORDS = re.compile(r"[a-z0-9']+")

# Name matches beat description matches beat body matches.
_WEIGHTS = ((3, "name"), (2, "description"), (1, "body"))

def _score(memory: Memory, words: list[str]) -> int:
	return sum(
		weight * getattr(memory, field).lower().count(word)
		for weight, field in _WEIGHTS
		for word in words
	)

def _fuzzy_score(memory: Memory, words: list[str]) -> int:
	score = 0
	for weight, field in _WEIGHTS:
		haystack = set(_WORDS.findall(getattr(memory, field).lower()))
		for word in words:
			if difflib.get_close_matches(word, haystack, n=1, cutoff=0.6):
				score += weight
	return score

class MemoryStore:
	def __init__(self, root: str | Path) -> None:
		self._root = Path(root).resolve()
		self._root.mkdir(parents=True, exist_ok=True)

	def _path(self, name: str) -> Path:
		path = (self._root / f"{slugify(name)}.md").resolve()
		if path.parent != self._root:
			raise ValueError(f"invalid memory name: {name!r}")
		return path

	def _files(self) -> list[Path]:
		return sorted(p for p in self._root.glob("*.md") if p.name != INDEX_NAME)

	def _load(self, path: Path) -> Memory | None:
		try:
			meta, body = parse_frontmatter(path.read_text(encoding="utf-8"))
		except OSError:
			log.warning("could not read memory %s", path.name)
			return None
		if not meta.get("description"):
			log.warning("memory %s has no description, skipping", path.name)
			return None
		return Memory(
			name=meta.get("name") or path.stem,
			description=meta["description"],
			type=meta.get("type", "user"),
			updated=meta.get("updated", ""),
			body=body,
		)

	def _all(self) -> list[Memory]:
		return [m for m in (self._load(p) for p in self._files()) if m is not None]

	def read(self, name: str) -> Memory | None:
		path = self._path(name)
		return self._load(path) if path.is_file() else None

	def write(self, name: str, description: str, body: str, type: str = "user") -> Memory:
		if type not in MEMORY_TYPES:
			raise ValueError(f"unknown memory type: {type!r}")
		if not description.strip():
			raise ValueError("a memory needs a description")

		path = self._path(name)
		memory = Memory(
			name=path.stem,
			description=" ".join(description.split()),
			type=type,
			updated=_utcnow(),
			body=body.strip(),
		)
		path.write_text(
			render_frontmatter(
				{
					"name": memory.name,
					"description": memory.description,
					"type": memory.type,
					"updated": memory.updated,
				},
				memory.body,
			),
			encoding="utf-8",
		)
		self.write_index()
		return memory

	def search(self, query: str, limit: int = 5) -> list[Memory]:
		words = [w for w in _WORDS.findall(query.lower()) if len(w) > 2]
		if not words:
			return []

		candidates = self._all()
		scored = [(s, m) for m in candidates if (s := _score(m, words))]

		if not scored:
			scored = [(s, m) for m in candidates if (s := _fuzzy_score(m, words))]

		scored.sort(key=lambda row: (row[0], row[1].updated), reverse=True)
		return [memory for _, memory in scored[:limit]]

	def index(self) -> list[Memory]:
		order = {name: position for position, name in enumerate(MEMORY_TYPES)}
		return sorted(self._all(), key=lambda m: (order.get(m.type, len(order)), m.name))

	def index_lines(self, limit: int = INDEX_LIMIT) -> list[str]:
		entries = self.index()
		lines = [f"{m.name}: {m.description}" for m in entries[:limit]]
		if len(entries) > limit:
			lines.append("More memories exist. Use memory_search to find them.")
		return lines

	def write_index(self) -> None:
		lines = [
			"# BT memory index",
			"",
			"Generated from the files in this directory. Edits here are overwritten.",
			"",
		]
		lines += [f"- [{m.name}]({m.name}.md) — {m.description}" for m in self.index()]
		(self._root / INDEX_NAME).write_text("\n".join(lines) + "\n", encoding="utf-8")


# ------------------------------ skills processing ------------------------------------


@dataclass(frozen=True)
class Skill:
	name: str
	description: str
	surfaces: frozenset[str]
	path: Path


class SkillLibrary:
	def __init__(self, root: str | Path = SKILLS_ROOT) -> None:
		self._root = Path(root)
		self._skills: dict[str, Skill] | None = None

	def _discover(self) -> dict[str, Skill]:
		if self._skills is not None:
			return self._skills

		skills: dict[str, Skill] = {}
		for path in sorted(self._root.glob("*/SKILL.md")):
			meta, _ = parse_frontmatter(path.read_text(encoding="utf-8"))
			name = path.parent.name
			if meta.get("name") and meta["name"] != name:
				# The directory is what load_skill is called with, so it wins.
				log.warning("skill %s declares name %r, using the directory", name, meta["name"])
			if not meta.get("description"):
				log.warning("skill %s has no description, skipping", name)
				continue
			surfaces = {s.strip() for s in meta.get("surfaces", "text, voice").split(",")}
			skills[name] = Skill(
				name=name,
				description=meta["description"],
				surfaces=frozenset(surfaces & set(SURFACES)),
				path=path,
			)

		self._skills = skills
		return skills

	def manifest(self, surface: str) -> list[Skill]:
		return [s for s in self._discover().values() if surface in s.surfaces]

	def body(self, name: str) -> str | None:
		skill = self._discover().get(name)
		if skill is None:
			return None
		_, body = parse_frontmatter(skill.path.read_text(encoding="utf-8"))
		return body


# --------------------------- singletons ----------------------------

_MEMORY: MemoryStore | None = None
_SKILLS: SkillLibrary | None = None

def get_memory() -> MemoryStore:
	global _MEMORY
	if _MEMORY is None:
		_MEMORY = MemoryStore(CONFIG.memory_dir)
	return _MEMORY

def get_skills() -> SkillLibrary:
	global _SKILLS
	if _SKILLS is None:
		_SKILLS = SkillLibrary()
	return _SKILLS
