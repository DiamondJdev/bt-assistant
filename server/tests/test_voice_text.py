import asyncio

from bt.voice import pipeline


async def _spoken(text: str) -> str:
    for _agg, transform in pipeline.TEXT_TRANSFORMS:
        text = await transform(text, "sentence")
    return text


def test_years_are_read_as_years():
    assert asyncio.run(_spoken("It shipped in 2025.")) == "It shipped in twenty twenty-five."
    assert asyncio.run(_spoken("Back in 1999")) == "Back in nineteen ninety-nine"


def test_non_years_are_left_alone():
    assert asyncio.run(_spoken("Port 8080, 42 items")) == "Port 8080, 42 items"


def test_markdown_is_stripped():
    assert asyncio.run(_spoken("**Done.** Use `ls` now.")) == "Done. Use ls now."
