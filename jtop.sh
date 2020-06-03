#!/usr/bin/env bash

readonly __dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PATH=$PATH:"${__dir}/scripts" python3 -c 'from jtop.__main__ import man; main()'
