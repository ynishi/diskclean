## diskclean/types — Core data types
##
## All types are plain value objects with no heap-allocated internal state.

import std/options

type
  CleanMethod* = enum
    ToolClean       ## Native tool succeeded (e.g. ``cargo clean``)
    FallbackRm      ## Direct directory removal (requires ``-d:experimentalRm``)
    Skipped         ## Nothing to clean, or rm fallback unavailable

  Rule* = object
    name*: string
    icon*: string
    markers*: seq[string]    ## Files that identify the project type (any match)
    tool*: string            ## Native clean command (empty = no tool)
    toolBin*: string         ## Binary name for findExe check
    targets*: seq[string]    ## Directory names to remove

  Project* = object
    root*: string            ## Project root (where marker was found)
    rule*: Rule              ## Matched rule
    targets*: seq[string]    ## Full paths of found target dirs
    size*: Option[int64]     ## Total size in bytes (none if not calculated)

  CleanResult* = object
    project*: Project
    usedMethod*: CleanMethod
    freed*: int64
    error*: string           ## Empty on success
