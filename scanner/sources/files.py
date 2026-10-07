"""Local file source.

Walks the configured directories and yields text content from supported,
reasonably sized files. Binary formats are skipped by default; this is meant
for notes, exports, CSVs, and similar text-like files where secrets tend to
hide.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from typing import Iterator, List

from ..config import FilesConfig


@dataclass
class FileRecord:
    path: str
    size_bytes: int
    text: str

    @property
    def snippet(self) -> str:
        return " ".join(self.text.split())[:400]


class FileSource:
    def __init__(self, cfg: FilesConfig):
        self.cfg = cfg
        self._exts = {e.lower() for e in cfg.extensions}
        self._max_bytes = cfg.max_file_mb * 1024 * 1024

    def iter_files(self) -> Iterator[FileRecord]:
        for root_path in self.cfg.paths:
            root_path = os.path.expanduser(root_path)
            if os.path.isfile(root_path):
                rec = self._read(root_path)
                if rec:
                    yield rec
                continue
            for dirpath, dirnames, filenames in os.walk(root_path):
                # Skip hidden/system dirs to stay out of caches and VCS.
                dirnames[:] = [d for d in dirnames if not d.startswith(".")]
                for name in filenames:
                    ext = os.path.splitext(name)[1].lower()
                    if ext not in self._exts:
                        continue
                    rec = self._read(os.path.join(dirpath, name))
                    if rec:
                        yield rec

    def _read(self, path: str) -> FileRecord | None:
        try:
            size = os.path.getsize(path)
            if size > self._max_bytes:
                return None
            with open(path, "r", encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            return FileRecord(path=path, size_bytes=size, text=text)
        except (OSError, UnicodeError):
            return None
