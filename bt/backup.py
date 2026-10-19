"""Consistent SQLite backups, including committed writes still in the WAL."""

import argparse
from contextlib import closing
import os
import sqlite3
import tempfile
from datetime import datetime, timezone
from pathlib import Path


def backup_database(source: Path, destination: Path) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(dir=destination.parent, suffix='.sqlite3.tmp')
    os.close(fd)
    try:
        with closing(sqlite3.connect(source.resolve().as_uri() + '?mode=ro', uri=True)) as live:
            with closing(sqlite3.connect(temporary)) as backup:
                live.backup(backup)
                if backup.execute('PRAGMA integrity_check').fetchone() != ('ok',):
                    raise RuntimeError('Backup integrity check failed')
        # Linking fails if the destination exists, preserving earlier backups.
        os.link(temporary, destination)
    finally:
        Path(temporary).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('source', type=Path)
    parser.add_argument('directory', type=Path)
    args = parser.parse_args()
    name = datetime.now(timezone.utc).strftime('bt-%Y%m%dT%H%M%S%f.sqlite3')
    destination = args.directory / name
    backup_database(args.source, destination)
    for old in sorted(args.directory.glob('bt-*.sqlite3'))[:-14]:
        old.unlink()
    print(destination)


if __name__ == '__main__':
    main()
