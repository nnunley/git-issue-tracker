# git-issue-board

One self-contained HTML page over a repository's git-issue notes. git-issue
has no web view; this is a read-only one for a laptop or a phone.

```sh
git fetch origin 'refs/notes/issue-*:refs/notes/issue-*'
contrib/board/git-issue-board.py            # writes git-issue-board.html in the cwd
contrib/board/git-issue-board.py --repo ~/src/other -o /tmp/board/index.html
```

Python 3.8 or later, standard library only; it shells out to `git issue
--porcelain list`, `export` and `show`, so `git-issue` must be on `PATH`.

What the page shows:

- Issues grouped by status in working order: in progress, review, blocked,
  open, deferred, closed. Priority first within a group.
- A segmented filter (Active hides closed), an assignee dropdown and a search
  over id, title, body and comments. The state lives in the URL hash, so a
  filtered view is a link.
- A dependency graph, as inline SVG, for the issues that take part in an edge:
  solid for `blocks` and `parent_of`, dashed for `relates_to`. Boxes link to
  their cards.
- Each card expands to the description, comments, author, dates and the
  `git issue show` line for it.
- Light and dark follow the OS; the layout holds at 390 px.

The page is a snapshot. Its footer says when it was generated and from which
commit; fetch and re-run to refresh. To read it on a phone, serve the output
directory with any static server (`python3 -m http.server 8080` in that
directory) and open it over the LAN or a tailnet.

Known edge: the renderer runs one `export` per issue because `export` with no
ids prints nothing in 1.0.0-rc6 (#3); about 0.1 s per issue.
