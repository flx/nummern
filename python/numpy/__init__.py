from __future__ import annotations

import importlib
import math
import sys
from pathlib import Path
from typing import Any, Callable, Iterable, List, Optional, Sequence


def _try_load_real_numpy() -> bool:
    if getattr(sys, "_nummern_numpy_loading", False):
        return False

    module_root = Path(__file__).resolve().parents[1]
    current_module = sys.modules.get(__name__)
    original_sys_path = list(sys.path)

    def is_module_root(entry: str) -> bool:
        try:
            return Path(entry).resolve() == module_root
        except Exception:
            return False

    try:
        sys._nummern_numpy_loading = True  # type: ignore[attr-defined]
        sys.path = [entry for entry in sys.path if not is_module_root(entry)]
        sys.modules.pop(__name__, None)
        module = importlib.import_module("numpy")
        sys.modules[__name__] = module
        globals().update(module.__dict__)
        return True
    except Exception:
        if current_module is not None:
            sys.modules[__name__] = current_module
        return False
    finally:
        sys.path = original_sys_path
        if hasattr(sys, "_nummern_numpy_loading"):
            delattr(sys, "_nummern_numpy_loading")


if not _try_load_real_numpy():
    nan = float("nan")

    class ndarray:
        def __init__(self, data: Any):
            self._data = data

        @property
        def flat(self) -> Iterable[Any]:
            return _flatten(self._data)

        @property
        def size(self) -> int:
            return sum(1 for _ in _flatten(self._data))

        def tolist(self) -> Any:
            return self._data

        def __iter__(self):
            if isinstance(self._data, list):
                return iter(self._data)
            return iter([self._data])

    class number:
        pass

    class bool_:
        pass

    def array(values: Any, dtype: Any = None) -> ndarray:
        if isinstance(values, ndarray):
            return values
        if isinstance(values, (list, tuple)):
            data = [_copy_nested(value) for value in values]
            return ndarray(data)
        return ndarray(values)

    def vectorize(func: Callable[..., Any], otypes: Optional[Sequence[Any]] = None) -> Callable[..., ndarray]:
        def wrapper(values: Any) -> ndarray:
            data = values._data if isinstance(values, ndarray) else values
            return ndarray(_map_nested(data, func))
        return wrapper

    def where(condition: Any, x: Any, y: Any) -> ndarray:
        cond_data = condition._data if isinstance(condition, ndarray) else condition
        x_data = x._data if isinstance(x, ndarray) else x
        y_data = y._data if isinstance(y, ndarray) else y
        return ndarray(_select_nested(cond_data, x_data, y_data))

    def nansum(values: Any, axis: Optional[int] = None) -> Any:
        data = values._data if isinstance(values, ndarray) else values
        if axis is None:
            return sum(_iter_numbers(data))
        if axis == 0:
            rows = data or []
            columns = list(zip(*rows)) if rows else []
            return [nansum(list(column)) for column in columns]
        if axis == 1:
            return [nansum(row) for row in data]
        raise ValueError("Unsupported axis")

    def nanmean(values: Any, axis: Optional[int] = None) -> Any:
        data = values._data if isinstance(values, ndarray) else values
        if axis is None:
            numbers = list(_iter_numbers(data))
            if not numbers:
                return nan
            return sum(numbers) / len(numbers)
        if axis == 0:
            rows = data or []
            columns = list(zip(*rows)) if rows else []
            return [nanmean(list(column)) for column in columns]
        if axis == 1:
            return [nanmean(row) for row in data]
        raise ValueError("Unsupported axis")

    def _iter_numbers(values: Any) -> Iterable[float]:
        for item in _flatten(values):
            if item is None:
                continue
            if isinstance(item, float) and math.isnan(item):
                continue
            if isinstance(item, bool):
                yield float(int(item))
            elif isinstance(item, (int, float)):
                yield float(item)

    def _flatten(values: Any) -> Iterable[Any]:
        if isinstance(values, ndarray):
            values = values._data
        if isinstance(values, list):
            for item in values:
                yield from _flatten(item)
        else:
            yield values

    def _copy_nested(values: Any) -> Any:
        if isinstance(values, list):
            return [_copy_nested(value) for value in values]
        if isinstance(values, tuple):
            return [_copy_nested(value) for value in values]
        return values

    def _map_nested(values: Any, func: Callable[[Any], Any]) -> Any:
        if isinstance(values, list):
            return [_map_nested(value, func) for value in values]
        return func(values)

    def _select_nested(condition: Any, x: Any, y: Any) -> Any:
        if isinstance(condition, list):
            result = []
            for index, item in enumerate(condition):
                x_item = x[index] if isinstance(x, list) else x
                y_item = y[index] if isinstance(y, list) else y
                result.append(_select_nested(item, x_item, y_item))
            return result
        return x if condition else y

    __all__ = [
        "array",
        "bool_",
        "nan",
        "nanmean",
        "nansum",
        "ndarray",
        "number",
        "vectorize",
        "where",
    ]
