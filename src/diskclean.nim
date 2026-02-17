## diskclean — Declarative disk cleanup for development projects
##
## Tool-first, rm-fallback. Minimal. Fast.

{.push raises: [].}

import diskclean/[types, rules, walker, cleaner, reporter]
export types, rules, walker, cleaner, reporter

when isMainModule:
  import diskclean/cli
  run()
