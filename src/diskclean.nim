## diskclean — Declarative disk cleanup for development projects
##
## Tool-first, rm-fallback. Minimal. Fast.

{.push raises: [].}

import diskclean/[types, rules, walker, cleaner, reporter, worktree]
export types, rules, walker, cleaner, reporter, worktree

when isMainModule:
  import diskclean/cli
  run()
