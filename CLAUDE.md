# Team knowledge

We keep shared knowledge (product docs, architecture, tickets, runbooks, feedback, etc.) in Aveline, not in this repo. Interact with it via the `aveline` CLI; run `aveline --help` to see every operation.

Start sessions with `aveline get-orientation` to learn how this workspace organizes its knowledge before reading or writing docs. Run `aveline contract` before your first doc write: it shows every block type and edit op with a valid example.

New docs are born private and new views land in your personal bucket. Publishing is deliberate: pass `--visibility workspace` on create-doc (or `set-doc-visibility` after) for anything the team should see, and `--bucket team` on create-view for shared views.
