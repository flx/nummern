import pytest

from canvassheets import address
from canvassheets.address import (
    CellRef,
    ColRangeRef,
    ColRef,
    NameRef,
    RangeRef,
    classify,
)


@pytest.mark.parametrize("label,index", [("A", 0), ("B", 1), ("Z", 25), ("AA", 26), ("AB", 27)])
def test_column_index_roundtrip(label, index):
    assert address.column_index(label) == index
    assert address.column_label(index) == label


def test_parse_cell_is_zero_based():
    assert address.parse_cell("A0") == (0, 0)
    assert address.parse_cell("B3") == (3, 1)


def test_parse_range_normalizes_order():
    assert address.parse_range("C9:A0") == (0, 0, 9, 2)
    assert address.parse_range("A0") == (0, 0, 0, 0)


def test_classify_kinds():
    assert classify("A0") == CellRef(0, 0)
    assert classify("B") == ColRef(1)
    assert classify("A0:C9") == RangeRef(0, 0, 9, 2)
    assert classify("A:C") == ColRangeRef(0, 2)
    assert classify("Revenue") == NameRef("Revenue")


def test_invalid_reference():
    with pytest.raises(address.AddressError):
        address.parse_cell("A")
