.DEFAULT_GOAL := run
PYTHON ?= python3
MODE ?= debug
SUITE ?= swift
FILTER ?=
CATEGORY ?=
RELAUNCH ?= 0
export MODE SUITE FILTER CATEGORY RELAUNCH

.PHONY: run build test server logs help
run build test server logs help:
	$(PYTHON) -B scripts/dev.py $@
