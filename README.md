# dagit.nvim

Git history in a horizontal split. Each row is a graph, an abbreviated hash, `HEAD (branch)`, and the subject. When another branch leaves that same merge, the merged parent stays on the node and the other branch joins the line above it. Tags, the author, and the date with its time stay on the right. The highlighted row has `>` on the left and the cursor-line background. Opening the history places that highlight on the checked-out commit. The commit HEAD points at is drawn in bold. A commit that is not on any remote uses a different hash color. A branch that is not local is drawn in a muted lane color, and the text on those commits is muted the same way. `<C-o>` copies the full hash. The caret is hidden in that window.

## Requirements

- Neovim 0.10 or newer
- Git

## Install

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{ "skarchr/dagit.nvim" }
```

The plugin works without `setup()`. Calling `setup()` only stores options.

```lua
{
    "skarchr/dagit.nvim",
    config = function()
        require("dagit").setup({
            height = 18,
            max_count = 300,
        })
    end,
}
```

The same table can live in `vim.g.dagit`, which does not require the plugin to be installed:

```lua
vim.g.dagit = {
    height = 18,
    date_format = "relative",
}
```

`setup()` wins when both are set. A value returned from a function is accepted in either place.

## Use

```vim
:Dagit
:Dagit log
:Dagit log main --first-parent
:Dagit refresh
:Dagit copy
:Dagit close
```

`:Dagit` and `:Dagit log` open the history for the repository that contains the current file. Extra arguments are passed to `git log` and replace `log_args` for that call.

In the history window:

| Key | Action |
| --- | --- |
| `<C-o>` | Copy the full hash of the cursor row |
| `r` | Reload the history |
| `q` | Close the window |
| `<CR>` | Show or hide the commit description and files |
| `z` | Show or hide the commit description and files |
| `Z` | Hide every expanded commit |
| `<Tab>` | Next commit filter: all, local, remote |
| `<S-Tab>` | Previous commit filter |

`<C-o>` is buffer-local, so the jump-list mapping is unchanged in other windows. Set a key to `false` to skip that default. `<Plug>` maps stay available:

```lua
vim.keymap.set("n", "<leader>gl", "<Plug>(DagitOpen)")
vim.keymap.set("n", "<leader>gy", "<Plug>(DagitCopyHash)")
```

`<Plug>(DagitRefresh)`, `<Plug>(DagitClose)`, `<Plug>(DagitExpand)`, `<Plug>(DagitShow)`, `<Plug>(DagitCollapse)`, `<Plug>(DagitFilterNext)`, and `<Plug>(DagitFilterPrev)` are mapped the same way.

The top of the window keeps one line, `[all]  local  remote`. Brackets mark the active filter, and the line stays put while the log scrolls. `all` is the loaded log. `local` shows commits reachable from a local branch or HEAD. `remote` shows commits reachable from a remote-tracking branch. `filter` chooses which of those a new window starts on. An open window keeps the filter it already has. `<Tab>` is local to the history window. In a terminal it is the same key as `<C-i>`.

`<CR>` draws a block under the highlighted commit, and hides it again. The text is indented. More than five changed files start the block with a count, such as `3 added, 1 modified, 2 deleted`. The commit description comes next, when the commit has one. Each changed file is a line after that: `M`, `A`, `D`, or `R`, then the path. A rename is `R old -> new`. The graph lanes continue through the block, and `j` and `k` move through the lines. `z` toggles the block as well. `Z` hides every open block. On a commit that is not local, that block uses the same muted colors as the row.

The commit under the cursor is available to other plugins:

```lua
local commit = require("dagit").commit()
-- commit.hash, commit.parents, commit.subject, commit.refs, commit.author
```

`on_select` runs on `<CR>` when `keymaps.expand` is not `<CR>`. It receives that same commit table:

```lua
require("dagit").setup({
    on_select = function(commit)
        vim.cmd("DiffviewOpen " .. commit.hash .. "^!")
    end,
})
```

## Options

```lua
{
    height = 16,                 -- rows. 0 < height < 1 is a fraction of the screen
    split = "bottom",            -- "bottom" or "top"
    filter = "all",              -- "all", "local", or "remote". Used when a window opens.
    max_count = 256,
    log_args = { "--all" },      -- passed to `git log`. Stashes are left out.
    date_format = "%d %b %H:%M", -- os.date format, or "relative". A date-only format still gets HH:MM. Another year is shown; the current year is left off.
    author_max_width = 22,
    ref_max_width = 30,          -- width of "HEAD (branch)" and of the tag
    multi_tag_label = "multi tag", -- several tags collapse to this label
    dim_merges = true,           -- dim commits with more than one parent
    git_cmd = "git",
    notify = true,
    icons = {
        enabled = true,          -- set false when you do not use a Nerd Font
        head = "󰘬",
        branch = "󰘬",
        remote = "",
        tag = "󰓹",
    },
    symbols = {
        -- Ghostty, Kitty, and Contour draw these to the cell edge.
        -- Other terminals fall back to Nerd Font circles unless you set this.
        commit = "",
        commit_down = "",       -- line continues downward
        commit_up = "",         -- line continues upward
        commit_through = "",    -- line passes through the circle
        vertical = "",
        horizontal = "",
        branch_start = "",
        merge_right = "",
        merge_left = "",
        diagonal_right = "╲",
        diagonal_left = "╱",
    },
    keymaps = {
        copy_hash = "<C-o>",
        close = "q",
        refresh = "r",
        expand = "<CR>",     -- toggle the description and files
        show = "z",           -- toggle the description and files
        collapse = "Z",       -- hide every expanded commit
        filter_next = "<Tab>",
        filter_prev = "<S-Tab>",
    },
    on_select = nil,
}
```

History is loaded with `--date-order`, so a parent is not drawn before its children when two commits share a timestamp. Pass `--topo-order` or `--author-date-order` in `log_args` to pick a different order. `--all` skips `refs/stash`. Add `refs/stash` to `log_args` to show stashes.

## Highlight groups

Every group links to a colorscheme group until you define it yourself.

| Group | Linked to | Used for |
| --- | --- | --- |
| `DagitNormal` | `SnacksPickerList`, then `SnacksPicker`, then `NormalFloat` | history window background, same as the Snacks explorer |
| `DagitHash` | `Label` | abbreviated commit hash |
| `DagitHashLocal` | `DiagnosticWarn` | hash of a commit that is not on any remote |
| `DagitUpstreamGone` | `DiagnosticError` | `(upstream gone)` after a local branch whose upstream ref is missing |
| `DagitDecor` | `Delimiter` | parentheses and commas around refs |
| `DagitHeadMark` | `Special` filled behind the history background | the word `HEAD` before `(branch)`, with a space on each side |
| `DagitHead` | bold, colorscheme foreground | `>` on the highlighted row, the HEAD subject, and the active filter name |
| `DagitFilter` | `Comment` | inactive names on the filter line |
| `DagitCursor` | `blend=100` | hidden caret in the history window |
| `DagitGraph1` … `DagitGraph8` | theme syntax groups | graph lanes, and the branch, remote, and HEAD names on that lane |
| `DagitGraph1Muted` … `DagitGraph8Muted` | lane color, faded toward the background | branches that are not local |
| `DagitTextMuted` | foreground, faded toward the background | subject on a commit that is not local. Hash, decoration, tag, author, and date use the `Muted` copy of their usual group |
| `DagitMerge` | `Comment` | merge subjects |
| `DagitAuthor` | `Comment` | author |
| `DagitDate` | `NonText` | date and time |
| `DagitRefTag` | `Constant` | tags |
| `DagitBody` | `Comment` | commit description under an expanded row |
| `DagitFileAdded` | `DiagnosticOk` | added file (`A`), green |
| `DagitFileModified` | `DiagnosticWarn` | modified file (`M`), yellow |
| `DagitFileDeleted` | `DiagnosticError` | deleted file (`D`), red |
| `DagitFileRenamed` | `DiagnosticHint` | renamed or copied file (`R`, `C`), cyan |
| `DagitBodyMuted`, `DagitFileAddedMuted`, `DagitFileModifiedMuted`, `DagitFileDeletedMuted`, `DagitFileRenamedMuted` | the group above, faded toward the background | description and file lines under a commit that is not local |

```lua
vim.api.nvim_set_hl(0, "DagitRefHead", { link = "DiagnosticOk" })
```

## Health

```vim
:checkhealth dagit
```

## Test

```sh
make test
```

That runs the spec files inside Neovim. With [busted](https://lunarmodules.github.io/busted/) installed, `busted .` runs the same files.
