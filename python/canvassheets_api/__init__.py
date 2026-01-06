from __future__ import annotations

import datetime
import math
import re
from contextlib import contextmanager
from dataclasses import dataclass, field
from pprint import pformat
from typing import Any, Dict, Iterable, List, Optional, Tuple

import numpy as np


class RangeParserError(ValueError):
    pass


def column_index(label: str) -> int:
    upper = label.strip().upper()
    if not upper:
        raise RangeParserError("Invalid column label")
    value = 0
    for ch in upper:
        if ch < "A" or ch > "Z":
            raise RangeParserError("Invalid column label")
        value = value * 26 + (ord(ch) - ord("A") + 1)
    return value - 1


def column_label(index: int) -> str:
    if index < 0:
        raise RangeParserError("Column index must be non-negative")
    number = index + 1
    chars: List[str] = []
    while number > 0:
        remainder = (number - 1) % 26
        chars.append(chr(ord("A") + remainder))
        number = (number - 1) // 26
    return "".join(reversed(chars))


def parse_cell(cell: str) -> Tuple[int, int]:
    trimmed = cell.strip()
    if not trimmed:
        raise RangeParserError("Invalid cell reference")
    letters = ""
    numbers = ""
    for ch in trimmed:
        if ch.isalpha() and not numbers:
            letters += ch
        else:
            numbers += ch
    if not letters or not numbers:
        raise RangeParserError("Invalid cell reference")
    if not numbers.isdigit():
        raise RangeParserError("Invalid cell reference")
    row_number = int(numbers)
    if row_number < 0:
        raise RangeParserError("Invalid cell reference")
    col_index = column_index(letters)
    return row_number, col_index


def cell_label(row: int, col: int) -> str:
    return f"{column_label(col)}{row}"


def address(region: str, row: int, col: int) -> str:
    return f"{region}[{cell_label(row, col)}]"


def _normalize_table_index(key: Any) -> Tuple[int, int]:
    if not isinstance(key, tuple) or len(key) != 2:
        raise TypeError("Table index must be a (row, col) tuple")
    row, col = key
    if not isinstance(row, int) or not isinstance(col, int):
        raise TypeError("Table index must be a (row, col) tuple")
    if row < 0 or col < 0:
        raise ValueError("Table indices must be non-negative")
    return row, col


def parse_range(range_str: str) -> Tuple[str, int, int, int, int]:
    trimmed = range_str.strip()
    if "[" not in trimmed or not trimmed.endswith("]"):
        raise RangeParserError("Invalid range format")
    region, inner = trimmed.split("[", 1)
    region = region.strip()
    inner = inner[:-1]
    if not region:
        raise RangeParserError("Invalid region")
    parts = inner.split(":")
    if len(parts) == 1:
        start_row, start_col = parse_cell(parts[0])
        return region, start_row, start_col, start_row, start_col
    if len(parts) == 2:
        start_row, start_col = parse_cell(parts[0])
        end_row, end_col = parse_cell(parts[1])
        return region, start_row, start_col, end_row, end_col
    raise RangeParserError("Invalid range format")


class FormulaError(ValueError):
    pass


_FORMULA_CELL_RE = re.compile(r"^[A-Za-z]+[0-9]+$")
_active_formula_table: Optional["Table"] = None
_active_label_context: Optional[Tuple["Table", str]] = None
_LABEL_REGIONS = {"top_labels", "bottom_labels", "left_labels", "right_labels"}
_FORMULA_ORDER_COUNTER = 0
_DEFAULT_CELL_WIDTH = 80.0
_DEFAULT_CELL_HEIGHT = 24.0
_DEFAULT_TABLE_OFFSET = 24.0
_DEFAULT_TABLE_ORIGIN = 80.0


def _next_formula_order() -> int:
    global _FORMULA_ORDER_COUNTER
    _FORMULA_ORDER_COUNTER += 1
    return _FORMULA_ORDER_COUNTER


class FormulaExpr:
    def __init__(self, expr: str) -> None:
        self.expr = expr

    def __add__(self, other: Any) -> "FormulaExpr":
        return FormulaExpr(f"{self.expr}+{_formula_literal(other)}")

    def __radd__(self, other: Any) -> "FormulaExpr":
        return FormulaExpr(f"{_formula_literal(other)}+{self.expr}")

    def __sub__(self, other: Any) -> "FormulaExpr":
        return FormulaExpr(f"{self.expr}-{_formula_literal(other)}")

    def __rsub__(self, other: Any) -> "FormulaExpr":
        return FormulaExpr(f"{_formula_literal(other)}-{self.expr}")

    def __mul__(self, other: Any) -> "FormulaExpr":
        return FormulaExpr(f"{self.expr}*{_formula_literal(other)}")

    def __rmul__(self, other: Any) -> "FormulaExpr":
        return FormulaExpr(f"{_formula_literal(other)}*{self.expr}")

    def __truediv__(self, other: Any) -> "FormulaExpr":
        return FormulaExpr(f"{self.expr}/{_formula_literal(other)}")

    def __rtruediv__(self, other: Any) -> "FormulaExpr":
        return FormulaExpr(f"{_formula_literal(other)}/{self.expr}")

    def __pow__(self, other: Any) -> "FormulaExpr":
        return FormulaExpr(f"{self.expr}^{_formula_literal(other)}")

    def __rpow__(self, other: Any) -> "FormulaExpr":
        return FormulaExpr(f"{_formula_literal(other)}^{self.expr}")

    def __xor__(self, other: Any) -> "FormulaExpr":
        return FormulaExpr(f"{self.expr}^{_formula_literal(other)}")

    def __rxor__(self, other: Any) -> "FormulaExpr":
        return FormulaExpr(f"{_formula_literal(other)}^{self.expr}")

    def __neg__(self) -> "FormulaExpr":
        return FormulaExpr(f"-{self.expr}")

    def __pos__(self) -> "FormulaExpr":
        return FormulaExpr(f"+{self.expr}")


class FormulaCell(FormulaExpr):
    def __init__(self, cell_ref: str) -> None:
        super().__init__(cell_ref)


def _formula_literal(value: Any) -> str:
    if isinstance(value, FormulaExpr):
        return value.expr
    if isinstance(value, bool):
        return "TRUE" if value else "FALSE"
    if isinstance(value, (int, float, np.number)):
        return str(value)
    if isinstance(value, str):
        escaped = value.replace('"', '""')
        return f"\"{escaped}\""
    raise FormulaError("Unsupported literal in formula expression")


def _formula_arg(value: Any) -> str:
    if isinstance(value, FormulaExpr):
        return value.expr
    if isinstance(value, str):
        trimmed = value.strip()
        if not trimmed:
            raise FormulaError("Formula reference cannot be empty")
        return trimmed
    return _formula_literal(value)


def _formula_call(name: str, *args: Any) -> FormulaExpr:
    if not args:
        raise FormulaError(f"{name} requires at least one argument")
    parts = ", ".join(_formula_arg(arg) for arg in args)
    return FormulaExpr(f"{name}({parts})")


def c_range(ref: str) -> FormulaExpr:
    return FormulaExpr(_formula_arg(ref))


def c_sum(*args: Any) -> FormulaExpr:
    return _formula_call("SUM", *args)


def c_avg(*args: Any) -> FormulaExpr:
    return _formula_call("AVERAGE", *args)


def c_min(*args: Any) -> FormulaExpr:
    return _formula_call("MIN", *args)


def c_max(*args: Any) -> FormulaExpr:
    return _formula_call("MAX", *args)


def c_count(*args: Any) -> FormulaExpr:
    return _formula_call("COUNT", *args)


def c_counta(*args: Any) -> FormulaExpr:
    return _formula_call("COUNTA", *args)


def c_if(condition: Any, true_val: Any, false_val: Any) -> FormulaExpr:
    return _formula_call("IF", condition, true_val, false_val)


def c_and(*args: Any) -> FormulaExpr:
    return _formula_call("AND", *args)


def c_or(*args: Any) -> FormulaExpr:
    return _formula_call("OR", *args)


def c_not(value: Any) -> FormulaExpr:
    return _formula_call("NOT", value)


def c_pmt(rate: Any, nper: Any, pv: Any, fv: Any = 0, when: Any = 0) -> FormulaExpr:
    return _formula_call("PMT", rate, nper, pv, fv, when)


def c_abs(value: Any) -> FormulaExpr:
    return _formula_call("ABS", value)


def c_round(value: Any, digits: Any = 0) -> FormulaExpr:
    return _formula_call("ROUND", value, digits)


def c_floor(value: Any) -> FormulaExpr:
    return _formula_call("FLOOR", value)


def c_ceil(value: Any) -> FormulaExpr:
    return _formula_call("CEIL", value)


def c_sqrt(value: Any) -> FormulaExpr:
    return _formula_call("SQRT", value)


def c_pow(base: Any, exponent: Any) -> FormulaExpr:
    return _formula_call("POWER", base, exponent)


def c_log(value: Any, base: Any = None) -> FormulaExpr:
    if base is None:
        return _formula_call("LOG", value)
    return _formula_call("LOG", value, base)


def c_log10(value: Any) -> FormulaExpr:
    return _formula_call("LOG10", value)


def c_exp(value: Any) -> FormulaExpr:
    return _formula_call("EXP", value)


def c_sin(value: Any) -> FormulaExpr:
    return _formula_call("SIN", value)


def c_cos(value: Any) -> FormulaExpr:
    return _formula_call("COS", value)


def c_tan(value: Any) -> FormulaExpr:
    return _formula_call("TAN", value)


def formula_mode(table: Optional["Table"]) -> None:
    global _active_formula_table
    _active_formula_table = table


def formula(text: str) -> FormulaExpr:
    if not isinstance(text, str):
        raise FormulaError("formula() expects a string")
    trimmed = text.strip()
    if trimmed.startswith("="):
        trimmed = trimmed[1:].strip()
    if not trimmed:
        raise FormulaError("formula() cannot be empty")
    return FormulaExpr(trimmed)


def date_value(value: Any) -> Dict[str, Any]:
    if isinstance(value, datetime.datetime):
        value = value.date()
    if isinstance(value, datetime.date):
        return {"type": "date", "value": value.isoformat()}
    if isinstance(value, str):
        try:
            parsed = datetime.date.fromisoformat(value)
        except ValueError as exc:
            raise ValueError("date_value expects YYYY-MM-DD") from exc
        return {"type": "date", "value": parsed.isoformat()}
    return {"type": "date", "value": str(value)}


def time_value(value: Any) -> Dict[str, Any]:
    if isinstance(value, datetime.datetime):
        value = value.time()
    if isinstance(value, datetime.time):
        return {"type": "time", "value": value.strftime("%H:%M:%S")}
    if isinstance(value, str):
        try:
            parsed = datetime.time.fromisoformat(value)
        except ValueError as exc:
            raise ValueError("time_value expects HH:MM or HH:MM:SS") from exc
        return {"type": "time", "value": parsed.strftime("%H:%M:%S")}
    return {"type": "time", "value": str(value)}


@contextmanager
def table_context(table: "Table"):
    previous = _active_formula_table
    formula_mode(table)
    try:
        yield
    finally:
        formula_mode(previous)


@contextmanager
def label_context(table: "Table", region: str):
    global _active_label_context, _active_formula_table
    previous_label = _active_label_context
    previous_formula = _active_formula_table
    _active_label_context = (table, region)
    _active_formula_table = None
    try:
        yield
    finally:
        _active_label_context = previous_label
        _active_formula_table = previous_formula


class LabelRegionProxy:
    def __init__(self, table: "Table", region: str) -> None:
        object.__setattr__(self, "_table", table)
        object.__setattr__(self, "_region", region)

    def __getattr__(self, name: str) -> Any:
        if _FORMULA_CELL_RE.match(name):
            cell_ref = name.upper()
            return FormulaExpr(f"{self._region}[{cell_ref}]")
        raise AttributeError(name)

    def __setattr__(self, name: str, value: Any) -> None:
        if name.startswith("_"):
            return object.__setattr__(self, name, value)
        if not _FORMULA_CELL_RE.match(name):
            raise AttributeError(name)
        cell_ref = name.upper()
        key = f"{self._region}[{cell_ref}]"
        if isinstance(value, FormulaExpr):
            self._table.set_formula(key, f"={value.expr}")
            return
        self._table.set_cells({key: value})


class FormulaLocals(dict):
    def __missing__(self, key: str) -> Any:
        if _active_formula_table is not None and _FORMULA_CELL_RE.match(key):
            cell_ref = key.upper()
            value = FormulaCell(cell_ref)
            self[key] = value
            return value
        if _active_formula_table is not None and key in _LABEL_REGIONS:
            proxy = LabelRegionProxy(_active_formula_table, key)
            self[key] = proxy
            return proxy
        builtins_obj = self.get("__builtins__", __builtins__)
        if isinstance(builtins_obj, dict):
            if key in builtins_obj:
                return builtins_obj[key]
        else:
            if hasattr(builtins_obj, key):
                return getattr(builtins_obj, key)
        raise KeyError(key)

    def __setitem__(self, key: str, value: Any) -> None:
        if _active_formula_table is not None and _FORMULA_CELL_RE.match(key):
            cell_ref = key.upper()
            if isinstance(value, FormulaExpr):
                _active_formula_table.set_formula(f"body[{cell_ref}]", f"={value.expr}")
                return super().__setitem__(key, FormulaCell(cell_ref))
            _active_formula_table.set_cells({f"body[{cell_ref}]": value})
            return super().__setitem__(key, FormulaCell(cell_ref))
        if _active_label_context is not None and _FORMULA_CELL_RE.match(key):
            table, region = _active_label_context
            cell_ref = key.upper()
            if isinstance(value, FormulaExpr):
                table.set_formula(f"{region}[{cell_ref}]", f"={value.expr}")
                return super().__setitem__(key, FormulaCell(cell_ref))
            table.set_cells({f"{region}[{cell_ref}]": value})
            return super().__setitem__(key, FormulaCell(cell_ref))
        return super().__setitem__(key, value)


@dataclass(frozen=True)
class Token:
    type: str
    value: str
    pos: int


_CELL_TOKEN_RE = re.compile(r"\$?[A-Za-z]+\$?\d+")
_NUMBER_TOKEN_RE = re.compile(r"(?:\d+\.\d*|\d+|\.\d+)")
_IDENT_TOKEN_RE = re.compile(r"[A-Za-z_][A-Za-z0-9_\.\$]*")
_CELL_REF_RE = re.compile(r"(\$?)([A-Za-z]+)(\$?)(\d+)")


def _tokenize_formula(text: str) -> List[Token]:
    tokens: List[Token] = []
    index = 0
    length = len(text)
    def next_non_space(pos: int) -> str:
        while pos < length and text[pos].isspace():
            pos += 1
        return text[pos] if pos < length else ""
    while index < length:
        ch = text[index]
        if ch.isspace():
            index += 1
            continue
        if ch in "+-*/^":
            tokens.append(Token("OP", ch, index))
            index += 1
            continue
        if ch in "(),:[]":
            tokens.append(Token(ch, ch, index))
            index += 1
            continue
        match = _CELL_TOKEN_RE.match(text, index)
        if match:
            next_char = next_non_space(match.end())
            token_type = "IDENT" if next_char == "(" else "CELL"
            tokens.append(Token(token_type, match.group(0), index))
            index = match.end()
            continue
        match = _NUMBER_TOKEN_RE.match(text, index)
        if match:
            tokens.append(Token("NUMBER", match.group(0), index))
            index = match.end()
            continue
        match = _IDENT_TOKEN_RE.match(text, index)
        if match:
            tokens.append(Token("IDENT", match.group(0), index))
            index = match.end()
            continue
        raise FormulaError(f"Unexpected character '{ch}' at position {index}")
    tokens.append(Token("EOF", "", index))
    return tokens


@dataclass(frozen=True)
class CellRef:
    row: int
    col: int
    row_abs: bool
    col_abs: bool


@dataclass(frozen=True)
class NumberNode:
    value: float


@dataclass(frozen=True)
class BoolNode:
    value: bool


@dataclass(frozen=True)
class UnaryOpNode:
    op: str
    operand: Any


@dataclass(frozen=True)
class BinaryOpNode:
    op: str
    left: Any
    right: Any


@dataclass(frozen=True)
class FuncCallNode:
    name: str
    args: List[Any]


@dataclass(frozen=True)
class CellRefNode:
    table_id: Optional[str]
    region: str
    cell: CellRef


@dataclass(frozen=True)
class RangeRefNode:
    table_id: Optional[str]
    region: str
    start: CellRef
    end: CellRef


@dataclass(frozen=True)
class ColumnRefNode:
    table_id: Optional[str]
    region: str
    col: int


@dataclass(frozen=True)
class RowRefNode:
    table_id: Optional[str]
    region: str
    row: int


class FormulaParser:
    def __init__(self, text: str) -> None:
        trimmed = text.strip()
        if trimmed.startswith("="):
            trimmed = trimmed[1:].strip()
        self.text = trimmed
        self.tokens = _tokenize_formula(self.text)
        self.index = 0

    def parse(self) -> Any:
        if self._peek().type == "EOF":
            raise FormulaError("Empty formula")
        expr = self._parse_expression()
        if self._peek().type != "EOF":
            token = self._peek()
            raise FormulaError(f"Unexpected token '{token.value}' at position {token.pos}")
        return expr

    def _peek(self, offset: int = 0) -> Token:
        return self.tokens[self.index + offset]

    def _advance(self) -> Token:
        token = self.tokens[self.index]
        self.index += 1
        return token

    def _match(self, token_type: str) -> bool:
        if self._peek().type == token_type:
            self._advance()
            return True
        return False

    def _parse_expression(self) -> Any:
        node = self._parse_term()
        while self._peek().type == "OP" and self._peek().value in "+-":
            op = self._advance().value
            right = self._parse_term()
            node = BinaryOpNode(op=op, left=node, right=right)
        return node

    def _parse_term(self) -> Any:
        node = self._parse_power()
        while self._peek().type == "OP" and self._peek().value in "*/":
            op = self._advance().value
            right = self._parse_power()
            node = BinaryOpNode(op=op, left=node, right=right)
        return node

    def _parse_power(self) -> Any:
        node = self._parse_unary()
        if self._peek().type == "OP" and self._peek().value == "^":
            op = self._advance().value
            right = self._parse_power()
            node = BinaryOpNode(op=op, left=node, right=right)
        return node

    def _parse_unary(self) -> Any:
        if self._peek().type == "OP" and self._peek().value in "+-":
            op = self._advance().value
            operand = self._parse_unary()
            return UnaryOpNode(op=op, operand=operand)
        return self._parse_primary()

    def _parse_primary(self) -> Any:
        token = self._peek()
        if token.type == "NUMBER":
            self._advance()
            return NumberNode(value=float(token.value))
        if token.type == "CELL":
            return self._parse_reference()
        if token.type == "IDENT":
            upper = token.value.upper()
            if upper in {"COL", "ROW"} and self._peek(1).type == "(":
                return self._parse_col_row_function()
            if self._peek(1).type == "(":
                return self._parse_function_call()
            if "." in token.value:
                dotted = self._advance().value
                table_id, ref = dotted.split(".", 1)
                if not table_id or not ref:
                    raise FormulaError("Invalid table reference")
                if self._peek().type == "[":
                    return self._parse_table_region_reference(table_id, ref)
                return self._parse_table_dot_reference(table_id, ref)
            if self._peek(1).type == "[":
                return self._parse_reference()
            if upper == "TRUE" or upper == "FALSE":
                self._advance()
                return BoolNode(value=(upper == "TRUE"))
        if token.type == "(":
            self._advance()
            expr = self._parse_expression()
            if not self._match(")"):
                raise FormulaError("Expected ')'")
            return expr
        raise FormulaError(f"Unexpected token '{token.value}' at position {token.pos}")

    def _parse_function_call(self) -> Any:
        name = self._advance().value
        if not self._match("("):
            raise FormulaError("Expected '(' after function name")
        args: List[Any] = []
        if self._peek().type != ")":
            while True:
                args.append(self._parse_expression())
                if self._match(")"):
                    break
                if not self._match(","):
                    raise FormulaError("Expected ',' or ')' in function call")
        else:
            self._advance()
        return FuncCallNode(name=name, args=args)

    def _parse_reference(self, table_id: Optional[str] = None) -> Any:
        token = self._peek()
        if token.type == "IDENT" and self._peek(1).type == "[":
            region = self._advance().value
            self._advance()
            start = self._parse_cell_token()
            end = start
            if self._match(":"):
                end = self._parse_cell_token()
            if not self._match("]"):
                raise FormulaError("Expected ']' in range reference")
            if start == end:
                return CellRefNode(table_id=table_id, region=region, cell=start)
            return RangeRefNode(table_id=table_id, region=region, start=start, end=end)
        if token.type == "IDENT" and self._peek(1).type != "[":
            if table_id is not None:
                col = self._parse_column_label(self._advance())
                return ColumnRefNode(table_id=table_id, region="body", col=col)
        if token.type == "CELL":
            start = self._parse_cell_token()
            end = start
            if self._match(":"):
                end = self._parse_cell_token()
            if start == end:
                return CellRefNode(table_id=table_id, region="body", cell=start)
            return RangeRefNode(table_id=table_id, region="body", start=start, end=end)
        raise FormulaError("Invalid reference syntax")

    def _parse_table_region_reference(self, table_id: str, region: str) -> Any:
        if not self._match("["):
            raise FormulaError("Expected '[' in range reference")
        start = self._parse_cell_token()
        end = start
        if self._match(":"):
            end = self._parse_cell_token()
        if not self._match("]"):
            raise FormulaError("Expected ']' in range reference")
        if start == end:
            return CellRefNode(table_id=table_id, region=region, cell=start)
        return RangeRefNode(table_id=table_id, region=region, start=start, end=end)

    def _parse_table_dot_reference(self, table_id: str, ref: str) -> Any:
        if _CELL_REF_RE.fullmatch(ref):
            start = self._parse_cell_string(ref)
            end = start
            if self._match(":"):
                end = self._parse_cell_token()
            if start == end:
                return CellRefNode(table_id=table_id, region="body", cell=start)
            return RangeRefNode(table_id=table_id, region="body", start=start, end=end)
        if ref.isalpha():
            return ColumnRefNode(table_id=table_id, region="body", col=column_index(ref))
        if ref.isdigit():
            row_number = int(ref)
            if row_number < 0:
                raise FormulaError("Invalid row reference")
            return RowRefNode(table_id=table_id, region="body", row=row_number)
        raise FormulaError("Invalid reference syntax")

    def _parse_cell_token(self) -> CellRef:
        token = self._advance()
        if token.type != "CELL":
            raise FormulaError("Expected cell reference")
        return self._parse_cell_string(token.value)

    def _parse_cell_string(self, value: str) -> CellRef:
        match = _CELL_REF_RE.fullmatch(value)
        if not match:
            raise FormulaError("Invalid cell reference")
        col_abs = match.group(1) == "$"
        row_abs = match.group(3) == "$"
        col_label = match.group(2)
        row_number = int(match.group(4))
        if row_number < 0:
            raise FormulaError("Invalid cell reference")
        return CellRef(
            row=row_number,
            col=column_index(col_label),
            row_abs=row_abs,
            col_abs=col_abs,
        )

    def _parse_column_label(self, token: Token) -> int:
        label = token.value
        if not label.isalpha():
            raise FormulaError("Invalid column reference")
        return column_index(label)

    def _parse_row_number(self, token: Token) -> int:
        if not token.value.isdigit():
            raise FormulaError("Row reference must be an integer")
        row_number = int(token.value)
        if row_number < 0:
            raise FormulaError("Invalid row reference")
        return row_number

    def _parse_col_row_function(self) -> Any:
        name = self._advance().value.upper()
        if not self._match("("):
            raise FormulaError("Expected '(' after function name")
        token = self._peek()
        if name == "COL":
            if token.type == "CELL":
                cell = self._parse_cell_token()
                col = cell.col
            elif token.type == "IDENT":
                col = self._parse_column_label(self._advance())
            else:
                raise FormulaError("Invalid COL reference")
            if not self._match(")"):
                raise FormulaError("Expected ')' after COL")
            return ColumnRefNode(table_id=None, region="body", col=col)
        if name == "ROW":
            if token.type == "CELL":
                cell = self._parse_cell_token()
                row = cell.row
            elif token.type == "NUMBER":
                row = self._parse_row_number(self._advance())
            else:
                raise FormulaError("Invalid ROW reference")
            if not self._match(")"):
                raise FormulaError("Expected ')' after ROW")
            return RowRefNode(table_id=None, region="body", row=row)
        raise FormulaError(f"Unknown function: {name}")


@dataclass(frozen=True)
class FormulaContext:
    project: "Project"
    table: "Table"
    anchor_row: int
    anchor_col: int
    target_row: int
    target_col: int


def _normalize_ref(ref: str) -> str:
    trimmed = ref.strip()
    if "[" in trimmed:
        return trimmed
    return f"body[{trimmed}]"


def _unwrap_value(value: Any) -> Any:
    if isinstance(value, dict) and "type" in value:
        value_type = value.get("type")
        if value_type == "number":
            return float(value.get("value", 0))
        if value_type == "string":
            return str(value.get("value", ""))
        if value_type == "bool":
            return bool(value.get("value", False))
        if value_type == "date":
            raw = str(value.get("value", ""))
            try:
                return datetime.date.fromisoformat(raw)
            except ValueError:
                return None
        if value_type == "time":
            raw = str(value.get("value", ""))
            try:
                return datetime.time.fromisoformat(raw)
            except ValueError:
                return None
        return None
    return value


def _resolve_cell_ref(cell: CellRef, context: FormulaContext) -> Tuple[int, int]:
    row_offset = context.target_row - context.anchor_row
    col_offset = context.target_col - context.anchor_col
    row = cell.row if cell.row_abs else cell.row + row_offset
    col = cell.col if cell.col_abs else cell.col + col_offset
    if row < 0 or col < 0:
        raise FormulaError("Reference out of bounds")
    return row, col


def _resolve_table(context: FormulaContext, table_id: Optional[str]) -> "Table":
    if table_id is None:
        return context.table
    return context.project.table(table_id)


def _cell_value(table: "Table", region: str, row: int, col: int) -> Any:
    key = address(region, row, col)
    return _unwrap_value(table.cell_values.get(key))


def _range_values(table: "Table", region: str, start: CellRef, end: CellRef,
                  context: FormulaContext) -> List[List[Any]]:
    start_row, start_col = _resolve_cell_ref(start, context)
    end_row, end_col = _resolve_cell_ref(end, context)
    row_start, row_end = sorted((start_row, end_row))
    col_start, col_end = sorted((start_col, end_col))
    values: List[List[Any]] = []
    for row in range(row_start, row_end + 1):
        row_values = []
        for col in range(col_start, col_end + 1):
            row_values.append(_cell_value(table, region, row, col))
        values.append(row_values)
    return values


def _column_values(table: "Table", region: str, col: int) -> List[Any]:
    if region != "body":
        raise FormulaError("Column references require body region")
    return [_cell_value(table, region, row, col) for row in range(table.grid_spec.bodyRows)]


def _row_values(table: "Table", region: str, row: int) -> List[Any]:
    if region != "body":
        raise FormulaError("Row references require body region")
    return [_cell_value(table, region, row, col) for col in range(table.grid_spec.bodyCols)]


def _iter_values(value: Any) -> Iterable[Any]:
    if isinstance(value, np.ndarray):
        for item in value.flat:
            yield item
    elif isinstance(value, (list, tuple)):
        for item in value:
            yield from _iter_values(item)
    else:
        yield value


def _coerce_number(value: Any) -> Optional[float]:
    if value is None:
        return None
    if isinstance(value, bool):
        return float(int(value))
    if isinstance(value, (int, float, np.number)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return None
    return None


def _require_number(value: Any) -> float:
    number = _coerce_number(value)
    if number is None:
        raise FormulaError("Expected numeric value")
    return number


def _numeric_values(value: Any) -> List[float]:
    numbers: List[float] = []
    for item in _iter_values(value):
        number = _coerce_number(item)
        if number is not None:
            numbers.append(number)
    return numbers


def _ensure_scalar(value: Any) -> Any:
    if isinstance(value, np.ndarray):
        if value.size == 1:
            return value.item()
        raise FormulaError("Expected scalar value")
    if isinstance(value, (list, tuple)):
        if len(value) == 1 and not isinstance(value[0], (list, tuple, np.ndarray)):
            return value[0]
        raise FormulaError("Expected scalar value")
    return value


def _to_numeric_array(values: Any) -> np.ndarray:
    array = np.array(values, dtype=object)

    def convert(item: Any) -> float:
        number = _coerce_number(item)
        return math.nan if number is None else number

    return np.vectorize(convert, otypes=[float])(array)


def cs_sum(*args: Any, axis: Optional[int] = None) -> Any:
    if axis is not None:
        values = args[0] if len(args) == 1 else list(args)
        return np.nansum(_to_numeric_array(values), axis=axis)
    values = args[0] if len(args) == 1 else list(args)
    numbers = _numeric_values(values)
    return sum(numbers)


def cs_avg(*args: Any, axis: Optional[int] = None) -> Any:
    if axis is not None:
        values = args[0] if len(args) == 1 else list(args)
        return np.nanmean(_to_numeric_array(values), axis=axis)
    values = args[0] if len(args) == 1 else list(args)
    numbers = _numeric_values(values)
    if not numbers:
        return math.nan
    return sum(numbers) / len(numbers)


def cs_min(*args: Any) -> Any:
    values = args[0] if len(args) == 1 else list(args)
    numbers = _numeric_values(values)
    return min(numbers) if numbers else None


def cs_max(*args: Any) -> Any:
    values = args[0] if len(args) == 1 else list(args)
    numbers = _numeric_values(values)
    return max(numbers) if numbers else None


def cs_count(*args: Any) -> int:
    values = args[0] if len(args) == 1 else list(args)
    return sum(1 for value in _iter_values(values) if _coerce_number(value) is not None)


def cs_counta(*args: Any) -> int:
    values = args[0] if len(args) == 1 else list(args)
    return sum(1 for value in _iter_values(values) if value not in (None, ""))


def cs_if(condition: Any, true_value: Any, false_value: Any) -> Any:
    if isinstance(condition, np.ndarray):
        return np.where(condition, true_value, false_value)
    return true_value if bool(condition) else false_value


def cs_and(*args: Any) -> bool:
    values = args[0] if len(args) == 1 else list(args)
    return all(bool(value) for value in _iter_values(values))


def cs_or(*args: Any) -> bool:
    values = args[0] if len(args) == 1 else list(args)
    return any(bool(value) for value in _iter_values(values))


def cs_not(value: Any) -> bool:
    return not bool(value)


def cs_pmt(rate: Any, nper: Any, pv: Any, fv: Any = 0, when: Any = 0) -> float:
    rate_num = _require_number(rate)
    nper_num = _require_number(nper)
    pv_num = _require_number(pv)
    fv_num = _require_number(fv)
    when_num = _require_number(when)
    if nper_num == 0:
        raise FormulaError("PMT requires nper != 0")
    if rate_num == 0:
        return -(pv_num + fv_num) / nper_num
    factor = (1 + rate_num) ** nper_num
    denom = (1 + rate_num * when_num) * (factor - 1)
    if denom == 0:
        raise FormulaError("PMT division by zero")
    return -(rate_num * (fv_num + pv_num * factor)) / denom


def cs_abs(value: Any) -> Any:
    if isinstance(value, (np.ndarray, list, tuple)):
        return np.abs(_to_numeric_array(value))
    return abs(_require_number(value))


def cs_round(value: Any, digits: Any = 0) -> Any:
    digits_num = int(_require_number(digits))
    if isinstance(value, (np.ndarray, list, tuple)):
        return np.round(_to_numeric_array(value), decimals=digits_num)
    return round(_require_number(value), digits_num)


def cs_floor(value: Any) -> Any:
    if isinstance(value, (np.ndarray, list, tuple)):
        return np.floor(_to_numeric_array(value))
    return math.floor(_require_number(value))


def cs_ceil(value: Any) -> Any:
    if isinstance(value, (np.ndarray, list, tuple)):
        return np.ceil(_to_numeric_array(value))
    return math.ceil(_require_number(value))


def cs_sqrt(value: Any) -> Any:
    if isinstance(value, (np.ndarray, list, tuple)):
        array = _to_numeric_array(value)
        if np.any(array < 0):
            raise FormulaError("SQRT requires non-negative values")
        return np.sqrt(array)
    number = _require_number(value)
    if number < 0:
        raise FormulaError("SQRT requires non-negative values")
    return math.sqrt(number)


def cs_pow(base: Any, exponent: Any) -> Any:
    if isinstance(base, (np.ndarray, list, tuple)) or isinstance(exponent, (np.ndarray, list, tuple)):
        return np.power(_to_numeric_array(base), _to_numeric_array(exponent))
    return math.pow(_require_number(base), _require_number(exponent))


def cs_log(value: Any, base: Any = None) -> Any:
    if isinstance(value, (np.ndarray, list, tuple)):
        array = _to_numeric_array(value)
        if np.any(array <= 0):
            raise FormulaError("LOG requires positive values")
        result = np.log(array)
        if base is None:
            return result
        base_num = _require_number(base)
        if base_num <= 0 or base_num == 1:
            raise FormulaError("LOG base must be positive and not 1")
        return result / math.log(base_num)
    number = _require_number(value)
    if number <= 0:
        raise FormulaError("LOG requires positive values")
    if base is None:
        return math.log(number)
    base_num = _require_number(base)
    if base_num <= 0 or base_num == 1:
        raise FormulaError("LOG base must be positive and not 1")
    return math.log(number, base_num)


def cs_log10(value: Any) -> Any:
    if isinstance(value, (np.ndarray, list, tuple)):
        array = _to_numeric_array(value)
        if np.any(array <= 0):
            raise FormulaError("LOG10 requires positive values")
        return np.log10(array)
    number = _require_number(value)
    if number <= 0:
        raise FormulaError("LOG10 requires positive values")
    return math.log10(number)


def cs_exp(value: Any) -> Any:
    if isinstance(value, (np.ndarray, list, tuple)):
        return np.exp(_to_numeric_array(value))
    return math.exp(_require_number(value))


def cs_sin(value: Any) -> Any:
    if isinstance(value, (np.ndarray, list, tuple)):
        return np.sin(_to_numeric_array(value))
    return math.sin(_require_number(value))


def cs_cos(value: Any) -> Any:
    if isinstance(value, (np.ndarray, list, tuple)):
        return np.cos(_to_numeric_array(value))
    return math.cos(_require_number(value))


def cs_tan(value: Any) -> Any:
    if isinstance(value, (np.ndarray, list, tuple)):
        return np.tan(_to_numeric_array(value))
    return math.tan(_require_number(value))


def _evaluate_formula(node: Any, context: FormulaContext) -> Any:
    if isinstance(node, NumberNode):
        return node.value
    if isinstance(node, BoolNode):
        return node.value
    if isinstance(node, UnaryOpNode):
        value = _ensure_scalar(_evaluate_formula(node.operand, context))
        if node.op == "-":
            return -_require_number(value)
        if node.op == "+":
            return _require_number(value)
        raise FormulaError(f"Unsupported unary operator: {node.op}")
    if isinstance(node, BinaryOpNode):
        left = _ensure_scalar(_evaluate_formula(node.left, context))
        right = _ensure_scalar(_evaluate_formula(node.right, context))
        if node.op == "+":
            return _require_number(left) + _require_number(right)
        if node.op == "-":
            return _require_number(left) - _require_number(right)
        if node.op == "*":
            return _require_number(left) * _require_number(right)
        if node.op == "/":
            return _require_number(left) / _require_number(right)
        if node.op == "^":
            return math.pow(_require_number(left), _require_number(right))
        raise FormulaError(f"Unsupported operator: {node.op}")
    if isinstance(node, FuncCallNode):
        name = node.name.upper()
        if "." in name:
            name = name.split(".")[-1]
        if name == "MEAN":
            name = "AVERAGE"
        args = [_evaluate_formula(arg, context) for arg in node.args]
        if name == "SUM":
            return cs_sum(*args)
        if name == "AVERAGE":
            return cs_avg(*args)
        if name == "MIN":
            return cs_min(*args)
        if name == "MAX":
            return cs_max(*args)
        if name == "COUNT":
            return cs_count(*args)
        if name == "COUNTA":
            return cs_counta(*args)
        if name == "IF":
            if len(args) != 3:
                raise FormulaError("IF requires 3 arguments")
            return cs_if(args[0], args[1], args[2])
        if name == "AND":
            return cs_and(*args)
        if name == "OR":
            return cs_or(*args)
        if name == "NOT":
            if len(args) != 1:
                raise FormulaError("NOT requires 1 argument")
            return cs_not(args[0])
        if name == "PMT":
            if len(args) not in (3, 4, 5):
                raise FormulaError("PMT requires 3 to 5 arguments")
            return cs_pmt(*args)
        if name == "ABS":
            if len(args) != 1:
                raise FormulaError("ABS requires 1 argument")
            return cs_abs(args[0])
        if name == "ROUND":
            if len(args) not in (1, 2):
                raise FormulaError("ROUND requires 1 or 2 arguments")
            return cs_round(*args)
        if name == "FLOOR":
            if len(args) != 1:
                raise FormulaError("FLOOR requires 1 argument")
            return cs_floor(args[0])
        if name == "CEIL":
            if len(args) != 1:
                raise FormulaError("CEIL requires 1 argument")
            return cs_ceil(args[0])
        if name == "SQRT":
            if len(args) != 1:
                raise FormulaError("SQRT requires 1 argument")
            return cs_sqrt(args[0])
        if name == "POWER":
            if len(args) != 2:
                raise FormulaError("POWER requires 2 arguments")
            return cs_pow(args[0], args[1])
        if name == "LOG":
            if len(args) not in (1, 2):
                raise FormulaError("LOG requires 1 or 2 arguments")
            return cs_log(*args)
        if name == "LOG10":
            if len(args) != 1:
                raise FormulaError("LOG10 requires 1 argument")
            return cs_log10(args[0])
        if name == "EXP":
            if len(args) != 1:
                raise FormulaError("EXP requires 1 argument")
            return cs_exp(args[0])
        if name == "SIN":
            if len(args) != 1:
                raise FormulaError("SIN requires 1 argument")
            return cs_sin(args[0])
        if name == "COS":
            if len(args) != 1:
                raise FormulaError("COS requires 1 argument")
            return cs_cos(args[0])
        if name == "TAN":
            if len(args) != 1:
                raise FormulaError("TAN requires 1 argument")
            return cs_tan(args[0])
        raise FormulaError(f"Unknown function: {name}")
    if isinstance(node, CellRefNode):
        table = _resolve_table(context, node.table_id)
        row, col = _resolve_cell_ref(node.cell, context)
        return _cell_value(table, node.region, row, col)
    if isinstance(node, RangeRefNode):
        table = _resolve_table(context, node.table_id)
        return _range_values(table, node.region, node.start, node.end, context)
    if isinstance(node, ColumnRefNode):
        table = _resolve_table(context, node.table_id)
        values = _column_values(table, node.region, node.col)
        return np.array(values, dtype=object)
    if isinstance(node, RowRefNode):
        table = _resolve_table(context, node.table_id)
        values = _row_values(table, node.region, node.row)
        return np.array(values, dtype=object)
    raise FormulaError("Invalid formula")

def _cell_value_to_json(value: Any) -> Dict[str, Any]:
    if isinstance(value, dict) and "type" in value:
        return value
    if value is None:
        return {"type": "empty"}
    if isinstance(value, (bool, np.bool_)):
        return {"type": "bool", "value": bool(value)}
    if isinstance(value, datetime.datetime):
        return {"type": "string", "value": value.isoformat()}
    if isinstance(value, datetime.date):
        return {"type": "date", "value": value.isoformat()}
    if isinstance(value, datetime.time):
        return {"type": "time", "value": value.strftime("%H:%M:%S")}
    if isinstance(value, (int, float, np.number)):
        return {"type": "number", "value": float(value)}
    return {"type": "string", "value": str(value)}


@dataclass
class Rect:
    x: float
    y: float
    width: float
    height: float

    @staticmethod
    def from_value(value: Any) -> "Rect":
        if isinstance(value, Rect):
            return value
        if isinstance(value, (list, tuple)) and len(value) == 4:
            return Rect(float(value[0]), float(value[1]), float(value[2]), float(value[3]))
        if isinstance(value, dict):
            return Rect(float(value["x"]), float(value["y"]), float(value["width"]), float(value["height"]))
        raise TypeError("Invalid rect value")

    def to_dict(self) -> Dict[str, Any]:
        return {"x": self.x, "y": self.y, "width": self.width, "height": self.height}


@dataclass
class LabelBands:
    topRows: int
    bottomRows: int
    leftCols: int
    rightCols: int

    @staticmethod
    def zero() -> "LabelBands":
        return LabelBands(topRows=0, bottomRows=0, leftCols=0, rightCols=0)

    @staticmethod
    def from_labels(labels: Optional[Dict[str, Any]]) -> "LabelBands":
        if not labels:
            return LabelBands.zero()
        return LabelBands(
            topRows=int(labels.get("top", 0)),
            bottomRows=int(labels.get("bottom", 0)),
            leftCols=int(labels.get("left", 0)),
            rightCols=int(labels.get("right", 0)),
        )

    def to_dict(self) -> Dict[str, Any]:
        return {
            "topRows": self.topRows,
            "bottomRows": self.bottomRows,
            "leftCols": self.leftCols,
            "rightCols": self.rightCols,
        }


@dataclass
class GridSpec:
    bodyRows: int
    bodyCols: int
    labelBands: LabelBands = field(default_factory=LabelBands.zero)

    def to_dict(self) -> Dict[str, Any]:
        return {
            "bodyRows": self.bodyRows,
            "bodyCols": self.bodyCols,
            "labelBands": self.labelBands.to_dict(),
        }


@dataclass
class SummaryValueSpec:
    col: int
    agg: str

    def to_dict(self) -> Dict[str, Any]:
        return {"col": int(self.col), "agg": str(self.agg)}


@dataclass
class SummarySpec:
    source_table_id: str
    group_by: List[int]
    values: List[SummaryValueSpec]

    def to_dict(self) -> Dict[str, Any]:
        return {
            "sourceTableId": self.source_table_id,
            "groupBy": list(self.group_by),
            "values": [value.to_dict() for value in self.values],
        }


@dataclass
class Table:
    id: str
    name: str
    rect: Rect
    grid_spec: GridSpec
    body_column_types: List[str] = field(default_factory=list)
    cell_values: Dict[str, Any] = field(default_factory=dict)
    range_values: Dict[str, Dict[str, Any]] = field(default_factory=dict)
    formulas: Dict[str, Dict[str, Any]] = field(default_factory=dict)
    formula_order: Dict[str, int] = field(default_factory=dict)
    label_band_values: Dict[str, Dict[str, List[str]]] = field(
        default_factory=lambda: {"top": {}, "bottom": {}, "left": {}, "right": {}}
    )
    summary_spec: Optional[SummarySpec] = None
    summary_order: Optional[int] = None

    def __post_init__(self) -> None:
        self._normalize_column_types()

    def _normalize_column_types(self) -> None:
        target = int(self.grid_spec.bodyCols)
        if len(self.body_column_types) < target:
            missing = target - len(self.body_column_types)
            self.body_column_types.extend(["number"] * missing)
        elif len(self.body_column_types) > target:
            self.body_column_types = self.body_column_types[:target]

    def __getattr__(self, name: str) -> Any:
        if _FORMULA_CELL_RE.match(name):
            cell_ref = name.upper()
            return FormulaExpr(f"{self.id}.{cell_ref}")
        raise AttributeError(name)

    def __setattr__(self, name: str, value: Any) -> None:
        if name.startswith("_") or name in getattr(self, "__dataclass_fields__", {}):
            return object.__setattr__(self, name, value)
        if _FORMULA_CELL_RE.match(name):
            cell_ref = name.upper()
            if isinstance(value, FormulaExpr):
                self.set_formula(f"body[{cell_ref}]", f"={value.expr}")
                return
            self.set_cells({f"body[{cell_ref}]": value})
            return
        object.__setattr__(self, name, value)

    def __getitem__(self, key: Any) -> Any:
        row, col = _normalize_table_index(key)
        cell_ref = cell_label(row, col)
        if _active_formula_table is not None:
            if _active_formula_table is self:
                return FormulaExpr(cell_ref)
            return FormulaExpr(f"{self.id}.{cell_ref}")
        return _unwrap_value(self.cell_values.get(address("body", row, col)))

    def __setitem__(self, key: Any, value: Any) -> None:
        row, col = _normalize_table_index(key)
        self._ensure_body_size(row + 1, col + 1)
        cell_ref = cell_label(row, col)
        if isinstance(value, FormulaExpr):
            self.set_formula(f"body[{cell_ref}]", f"={value.expr}")
            return
        self.set_cells({f"body[{cell_ref}]": value})

    def set_rect(self, rect: Any) -> None:
        self.rect = Rect.from_value(rect)

    def set_position(self, x: float, y: float) -> None:
        self.rect = Rect(float(x), float(y), self.rect.width, self.rect.height)

    def resize(self, rows: Optional[int] = None, cols: Optional[int] = None) -> None:
        if rows is not None:
            self.grid_spec.bodyRows = int(rows)
        if cols is not None:
            self.grid_spec.bodyCols = int(cols)
        self._normalize_column_types()
        self._sync_rect_size()

    def set_labels(self, top: Optional[int] = None, left: Optional[int] = None,
                   bottom: Optional[int] = None, right: Optional[int] = None) -> None:
        if top is not None:
            self.grid_spec.labelBands.topRows = int(top)
        if left is not None:
            self.grid_spec.labelBands.leftCols = int(left)
        if bottom is not None:
            self.grid_spec.labelBands.bottomRows = int(bottom)
        if right is not None:
            self.grid_spec.labelBands.rightCols = int(right)
        self._sync_rect_size()

    def set_column_type(self, col: int, type: str) -> None:
        index = int(col)
        if index < 0:
            raise ValueError("Column index must be non-negative")
        if index >= self.grid_spec.bodyCols:
            self._ensure_body_size(self.grid_spec.bodyRows, index + 1)
        self._normalize_column_types()
        if index < len(self.body_column_types):
            self.body_column_types[index] = str(type)

    def set_cells(self, mapping: Dict[str, Any]) -> None:
        max_row: Optional[int] = None
        max_col: Optional[int] = None
        for key in mapping.keys():
            try:
                region, start_row, start_col, end_row, end_col = parse_range(key)
            except RangeParserError:
                continue
            if region != "body":
                continue
            row = max(start_row, end_row)
            col = max(start_col, end_col)
            max_row = row if max_row is None else max(max_row, row)
            max_col = col if max_col is None else max(max_col, col)
        if max_row is not None and max_col is not None:
            self._ensure_body_size(max_row + 1, max_col + 1)
        for key, value in mapping.items():
            self.cell_values[key] = value

    def set_range(self, range_str: str, values: List[List[Any]], dtype: Optional[str] = None) -> None:
        self.range_values[range_str] = {"values": values, "dtype": dtype}
        try:
            region, start_row, start_col, _, _ = parse_range(range_str)
        except RangeParserError:
            return
        if region == "body":
            value_rows = len(values)
            value_cols = max((len(row) for row in values), default=0)
            if value_rows > 0 and value_cols > 0:
                end_row = start_row + value_rows - 1
                end_col = start_col + value_cols - 1
                self._ensure_body_size(end_row + 1, end_col + 1)
        for row_index, row_values in enumerate(values):
            for col_index, value in enumerate(row_values):
                row = start_row + row_index
                col = start_col + col_index
                key = address(region, row, col)
                self.cell_values[key] = value

    def clear_range(self, range_str: str) -> None:
        self.range_values.pop(range_str, None)

    def set_label_band(self, band: str, index: int, values: List[str]) -> None:
        target = self.label_band_values.get(band)
        if target is None:
            raise ValueError(f"Unknown label band: {band}")
        target[str(index)] = list(values)

    def set_formula(self, target_range: str, formula: str, mode: str = "spreadsheet") -> None:
        if not formula.strip():
            self.formulas.pop(target_range, None)
            self.formula_order.pop(target_range, None)
            return
        try:
            region, start_row, start_col, end_row, end_col = parse_range(target_range)
        except RangeParserError:
            region = None
        if region == "body":
            row = max(start_row, end_row)
            col = max(start_col, end_col)
            self._ensure_body_size(row + 1, col + 1)
        self.formulas[target_range] = {"formula": formula, "mode": mode}
        self.formula_order[target_range] = _next_formula_order()

    def insert_rows(self, at: int, count: int) -> None:
        self.grid_spec.bodyRows += int(count)
        self._sync_rect_size()

    def insert_cols(self, at: int, count: int) -> None:
        self.grid_spec.bodyCols += int(count)
        self._normalize_column_types()
        self._sync_rect_size()

    def minimize(self) -> None:
        max_row: Optional[int] = None
        max_col: Optional[int] = None
        for key, value in self.cell_values.items():
            if value in (None, ""):
                continue
            try:
                region, start_row, start_col, end_row, end_col = parse_range(key)
            except RangeParserError:
                continue
            if region != "body":
                continue
            row = max(start_row, end_row)
            col = max(start_col, end_col)
            max_row = row if max_row is None else max(max_row, row)
            max_col = col if max_col is None else max(max_col, col)
        for key, payload in self.formulas.items():
            formula = payload.get("formula") if isinstance(payload, dict) else None
            if not formula or not str(formula).strip():
                continue
            try:
                region, start_row, start_col, end_row, end_col = parse_range(key)
            except RangeParserError:
                continue
            if region != "body":
                continue
            row = max(start_row, end_row)
            col = max(start_col, end_col)
            max_row = row if max_row is None else max(max_row, row)
            max_col = col if max_col is None else max(max_col, col)
        if max_row is None or max_col is None:
            return
        target_rows = max(1, max_row + 1)
        target_cols = max(1, max_col + 1)
        if target_rows == self.grid_spec.bodyRows and target_cols == self.grid_spec.bodyCols:
            return
        self.grid_spec.bodyRows = target_rows
        self.grid_spec.bodyCols = target_cols
        self._normalize_column_types()
        self._sync_rect_size()

    def _sync_rect_size(self) -> None:
        bands = self.grid_spec.labelBands
        total_cols = bands.leftCols + self.grid_spec.bodyCols + bands.rightCols
        total_rows = bands.topRows + self.grid_spec.bodyRows + bands.bottomRows
        self.rect.width = float(total_cols) * _DEFAULT_CELL_WIDTH
        self.rect.height = float(total_rows) * _DEFAULT_CELL_HEIGHT

    def _ensure_body_size(self, rows: int, cols: int) -> None:
        changed = False
        if rows > self.grid_spec.bodyRows:
            self.grid_spec.bodyRows = int(rows)
            changed = True
        if cols > self.grid_spec.bodyCols:
            self.grid_spec.bodyCols = int(cols)
            changed = True
        if changed:
            self._normalize_column_types()
        if changed:
            self._sync_rect_size()

    def _iter_formulas_by_order(self) -> List[Tuple[int, str, Dict[str, Any]]]:
        entries: List[Tuple[int, str, Dict[str, Any]]] = []
        for target_range, payload in list(self.formulas.items()):
            order = self.formula_order.get(target_range)
            if order is None:
                order = _next_formula_order()
                self.formula_order[target_range] = order
            entries.append((order, target_range, payload))
        entries.sort(key=lambda entry: entry[0])
        return entries

    def apply_formula_entry(self, project: "Project", target_range: str, payload: Dict[str, Any]) -> bool:
        changed = False
        formula = str(payload.get("formula", "")).strip()
        if not formula:
            return changed
        mode = payload.get("mode", "spreadsheet")
        try:
            region, start_row, start_col, end_row, end_col = parse_range(_normalize_ref(target_range))
        except RangeParserError:
            return changed

        if mode != "spreadsheet":
            return changed

        try:
            ast = FormulaParser(formula).parse()
        except FormulaError:
            for row in range(start_row, end_row + 1):
                for col in range(start_col, end_col + 1):
                    key = address(region, row, col)
                    if self.cell_values.get(key) != "#ERROR":
                        changed = True
                    self.cell_values[key] = "#ERROR"
            return changed

        for row in range(start_row, end_row + 1):
            for col in range(start_col, end_col + 1):
                context = FormulaContext(
                    project=project,
                    table=self,
                    anchor_row=start_row,
                    anchor_col=start_col,
                    target_row=row,
                    target_col=col,
                )
                try:
                    value = _evaluate_formula(ast, context)
                except Exception:
                    value = "#ERROR"
                key = address(region, row, col)
                if self.cell_values.get(key) != value:
                    changed = True
                self.cell_values[key] = value
        return changed

    def apply_formulas(self, project: "Project") -> bool:
        changed = False
        for _, target_range, payload in self._iter_formulas_by_order():
            if self.apply_formula_entry(project, target_range, payload):
                changed = True
        return changed

    def _encode_cell_values(self) -> Dict[str, Any]:
        return {key: _cell_value_to_json(value) for key, value in self.cell_values.items()}

    def _encode_range_values(self) -> Dict[str, Any]:
        encoded: Dict[str, Any] = {}
        for key, payload in self.range_values.items():
            values = payload.get("values", [])
            dtype = payload.get("dtype")
            encoded_values = [[_cell_value_to_json(value) for value in row] for row in values]
            encoded[key] = {"values": encoded_values, "dtype": dtype}
        return encoded

    def to_dict(self) -> Dict[str, Any]:
        payload = {
            "id": self.id,
            "name": self.name,
            "rect": self.rect.to_dict(),
            "gridSpec": self.grid_spec.to_dict(),
            "bodyColumnTypes": list(self.body_column_types),
            "cellValues": self._encode_cell_values(),
            "rangeValues": self._encode_range_values(),
            "formulas": self.formulas,
            "labelBandValues": self.label_band_values,
        }
        if self.summary_spec is not None:
            payload["summarySpec"] = self.summary_spec.to_dict()
        return payload


def _parse_col_ref(ref: str) -> Tuple[str, int]:
    trimmed = ref.strip()
    if "[" in trimmed and trimmed.endswith("]"):
        region, inner = trimmed.split("[", 1)
        region = region.strip()
        col_label = inner[:-1].strip()
    else:
        region = "body"
        col_label = trimmed
    if not col_label:
        raise RangeParserError("Invalid column reference")
    return region, column_index(col_label)


_SUMMARY_AGGREGATIONS = {"sum", "avg", "min", "max", "count"}


def _parse_summary_column(ref: Any) -> int:
    if isinstance(ref, int):
        if ref < 0:
            raise RangeParserError("Summary column index must be non-negative")
        return ref
    if isinstance(ref, str):
        region, col_index = _parse_col_ref(ref)
        if region != "body":
            raise RangeParserError("Summary columns must reference body columns")
        return col_index
    raise RangeParserError("Invalid summary column reference")


def _parse_summary_group_by(group_by: Any) -> List[int]:
    if group_by is None:
        return []
    if isinstance(group_by, (list, tuple)):
        return [_parse_summary_column(item) for item in group_by]
    return [_parse_summary_column(group_by)]


def _parse_summary_values(values: Any) -> List[SummaryValueSpec]:
    if isinstance(values, SummaryValueSpec):
        return [values]
    if isinstance(values, dict):
        values = [values]
    if not isinstance(values, (list, tuple)) or not values:
        raise ValueError("Summary values must be a non-empty list")
    parsed: List[SummaryValueSpec] = []
    for item in values:
        if isinstance(item, SummaryValueSpec):
            parsed.append(item)
            continue
        if isinstance(item, dict):
            col = item.get("col")
            agg = item.get("agg")
        elif isinstance(item, (list, tuple)) and len(item) == 2:
            col, agg = item
        else:
            raise ValueError("Summary values must be dicts or (col, agg) tuples")
        if agg is None:
            raise ValueError("Summary values require an aggregation")
        agg_name = str(agg).lower()
        if agg_name not in _SUMMARY_AGGREGATIONS:
            raise ValueError(f"Unsupported aggregation: {agg_name}")
        col_index = _parse_summary_column(col)
        parsed.append(SummaryValueSpec(col=col_index, agg=agg_name))
    return parsed


def _summary_key_component(value: Any) -> Any:
    value = _unwrap_value(value)
    if isinstance(value, dict):
        return tuple(sorted((key, _summary_key_component(val)) for key, val in value.items()))
    if isinstance(value, (list, tuple)):
        return tuple(_summary_key_component(item) for item in value)
    np_generic = getattr(np, "generic", None)
    if np_generic is not None and isinstance(value, np_generic):
        return value.item()
    return value


def _is_summary_empty(value: Any) -> bool:
    if value is None:
        return True
    if isinstance(value, str) and value == "":
        return True
    if isinstance(value, dict) and value.get("type") == "empty":
        return True
    if value == "#ERROR":
        return True
    return False


class _SummaryAccumulator:
    def __init__(self, agg: str) -> None:
        self.agg = agg
        self.count = 0
        self.total = 0.0
        self.minimum: Optional[float] = None
        self.maximum: Optional[float] = None

    def add(self, value: Any) -> None:
        if _is_summary_empty(value):
            return
        if self.agg == "count":
            self.count += 1
            return
        numeric = _summary_number(value)
        if numeric is None:
            return
        if self.agg in ("sum", "avg"):
            self.total += numeric
            self.count += 1
            return
        if self.agg == "min":
            self.minimum = numeric if self.minimum is None else min(self.minimum, numeric)
            return
        if self.agg == "max":
            self.maximum = numeric if self.maximum is None else max(self.maximum, numeric)
            return

    def finalize(self) -> Any:
        if self.agg == "count":
            return self.count
        if self.agg == "sum":
            return self.total if self.count > 0 else None
        if self.agg == "avg":
            return (self.total / self.count) if self.count > 0 else None
        if self.agg == "min":
            return self.minimum
        if self.agg == "max":
            return self.maximum
        return None


def _summary_number(value: Any) -> Optional[float]:
    value = _unwrap_value(value)
    if isinstance(value, bool):
        return float(value)
    if isinstance(value, (int, float, np.number)):
        return float(value)
    return None


def _apply_summary_table(project: "Project", summary_table: Table) -> None:
    spec = summary_table.summary_spec
    if spec is None:
        return
    source = project.table(spec.source_table_id)
    group_by = list(spec.group_by)
    value_specs = list(spec.values)
    if not value_specs:
        return
    group_order: List[Tuple[Any, ...]] = []
    aggregates: Dict[Tuple[Any, ...], List[_SummaryAccumulator]] = {}
    group_values_map: Dict[Tuple[Any, ...], List[Any]] = {}

    if source.grid_spec.bodyRows <= 0:
        body_rows = 0
    else:
        body_rows = source.grid_spec.bodyRows

    for row in range(body_rows):
        group_values = [_unwrap_value(source.cell_values.get(address("body", row, col)))
                        for col in group_by]
        if group_by and all(_is_summary_empty(value) for value in group_values):
            continue
        key = tuple(_summary_key_component(value) for value in group_values)
        if key not in aggregates:
            aggregates[key] = [_SummaryAccumulator(spec.agg) for spec in value_specs]
            group_values_map[key] = group_values
            group_order.append(key)
        for accumulator, value_spec in zip(aggregates[key], value_specs):
            value = _unwrap_value(source.cell_values.get(address("body", row, value_spec.col)))
            accumulator.add(value)

    result_rows: List[List[Any]] = []
    for key in group_order or [()]:
        group_values = group_values_map.get(key, [])
        accumulators = aggregates.get(key, [_SummaryAccumulator(spec.agg) for spec in value_specs])
        row_values = list(group_values) + [acc.finalize() for acc in accumulators]
        result_rows.append(row_values)

    summary_table.cell_values = {
        key: value for key, value in summary_table.cell_values.items()
        if not str(key).startswith("body[")
    }
    summary_table.grid_spec.bodyRows = max(1, len(result_rows))
    summary_table.grid_spec.bodyCols = max(1, len(result_rows[0]) if result_rows else len(group_by) + len(value_specs))
    summary_table._normalize_column_types()
    summary_table._sync_rect_size()

    for row_index, row_values in enumerate(result_rows):
        for col_index, value in enumerate(row_values):
            key = address("body", row_index, col_index)
            summary_table.cell_values[key] = value


def cell(table: Table, ref: str) -> Any:
    region, start_row, start_col, end_row, end_col = parse_range(_normalize_ref(ref))
    if start_row != end_row or start_col != end_col:
        raise RangeParserError("cell() requires a single cell reference")
    return _cell_value(table, region, start_row, start_col)


def col(table: Table, ref: str) -> np.ndarray:
    region, col_index = _parse_col_ref(ref)
    if region != "body":
        raise RangeParserError("col() supports body columns only")
    values = [_cell_value(table, region, row, col_index) for row in range(table.grid_spec.bodyRows)]
    return np.array(values, dtype=object)


def rng(table: Table, ref: str) -> np.ndarray:
    region, start_row, start_col, end_row, end_col = parse_range(_normalize_ref(ref))
    values: List[List[Any]] = []
    for row in range(start_row, end_row + 1):
        row_values = []
        for col_index in range(start_col, end_col + 1):
            row_values.append(_cell_value(table, region, row, col_index))
        values.append(row_values)
    return np.array(values, dtype=object)


def _coerce_range_values(values: Any, rows: int, cols: int) -> List[List[Any]]:
    if isinstance(values, np.ndarray):
        values = values.tolist()
    if not isinstance(values, list):
        return [[values for _ in range(cols)] for _ in range(rows)]
    if values and not isinstance(values[0], list):
        if rows == 1:
            return [values]
        if cols == 1:
            return [[value] for value in values]
        raise ValueError("Range values must be 2D")
    return values


def set_cell(table: Table, ref: str, value: Any) -> None:
    region, start_row, start_col, end_row, end_col = parse_range(_normalize_ref(ref))
    if start_row != end_row or start_col != end_col:
        raise RangeParserError("set_cell() requires a single cell reference")
    key = address(region, start_row, start_col)
    table.set_cells({key: value})


def set_col(table: Table, ref: str, values: Any) -> None:
    region, col_index = _parse_col_ref(ref)
    if region != "body":
        raise RangeParserError("set_col() supports body columns only")
    if isinstance(values, np.ndarray):
        values = values.tolist()
    if not isinstance(values, list):
        values = [values] * table.grid_spec.bodyRows
    for row, value in enumerate(values):
        key = address(region, row, col_index)
        table.cell_values[key] = value


def set_range(table: Table, ref: str, values: Any, dtype: Optional[str] = None) -> None:
    normalized = _normalize_ref(ref)
    region, start_row, start_col, end_row, end_col = parse_range(normalized)
    rows = end_row - start_row + 1
    cols = end_col - start_col + 1
    values_2d = _coerce_range_values(values, rows, cols)
    table.set_range(normalized, values_2d, dtype=dtype)


def clear_range(table: Table, ref: str) -> None:
    normalized = _normalize_ref(ref)
    table.clear_range(normalized)


@dataclass
class Sheet:
    id: str
    name: str
    tables: List[Table] = field(default_factory=list)

    def to_dict(self) -> Dict[str, Any]:
        return {"id": self.id, "name": self.name, "tables": [table.to_dict() for table in self.tables]}


class Project:
    def __init__(self) -> None:
        self.sheets: List[Sheet] = []

    def add_sheet(self, name: str, sheet_id: str) -> Sheet:
        sheet = Sheet(id=sheet_id, name=name)
        self.sheets.append(sheet)
        return sheet

    def rename_sheet(self, sheet_id: str, name: Optional[str] = None,
                     new_name: Optional[str] = None) -> None:
        updated = name if name is not None else new_name
        if updated is None:
            raise ValueError("rename_sheet requires a name")
        sheet = self._find_sheet(sheet_id)
        if sheet is None:
            raise KeyError(f"Unknown sheet_id: {sheet_id}")
        sheet.name = updated

    def add_table(self, sheet_id: str, table_id: str, name: str,
                  rect: Optional[Any] = None, rows: int = 10, cols: int = 6,
                  labels: Optional[Dict[str, Any]] = None,
                  x: Optional[float] = None, y: Optional[float] = None) -> Table:
        sheet = self._find_sheet(sheet_id)
        if sheet is None:
            raise KeyError(f"Unknown sheet_id: {sheet_id}")
        bands = LabelBands.from_labels(labels)
        grid_spec = GridSpec(bodyRows=int(rows), bodyCols=int(cols), labelBands=bands)
        rect_value = Rect.from_value(rect) if rect is not None else self._default_rect(
            rows=int(rows), cols=int(cols), bands=bands, x=x, y=y
        )
        table = Table(id=table_id, name=name, rect=rect_value, grid_spec=grid_spec)
        sheet.tables.append(table)
        return table

    def add_summary_table(self,
                          sheet_id: str,
                          table_id: str,
                          name: str,
                          source_table_id: str,
                          group_by: Any,
                          values: Any,
                          x: Optional[float] = None,
                          y: Optional[float] = None) -> Table:
        sheet = self._find_sheet(sheet_id)
        if sheet is None:
            raise KeyError(f"Unknown sheet_id: {sheet_id}")
        group_columns = _parse_summary_group_by(group_by)
        value_specs = _parse_summary_values(values)
        summary_spec = SummarySpec(source_table_id=source_table_id,
                                   group_by=group_columns,
                                   values=value_specs)
        cols = max(1, len(group_columns) + len(value_specs))
        grid_spec = GridSpec(bodyRows=1, bodyCols=cols, labelBands=LabelBands.zero())
        rect_value = self._default_rect(rows=grid_spec.bodyRows,
                                        cols=grid_spec.bodyCols,
                                        bands=grid_spec.labelBands,
                                        x=x,
                                        y=y)
        table = Table(id=table_id,
                      name=name,
                      rect=rect_value,
                      grid_spec=grid_spec,
                      summary_spec=summary_spec,
                      summary_order=_next_formula_order())
        sheet.tables.append(table)
        return table

    def _default_rect(self, rows: int, cols: int, bands: LabelBands,
                      x: Optional[float], y: Optional[float]) -> Rect:
        total_cols = bands.leftCols + cols + bands.rightCols
        total_rows = bands.topRows + rows + bands.bottomRows
        width = total_cols * _DEFAULT_CELL_WIDTH
        height = total_rows * _DEFAULT_CELL_HEIGHT
        if x is None or y is None:
            count = sum(len(sheet.tables) for sheet in self.sheets)
            offset = count * _DEFAULT_TABLE_OFFSET
            if x is None:
                x = _DEFAULT_TABLE_ORIGIN + offset
            if y is None:
                y = _DEFAULT_TABLE_ORIGIN + offset
        return Rect(float(x), float(y), float(width), float(height))

    def table(self, table_id: str) -> Table:
        for sheet in self.sheets:
            for table in sheet.tables:
                if table.id == table_id:
                    return table
        raise KeyError(f"Unknown table_id: {table_id}")

    def apply_formulas(self) -> None:
        entries: List[Tuple[int, str, Any]] = []
        for sheet in self.sheets:
            for table in sheet.tables:
                if table.summary_spec is not None:
                    order = table.summary_order
                    if order is None:
                        order = _next_formula_order()
                        table.summary_order = order
                    entries.append((order, "summary", table))
                for target_range, payload in list(table.formulas.items()):
                    order = table.formula_order.get(target_range)
                    if order is None:
                        order = _next_formula_order()
                        table.formula_order[target_range] = order
                    entries.append((order, "formula", (table, target_range, payload)))
        entries.sort(key=lambda entry: entry[0])
        for _, kind, payload in entries:
            if kind == "summary":
                _apply_summary_table(self, payload)
                continue
            table, target_range, formula_payload = payload
            table.apply_formula_entry(self, target_range, formula_payload)

    def to_dict(self) -> Dict[str, Any]:
        return {"sheets": [sheet.to_dict() for sheet in self.sheets]}

    def _find_sheet(self, sheet_id: str) -> Optional[Sheet]:
        for sheet in self.sheets:
            if sheet.id == sheet_id:
                return sheet
        return None


def export_numpy_script(project: Project,
                        include_labels: bool = True,
                        include_formulas: bool = False) -> str:
    if include_formulas:
        return _export_numpy_script_with_formulas(project, include_labels)
    lines: List[str] = ["import numpy as np", "", "def build_tables():", "    tables = {}"]
    for sheet in project.sheets:
        for table in sheet.tables:
            body_rows = table.grid_spec.bodyRows
            body_cols = table.grid_spec.bodyCols
            body_values = _collect_region_values(table, "body", body_rows, body_cols)
            body_values, body_dtype = _coerce_numpy_values(body_values)
            body_var = _safe_identifier(f"{table.id}_body")
            lines.extend(_emit_np_array(body_var, body_values, body_dtype))

            entry_parts = [f"'body': {body_var}"]
            if include_labels:
                labels = _collect_label_bands(table)
                if labels:
                    labels_var = _safe_identifier(f"{table.id}_labels")
                    lines.extend(_emit_literal_assignment(labels_var, labels))
                    entry_parts.append(f"'labels': {labels_var}")

            if include_formulas and table.formulas:
                formulas_var = _safe_identifier(f"{table.id}_formulas")
                lines.extend(_emit_literal_assignment(formulas_var, table.formulas))
                entry_parts.append(f"'formulas': {formulas_var}")

            entry_literal = "{%s}" % ", ".join(entry_parts)
            lines.append(f"    tables[{_encode_py_string(table.id)}] = {entry_literal}")
            lines.append("")

    lines.append("    return tables")
    lines.append("")
    lines.append("tables = build_tables()")
    return "\n".join(lines)


def _export_numpy_script_with_formulas(project: Project, include_labels: bool) -> str:
    lines: List[str] = [
        "import numpy as np",
        "from canvassheets_api import Project, address",
        "",
        "def build_project():",
        "    proj = Project()",
    ]

    for sheet in project.sheets:
        lines.append(f"    proj.add_sheet({_encode_py_string(sheet.name)}, sheet_id={_encode_py_string(sheet.id)})")
        for table in sheet.tables:
            labels = table.grid_spec.labelBands
            label_literal = (
                f"dict(top={labels.topRows}, left={labels.leftCols}, "
                f"bottom={labels.bottomRows}, right={labels.rightCols})"
            )
            x = _format_number(table.rect.x)
            y = _format_number(table.rect.y)
            lines.append(
                "    t = proj.add_table("
                f"{_encode_py_string(sheet.id)}, table_id={_encode_py_string(table.id)}, "
                f"name={_encode_py_string(table.name)}, x={x}, y={y}, "
                f"rows={table.grid_spec.bodyRows}, cols={table.grid_spec.bodyCols}, labels={label_literal})"
            )
            formula_targets = _collect_formula_targets(table)
            cell_values = _collect_cell_values(table, include_labels, formula_targets)
            if cell_values:
                lines.extend(_emit_set_cells(cell_values, "    "))

    formula_entries = _collect_formula_entries(project)
    if formula_entries:
        lines.append("")
        current_table_id: Optional[str] = None
        for table_id, target_range, payload in formula_entries:
            if current_table_id != table_id:
                lines.append(f"    t = proj.table({_encode_py_string(table_id)})")
                current_table_id = table_id
            assignment = _format_formula_assignment(target_range, payload)
            lines.append(f"    {assignment}")

    lines.append("    return proj")
    lines.append("")
    lines.extend(_emit_export_helpers(include_labels, include_formulas=True))
    lines.append("def build_tables():")
    lines.append("    proj = build_project()")
    lines.append("    proj.apply_formulas()")
    lines.append("    tables = {}")
    lines.append("    for sheet in proj.sheets:")
    lines.append("        for table in sheet.tables:")
    lines.append("            body_rows = table.grid_spec.bodyRows")
    lines.append("            body_cols = table.grid_spec.bodyCols")
    lines.append("            body_values = _collect_region_values(table, 'body', body_rows, body_cols)")
    lines.append("            body_values, body_dtype = _coerce_numpy_values(body_values)")
    lines.append("            entry = {'body': np.array(body_values, dtype=body_dtype)}")
    if include_labels:
        lines.append("            labels = _collect_label_bands(table)")
        lines.append("            if labels:")
        lines.append("                entry['labels'] = labels")
    lines.append("            entry['formulas'] = dict(table.formulas)")
    lines.append("            tables[table.id] = entry")
    lines.append("    return tables")
    lines.append("")
    lines.append("tables = build_tables()")
    return "\n".join(lines)


def _format_number(value: float) -> str:
    if value == int(value):
        return str(int(value))
    return repr(value)


def _format_python_literal(value: Any) -> str:
    value = _unwrap_value(value)
    if value is None:
        return "None"
    if isinstance(value, bool):
        return "True" if value else "False"
    if isinstance(value, (int, float, np.number)):
        return repr(value)
    if isinstance(value, str):
        return _encode_py_string(value)
    return pformat(value, width=88)


def _collect_cell_values(table: Table, include_labels: bool, formula_targets: set[str]) -> Dict[str, Any]:
    cells: Dict[str, Any] = {}
    for key, value in table.cell_values.items():
        if key in formula_targets:
            continue
        if not include_labels and not key.startswith("body["):
            continue
        cells[key] = value
    return cells


def _emit_set_cells(cells: Dict[str, Any], indent: str) -> List[str]:
    lines = [f"{indent}t.set_cells({{"]
    for key in sorted(cells.keys()):
        value_literal = _format_python_literal(cells[key])
        lines.append(f"{indent}    {_encode_py_string(key)}: {value_literal},")
    lines.append(f"{indent}}})")
    return lines


def _collect_body_assignments(table: Table, formula_targets: set[str]) -> List[str]:
    assignments: List[str] = []
    rows = table.grid_spec.bodyRows
    cols = table.grid_spec.bodyCols
    for row in range(rows):
        for col in range(cols):
            key = address("body", row, col)
            if key in formula_targets:
                continue
            if key not in table.cell_values:
                continue
            cell_label_str = f"{column_label(col).lower()}{row}"
            assignments.append(f"{cell_label_str} = {_format_python_literal(table.cell_values[key])}")
    return assignments


def _collect_label_assignments(table: Table) -> Dict[str, List[str]]:
    assignments: Dict[str, List[str]] = {}
    bands = table.grid_spec.labelBands
    regions: List[Tuple[str, int, int]] = []
    if bands.topRows > 0:
        regions.append(("top_labels", bands.topRows, table.grid_spec.bodyCols))
    if bands.bottomRows > 0:
        regions.append(("bottom_labels", bands.bottomRows, table.grid_spec.bodyCols))
    if bands.leftCols > 0:
        regions.append(("left_labels", table.grid_spec.bodyRows, bands.leftCols))
    if bands.rightCols > 0:
        regions.append(("right_labels", table.grid_spec.bodyRows, bands.rightCols))
    for region_name, rows, cols in regions:
        region_assignments: List[str] = []
        for row in range(rows):
            for col in range(cols):
                key = address(region_name, row, col)
                if key not in table.cell_values:
                    continue
                cell_label_str = f"{column_label(col).lower()}{row}"
                region_assignments.append(f"{cell_label_str} = {_format_python_literal(table.cell_values[key])}")
        if region_assignments:
            assignments[region_name] = region_assignments
    return assignments


def _collect_formula_targets(table: Table) -> set[str]:
    targets: set[str] = set()
    for target_range in table.formulas.keys():
        try:
            region, start_row, start_col, end_row, end_col = parse_range(_normalize_ref(target_range))
        except RangeParserError:
            continue
        for row in range(start_row, end_row + 1):
            for col in range(start_col, end_col + 1):
                targets.add(address(region, row, col))
    return targets


def _collect_formula_entries(project: Project) -> List[Tuple[str, str, Dict[str, Any]]]:
    entries: List[Tuple[Tuple[bool, int, str, str], str, str, Dict[str, Any]]] = []
    for sheet in project.sheets:
        for table in sheet.tables:
            for target_range, payload in table.formulas.items():
                order = table.formula_order.get(target_range)
                key = (order is None, order or 0, table.id, target_range)
                entries.append((key, table.id, target_range, payload))
    entries.sort(key=lambda entry: entry[0])
    return [(table_id, target_range, payload) for _, table_id, target_range, payload in entries]


def _format_formula_assignment(target_range: str, payload: Dict[str, Any]) -> str:
    formula_text = str(payload.get("formula", ""))
    mode = payload.get("mode", "spreadsheet")
    return (
        f"t.set_formula({_encode_py_string(target_range)}, "
        f"{_encode_py_string(formula_text)}, mode={_encode_py_string(str(mode))})"
    )


def _emit_export_helpers(include_labels: bool, include_formulas: bool) -> List[str]:
    lines: List[str] = [
        "def _normalize_export_value(value):",
        "    if isinstance(value, dict) and 'type' in value:",
        "        value_type = value.get('type')",
        "        if value_type == 'number':",
        "            return float(value.get('value', 0))",
        "        if value_type == 'string':",
        "            return str(value.get('value', ''))",
        "        if value_type == 'bool':",
        "            return bool(value.get('value', False))",
        "        if value_type == 'date':",
        "            return str(value.get('value', ''))",
        "        if value_type == 'time':",
        "            return str(value.get('value', ''))",
        "        return None",
        "    np_generic = getattr(np, 'generic', None)",
        "    if np_generic is not None and isinstance(value, np_generic):",
        "        return value.item()",
        "    return value",
        "",
        "def _collect_region_values(table, region, rows, cols):",
        "    values = []",
        "    for row in range(rows):",
        "        row_values = []",
        "        for col in range(cols):",
        "            key = address(region, row, col)",
        "            row_values.append(_normalize_export_value(table.cell_values.get(key)))",
        "        values.append(row_values)",
        "    return values",
        "",
        "def _coerce_numpy_values(values):",
        "    flat = []",
        "    for row in values:",
        "        flat.extend(row)",
        "",
        "    def is_number(item):",
        "        return isinstance(item, (int, float, np.number)) and not isinstance(item, bool)",
        "",
        "    if all((item is None) or is_number(item) for item in flat):",
        "        coerced = []",
        "        for row in values:",
        "            coerced.append([None if item is None else float(item) for item in row])",
        "        return coerced, 'float'",
        "    return values, 'object'",
        "",
        "def _collect_label_bands(table):",
        "    labels = {}",
        "    bands = table.grid_spec.labelBands",
        "    if bands.topRows > 0:",
        "        labels['top'] = _collect_region_values(table, 'top_labels', bands.topRows, table.grid_spec.bodyCols)",
        "    if bands.bottomRows > 0:",
        "        labels['bottom'] = _collect_region_values(table, 'bottom_labels', bands.bottomRows, table.grid_spec.bodyCols)",
        "    if bands.leftCols > 0:",
        "        labels['left'] = _collect_region_values(table, 'left_labels', table.grid_spec.bodyRows, bands.leftCols)",
        "    if bands.rightCols > 0:",
        "        labels['right'] = _collect_region_values(table, 'right_labels', table.grid_spec.bodyRows, bands.rightCols)",
        "    return labels",
        "",
    ]
    return lines


def _safe_identifier(name: str) -> str:
    cleaned = re.sub(r"[^A-Za-z0-9_]", "_", name)
    if not cleaned:
        return "table"
    if cleaned[0].isdigit():
        return f"t_{cleaned}"
    return cleaned


def _encode_py_string(value: str) -> str:
    escaped = value.replace("\\", "\\\\").replace("'", "\\'")
    return f"'{escaped}'"


def _collect_region_values(table: Table, region: str, rows: int, cols: int) -> List[List[Any]]:
    values: List[List[Any]] = []
    for row in range(rows):
        row_values: List[Any] = []
        for col in range(cols):
            key = address(region, row, col)
            row_values.append(_normalize_export_value(table.cell_values.get(key)))
        values.append(row_values)
    return values


def _normalize_export_value(value: Any) -> Any:
    value = _unwrap_value(value)
    if isinstance(value, datetime.datetime):
        return value.isoformat()
    if isinstance(value, datetime.date):
        return value.isoformat()
    if isinstance(value, datetime.time):
        return value.strftime("%H:%M:%S")
    np_generic = getattr(np, "generic", None)
    if np_generic is not None and isinstance(value, np_generic):
        return value.item()
    return value


def _coerce_numpy_values(values: List[List[Any]]) -> Tuple[List[List[Any]], str]:
    flat: List[Any] = []
    for row in values:
        flat.extend(row)

    def is_number(item: Any) -> bool:
        return isinstance(item, (int, float, np.number)) and not isinstance(item, bool)

    if all((item is None) or is_number(item) for item in flat):
        coerced: List[List[Any]] = []
        for row in values:
            coerced.append([None if item is None else float(item) for item in row])
        return coerced, "float"
    return values, "object"


def _collect_label_bands(table: Table) -> Dict[str, List[List[Any]]]:
    labels: Dict[str, List[List[Any]]] = {}
    bands = table.grid_spec.labelBands
    if bands.topRows > 0:
        labels["top"] = _collect_region_values(table, "top_labels", bands.topRows, table.grid_spec.bodyCols)
    if bands.bottomRows > 0:
        labels["bottom"] = _collect_region_values(table, "bottom_labels", bands.bottomRows, table.grid_spec.bodyCols)
    if bands.leftCols > 0:
        labels["left"] = _collect_region_values(table, "left_labels", table.grid_spec.bodyRows, bands.leftCols)
    if bands.rightCols > 0:
        labels["right"] = _collect_region_values(table, "right_labels", table.grid_spec.bodyRows, bands.rightCols)
    return labels


def _emit_np_array(var_name: str, values: List[List[Any]], dtype: str) -> List[str]:
    literal = pformat(values, width=88)
    if "\n" not in literal:
        return [f"    {var_name} = np.array({literal}, dtype={dtype})"]
    lines = [f"    {var_name} = np.array("]
    for line in literal.splitlines():
        lines.append(f"        {line}")
    lines.append(f"    , dtype={dtype})")
    return lines


def _emit_literal_assignment(var_name: str, value: Any) -> List[str]:
    literal = pformat(value, width=88)
    lines: List[str] = []
    parts = literal.splitlines()
    if len(parts) == 1:
        lines.append(f"    {var_name} = {parts[0]}")
        return lines
    lines.append(f"    {var_name} = {parts[0]}")
    for line in parts[1:]:
        lines.append(f"    {line}")
    return lines


__all__ = [
    "Project",
    "Table",
    "Rect",
    "GridSpec",
    "LabelBands",
    "FormulaError",
    "RangeParserError",
    "address",
    "export_numpy_script",
    "formula_mode",
    "table_context",
    "label_context",
    "formula",
    "date_value",
    "time_value",
    "c_range",
    "c_sum",
    "c_avg",
    "c_min",
    "c_max",
    "c_count",
    "c_counta",
    "c_if",
    "c_and",
    "c_or",
    "c_not",
    "c_pmt",
    "c_abs",
    "c_round",
    "c_floor",
    "c_ceil",
    "c_sqrt",
    "c_pow",
    "c_log",
    "c_log10",
    "c_exp",
    "c_sin",
    "c_cos",
    "c_tan",
    "cell",
    "col",
    "rng",
    "set_cell",
    "set_col",
    "set_range",
    "clear_range",
    "cs_sum",
    "cs_avg",
    "cs_min",
    "cs_max",
    "cs_count",
    "cs_counta",
    "cs_pmt",
    "cs_abs",
    "cs_round",
    "cs_floor",
    "cs_ceil",
    "cs_sqrt",
    "cs_pow",
    "cs_log",
    "cs_log10",
    "cs_exp",
    "cs_sin",
    "cs_cos",
    "cs_tan",
    "cs_if",
    "cs_and",
    "cs_or",
    "cs_not",
    "parse_range",
    "column_label",
    "column_index",
]
