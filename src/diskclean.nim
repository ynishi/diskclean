## diskclean — Declarative disk cleanup for development projects
##
## Tool-first, rm-fallback. Minimal. Fast.

import diskclean/[types, rules, walker, cleaner, reporter, cli]
export types, rules, walker, cleaner, reporter, cli

when isMainModule:
  run()
