import os
import re


def norm(p):
    return os.path.normpath(p).replace(os.sep, "/")


ROOT = "lib"


def resolve(imp, curdir):
    if imp.startswith("package:ssa_app/"):
        return norm(os.path.join(ROOT, imp[len("package:ssa_app/"):]))
    if imp.startswith("package:") or imp.startswith("dart:"):
        return None
    # Dart allows relative imports without a leading "./" (e.g. 'theme/app_theme.dart').
    return norm(os.path.join(curdir, imp))


seen = set()
stack = ["lib/main.dart"]
while stack:
    f = norm(stack.pop())
    if f in seen or not os.path.exists(f):
        continue
    seen.add(f)
    d = os.path.dirname(f)
    try:
        src = open(f, encoding="utf-8").read()
    except OSError:
        continue
    for m in re.findall(r"""import\s+['"]([^'"]+)['"]""", src):
        t = resolve(m, d)
        if t:
            stack.append(t)

lib_files = []
for dp, _, fns in os.walk(ROOT):
    for fn in fns:
        if fn.endswith(".dart"):
            lib_files.append(norm(os.path.join(dp, fn)))

dead = sorted(set(lib_files) - seen)
print("LIVE:", len(seen), " DEAD:", len(dead))
print()
print("=== DEAD (unreachable from main.dart) ===")
for f in dead:
    print("  ", f)
