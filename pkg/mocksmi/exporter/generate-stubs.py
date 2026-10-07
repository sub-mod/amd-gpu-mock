#!/usr/bin/env python3
"""Generate unsupported GPU functions from a C-preprocessed AMD SMI header."""
import pathlib
import re
import sys
root = pathlib.Path(__file__).resolve().parent
implemented = set(re.findall(r"amdsmi_status_t\s+(amdsmi_\w+)\s*\(", (root / "mock.c").read_text()))
prototypes = re.findall(r"amdsmi_status_t\s+(amdsmi_\w+)\s*\(([^;]*?)\)\s*;", pathlib.Path(sys.argv[1]).read_text(), re.S)
(root / "unsupported.c").write_text('// Generated from the pinned GPU-only AMD SMI header.\n#include "amdsmi.h"\n' + '\n'.join(f'amdsmi_status_t {name}({args}) {{ return AMDSMI_STATUS_NOT_SUPPORTED; }}' for name, args in prototypes if name not in implemented) + '\n')
