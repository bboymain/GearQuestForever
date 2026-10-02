import os
import sys

from lupa import LuaRuntime

ROOT = os.path.dirname(os.path.abspath(__file__))
TEST = os.path.join(ROOT, "test_runtime.lua")

lua = LuaRuntime(unpack_returned_tuples=True)
try:
    lua.execute(open(TEST, encoding="utf-8").read())
except Exception as exc:
    print("FAIL: %s" % exc)
    sys.exit(1)
print("PASS")
