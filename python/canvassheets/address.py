"""Spreadsheet address parsing.

Conventions (match the app and the spec, README §5.4):
  * Columns are letters: A, B, ..., Z, AA, AB, ...
  * Rows are 0-based: the first row is ``0`` (so ``A0`` is the top-left cell).
  * A bare reference (``A0``, ``A``, ``A0:C9``) targets the table body. Label
    bands are reached through the band proxies (``table.top[...]`` etc.), not here.

These functions are pure (no pandas) so they can be tested in isolation.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Tuple, Union

__all__ = [
    "AddressError",
    "column_index",
    "column_label",
    "parse_cell",
    "parse_range",
    "classify",
    "CellRef",
    "ColRef",
    "RangeRef",
    "ColRangeRef",
    "NameRef",
]


class AddressError(ValueError):
    """Raised when a reference string cannot be parsed."""


_CELL_RE = re.compile(r"^([A-Za-z]+)([0-9]+)$")
_COL_RE = re.compile(r"^([A-Za-z]+)$")
_RANGE_RE = re.compile(r"^([A-Za-z]+)([0-9]+):([A-Za-z]+)([0-9]+)$")
_COLRANGE_RE = re.compile(r"^([A-Za-z]+):([A-Za-z]+)$")

# For classification only, an A1-style reference must be UPPERCASE. A token that
# contains a lowercase letter is treated as a column *name* (e.g. "Revenue",
# "Total"). This resolves the letter-vs-name ambiguity. Table indexing also
# resolves header names first, so a header like "Q1" wins over cell Q1.
_U_CELL_RE = re.compile(r"^([A-Z]+)([0-9]+)$")
_U_COL_RE = re.compile(r"^([A-Z]+)$")
_U_RANGE_RE = re.compile(r"^([A-Z]+)([0-9]+):([A-Z]+)([0-9]+)$")
_U_COLRANGE_RE = re.compile(r"^([A-Z]+):([A-Z]+)$")


def column_index(label: str) -> int:
    """``"A" -> 0``, ``"Z" -> 25``, ``"AA" -> 26``."""
    upper = label.strip().upper()
    if not upper or not upper.isalpha():
        raise AddressError(f"Invalid column label: {label!r}")
    value = 0
    for ch in upper:
        value = value * 26 + (ord(ch) - ord("A") + 1)
    return value - 1


def column_label(index: int) -> str:
    """Inverse of :func:`column_index`. ``0 -> "A"``, ``26 -> "AA"``."""
    if index < 0:
        raise AddressError("Column index must be non-negative")
    number = index + 1
    chars = []
    while number > 0:
        number, remainder = divmod(number - 1, 26)
        chars.append(chr(ord("A") + remainder))
    return "".join(reversed(chars))


def parse_cell(ref: str) -> Tuple[int, int]:
    """``"A0" -> (0, 0)``, ``"B3" -> (3, 1)``. Returns ``(row, col)``."""
    match = _CELL_RE.match(ref.strip())
    if not match:
        raise AddressError(f"Invalid cell reference: {ref!r}")
    return int(match.group(2)), column_index(match.group(1))


def parse_range(ref: str) -> Tuple[int, int, int, int]:
    """``"A0:C9" -> (row0, col0, row1, col1)`` with start <= end on both axes.

    A single cell parses as a 1x1 range.
    """
    text = ref.strip()
    match = _RANGE_RE.match(text)
    if match:
        r0, c0 = int(match.group(2)), column_index(match.group(1))
        r1, c1 = int(match.group(4)), column_index(match.group(3))
        return (min(r0, r1), min(c0, c1), max(r0, r1), max(c0, c1))
    r, c = parse_cell(text)
    return (r, c, r, c)


# --- classification for Table indexing -------------------------------------

@dataclass(frozen=True)
class CellRef:
    row: int
    col: int


@dataclass(frozen=True)
class ColRef:
    col: int


@dataclass(frozen=True)
class RangeRef:
    row0: int
    col0: int
    row1: int
    col1: int


@dataclass(frozen=True)
class ColRangeRef:
    col0: int
    col1: int


@dataclass(frozen=True)
class NameRef:
    """A key that is not an A1-style reference: treated as a column name."""

    name: str


Ref = Union[CellRef, ColRef, RangeRef, ColRangeRef, NameRef]


def classify(key: str) -> Ref:
    """Classify a string index key used in ``table[key]``.

    Letter/cell/range forms are positional; anything else is a column name.
    """
    if not isinstance(key, str):
        raise AddressError(f"Index key must be a string, got {type(key).__name__}")
    text = key.strip()
    m = _U_RANGE_RE.match(text)
    if m:
        r0, c0 = int(m.group(2)), column_index(m.group(1))
        r1, c1 = int(m.group(4)), column_index(m.group(3))
        return RangeRef(min(r0, r1), min(c0, c1), max(r0, r1), max(c0, c1))
    m = _U_CELL_RE.match(text)
    if m:
        return CellRef(int(m.group(2)), column_index(m.group(1)))
    m = _U_COLRANGE_RE.match(text)
    if m:
        c0, c1 = column_index(m.group(1)), column_index(m.group(2))
        return ColRangeRef(min(c0, c1), max(c0, c1))
    m = _U_COL_RE.match(text)
    if m:
        return ColRef(column_index(text))
    return NameRef(text)
