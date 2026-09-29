# timing_interface

Block-level timing databases, the inter-block connection database, and a dashboard for browsing timing paths across blocks.

## Layout

| Path | Contents |
|---|---|
| `sqlite_block_database/` | Block-level SQLite timing databases |
| `interface_binder/` | SQLite database defining connections between blocks |
| `dashboard/` | Django GUI for displaying timing paths |
| `tcl_scripts/` | TCL scripts |
| `release.sh` | Interactive tag-and-release script |

## Releasing

Run `./release.sh` from the branch you want to release. It:

1. Shows the previous tag, the commits since it, and any uncommitted changes.
2. Asks for the new tag (default is the next patch version, e.g. `v0.1.0` to `v0.1.1`) and a release message.
3. After you confirm, commits all pending changes with that message, creates an annotated tag, and pushes the branch and tag to `origin` together.

Tags follow semantic versioning, `vMAJOR.MINOR.PATCH` (optionally `-rc.1`): bump MAJOR for an incompatible database schema or interface change, MINOR for a new feature, block or dashboard view, and PATCH for bug fixes.
