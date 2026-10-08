# dagit.nvim

Git history in a horizontal split. Each row is a graph, an abbreviated hash, `(HEAD -> branch)`, and the subject. Tags, the author, and the date with its time stay on the right. The highlighted row has `>` on the left and the cursor-line background. The commit HEAD points at is drawn in bold. `<C-o>` copies the full hash. The caret is hidden in that window.

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
| `<CR>` | Call `on_select`, when you set it |

`<C-o>` is buffer-local, so the jump-list mapping is unchanged in other windows. Set a key to `false` to skip that default. `<Plug>` maps stay available:

```lua
vim.keymap.set("n", "<leader>gl", "<Plug>(DagitOpen)")
vim.keymap.set("n", "<leader>gy", "<Plug>(DagitCopyHash)")
```

`<Plug>(DagitRefresh)` and `<Plug>(DagitClose)` are mapped the same way.

The commit under the cursor is available to other plugins:

```lua
local commit = require("dagit").commit()
-- commit.hash, commit.parents, commit.subject, commit.refs, commit.author
```

`on_select` is the hook for a later drilldown. It receives that same commit table:

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
    max_count = 256,
    log_args = { "--all" },      -- passed to `git log`
    date_format = "%d %b %H:%M", -- os.date format, or "relative". A date-only format still gets HH:MM. Another year is shown; the current year is left off.
    author_max_width = 22,
    ref_max_width = 28,          -- width of "(HEAD -> branch)" and of the tag
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
    },
    keymaps = {
        copy_hash = "<C-o>",
        close = "q",
        refresh = "r",
    },
    on_select = nil,
}
```

History is loaded with `--date-order`, so a parent is not drawn before its children when two commits share a timestamp. Pass `--topo-order` or `--author-date-order` in `log_args` to pick a different order.

## Highlight groups

Every group links to a colorscheme group until you define it yourself.

| Group | Linked to | Used for |
| --- | --- | --- |
| `DagitNormal` | `SnacksPickerList`, then `SnacksPicker`, then `NormalFloat` | history window background, same as the Snacks explorer |
| `DagitHash` | `Label` | abbreviated commit hash |
| `DagitDecor` | `Delimiter` | parentheses and commas around refs |
| `DagitHead` | bold, colorscheme foreground | `>` on the highlighted row, `HEAD ->`, and the HEAD subject |
| `DagitCursor` | `blend=100` | hidden caret in the history window |
| `DagitGraph1` … `DagitGraph8` | theme syntax groups | graph lanes, and the branch, remote, and HEAD names on that lane |
| `DagitMerge` | `Comment` | merge subjects |
| `DagitAuthor` | `Comment` | author |
| `DagitDate` | `NonText` | date and time |
| `DagitRefTag` | `Constant` | tags |

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
