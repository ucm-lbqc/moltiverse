#!/usr/bin/env bash

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

cd $SCRIPT_DIR
../bin/moltiverse -l molecules.smi -o TEST_MOLECULE -p test -n 10
