## diskclean/types — Core data types
##
## All types are plain value objects with no heap-allocated internal state.

{.push raises: [].}

import std/options

type
  CleanMethod* = enum
    ToolClean       ## Native tool succeeded (e.g. ``cargo clean``)
    FallbackRm      ## Direct directory removal (requires ``-d:experimentalRm``)

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

  CleanResultKind* = enum
    crkSuccess
    crkSkipped
    crkError

  CleanResult* = object
    project*: Project
    case kind*: CleanResultKind
    of crkSuccess:
      cleanMethod*: CleanMethod
      freed*: int64
    of crkSkipped:
      skipReason*: string
    of crkError:
      error*: string
