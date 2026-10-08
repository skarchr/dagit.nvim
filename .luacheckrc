-- Rerun tests only if their modification time changed.
cache = true

std = luajit
codes = true

self = false

-- Reference: https://luacheck.readthedocs.io/en/stable/warnings.html
ignore = {
    -- Neovim lua API + luacheck thinks assignments like `vim.wo.spell = true`
    -- are invalid. They are valid, so silence rule 122.
    "122",
}

-- Global objects defined by the C code
read_globals = { "vim" }

exclude_files = {}
globals = { "describe", "it", "assert" }
