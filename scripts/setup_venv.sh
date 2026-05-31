#!/bin/sh
set -eu

PYTHON_BIN=${PYTHON_BIN:-/opt/homebrew/opt/python@3.14/bin/python3.14}
VENV_DIR=${VENV_DIR:-.venv}

"$PYTHON_BIN" -m venv "$VENV_DIR"
"$VENV_DIR/bin/pip" install --upgrade pip
"$VENV_DIR/bin/pip" install -r requirements.txt
# Editable install of the canvassheets engine so `python script.py` works anywhere.
"$VENV_DIR/bin/pip" install -e ./python

echo "Venv ready at $VENV_DIR"
"$VENV_DIR/bin/python" -m pytest python -q
