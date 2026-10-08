--- Type definitions for dagit.
---
--- This module is annotations only. It exists so editors and `:checkhealth`
--- share one description of the public data.

---@class dagit.Ref
--- One branch, tag, or HEAD decoration on a commit.
---@field name string Display name, such as `main` or `origin/main`.
---@field kind "head" | "branch" | "remote" | "tag"

---@class dagit.Commit
--- One row in the history log.
---@field hash string Full commit hash.
---@field parents string[] Parent hashes. The first parent is the first parent Git records.
---@field author string Author name.
---@field timestamp string Author time in ISO-8601.
---@field subject string First line of the commit message.
---@field refs dagit.Ref[]

---@class dagit.Icons
--- Glyphs drawn in front of branch and tag names.
---
--- The defaults are Nerd Font codepoints. Set `enabled` to `false` for plain text.
---@field enabled boolean
---@field head string
---@field branch string
---@field remote string
---@field tag string

---@class dagit.Symbols
--- Characters for the commit graph.
---
--- `commit_down`, `commit_up`, and `commit_through` are circles with a
--- vertical stroke so a straight lane stays connected. All four commit
--- glyphs must be the same display width. The defaults are the branch-drawing
--- glyphs Ghostty, Kitty, and Contour paint to the cell edge. Other terminals
--- receive Nerd Font circles unless `symbols` is set.
---@field commit string Lone commit. No line enters or leaves its cell.
---@field commit_down string Line continues to the parent below.
---@field commit_up string Line continues from the child above.
---@field commit_through string Line continues through the commit.
---@field vertical string
---@field horizontal string
---@field branch_start string
---@field merge_right string
---@field merge_left string

---@class dagit.Keymaps
--- Buffer-local maps created in the history window.
---
--- Set a field to `false` to skip that default map. `<Plug>` maps stay available.
---@field copy_hash string | false
---@field close string | false
---@field refresh string | false

---@class dagit.Config
--- Resolved configuration. Every field is present.
---@field height number Rows. A value between 0 and 1 is a fraction of the screen.
---@field split "bottom" | "top"
---@field max_count integer Maximum commits to load.
---@field log_args string[] Extra arguments inserted into `git log`.
---@field date_format string `os.date` format, or `"relative"`.
---@field author_max_width integer
---@field ref_max_width integer Maximum width of the `(HEAD -> branch)` decoration and of the tag on the right.
---@field multi_tag_label string Label drawn when a commit has more than one tag.
---@field dim_merges boolean Dim commits that have more than one parent.
---@field git_cmd string
---@field notify boolean
---@field icons dagit.Icons
---@field symbols dagit.Symbols
---@field keymaps dagit.Keymaps
---@field on_select? fun(commit: dagit.Commit) Called for `<CR>` when set.

--- User configuration. Every field is optional.
---@class (partial) dagit.Opts : dagit.Config

---@class dagit.OpenOpts
--- Per-call overrides for `dagit.open()`.
---@field cwd? string Directory inside the repository to read.
---@field log_args? string[] Replaces `config.log_args` for this open.
---@field max_count? integer
---@field height? number

return {}
