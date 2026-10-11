--- Resolve and validate user configuration.
---
--- `setup()` is optional. The plugin reads `vim.g.dagit` the first time it
--- needs a value, and `setup()` only stores an override on top of that.

local M = {}

---@type dagit.Config
local defaults = {
    height = 16,
    split = "bottom",
    max_count = 256,
    log_args = { "--all" },
    date_format = "%d %b %H:%M",
    author_max_width = 22,
    ref_max_width = 30,
    multi_tag_label = "multi tag",
    dim_merges = true,
    git_cmd = "git",
    notify = true,
    icons = {
        enabled = true,
        head = "󰘬",
        branch = "󰘬",
        remote = "",
        tag = "󰓹",
    },
    -- Ghostty, Kitty, and Contour draw these private-use glyphs themselves,
    -- out to the cell edge, so a vertical lane has no gap between rows.
    -- Terminals that do not draw them get `portable_symbols` from `resolve()`.
    symbols = {
        commit = "",
        commit_down = "",
        commit_up = "",
        commit_through = "",
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
        expand = "<CR>",
        show = "z",
        collapse = "Z",
    },
}

--- Keys whose tables are replaced instead of merged index-by-index.
local replace_keys = {
    log_args = true,
}

--- Nerd Font circles for terminals that do not draw branch glyphs.
--- The stroke sits inside the em box, so a tall line height can leave a gap.
local portable_symbols = {
    commit = "●",
    commit_down = "󰜝",
    commit_up = "󰜙",
    commit_through = "󰜘",
    vertical = "│",
    horizontal = "─",
    branch_start = "╮",
    merge_right = "╯",
    merge_left = "╰",
    diagonal_right = "╲",
    diagonal_left = "╱",
}

--- True when the outer terminal paints U+F5D0–U+F60D to the cell edge.
---
---@return boolean
function M.branch_drawing_supported()
    if vim.env.KITTY_WINDOW_ID or vim.env.GHOSTTY_RESOURCES_DIR then
        return true
    end

    local program = string.lower(vim.env.TERM_PROGRAM or "")

    if program == "ghostty" or program == "kitty" or program == "contour" then
        return true
    end

    local term = string.lower(vim.env.TERM or "")

    return term:find("kitty", 1, true) ~= nil
        or term:find("ghostty", 1, true) ~= nil
        or term:find("contour", 1, true) ~= nil
end

---@type dagit.Opts?
local user_opts = nil

--- Remember the table passed to `setup()`.
---
---@param opts dagit.Opts?
function M.set_user_opts(opts)
    user_opts = opts
end

---@return dagit.Config
local function copy_defaults()
    return vim.deepcopy(defaults)
end

--- Merge `override` onto `base`.
---
--- List-shaped settings such as `log_args` are replaced. Nested tables such
--- as `icons` are merged so a user can override one glyph.
---
---@param base table
---@param override table
---@return table
local function merge(base, override)
    local out = vim.deepcopy(base)

    for key, value in pairs(override) do
        if replace_keys[key] or type(value) ~= "table" or type(out[key]) ~= "table" then
            out[key] = vim.deepcopy(value)
        else
            out[key] = merge(out[key], value)
        end
    end

    return out
end

---@param issues string[]
---@param path string
---@param value any
---@param expected string
---@return boolean
local function check_type(issues, path, value, expected)
    local actual = type(value)

    if actual == expected then
        return true
    end

    issues[#issues + 1] = string.format("%s: expected %s, got %s", path, expected, actual)

    return false
end

---@param issues string[]
---@param path string
---@param value any
---@return boolean
local function check_string_list(issues, path, value)
    if not check_type(issues, path, value, "table") then
        return false
    end

    for index, item in ipairs(value) do
        if type(item) ~= "string" then
            issues[#issues + 1] = string.format("%s[%d]: expected string, got %s", path, index, type(item))

            return false
        end
    end

    return true
end

---@param issues string[]
---@param path string
---@param value any
---@param allowed string[]
---@return boolean
local function check_enum(issues, path, value, allowed)
    if not check_type(issues, path, value, "string") then
        return false
    end

    if vim.tbl_contains(allowed, value) then
        return true
    end

    issues[#issues + 1] = string.format("%s: expected one of %s, got %s", path, table.concat(allowed, ", "), value)

    return false
end

---@param issues string[]
---@param cfg dagit.Config
local function validate_symbols(issues, cfg)
    if not check_type(issues, "symbols", cfg.symbols, "table") then
        return
    end

    local names = {
        "commit",
        "commit_down",
        "commit_up",
        "commit_through",
        "vertical",
        "horizontal",
        "branch_start",
        "merge_right",
        "merge_left",
        "diagonal_right",
        "diagonal_left",
    }

    for _, name in ipairs(names) do
        local value = cfg.symbols[name]

        if type(value) ~= "string" or value == "" then
            issues[#issues + 1] = string.format("symbols.%s: expected a non-empty string, got %s", name, type(value))
        end
    end

    local width = nil

    for _, name in ipairs({ "commit", "commit_down", "commit_up", "commit_through" }) do
        local value = cfg.symbols[name]

        if type(value) == "string" and value ~= "" then
            local glyph_width = vim.api.nvim_strwidth(value)

            if width == nil then
                width = glyph_width
            elseif glyph_width ~= width then
                issues[#issues + 1] =
                    "symbols.commit, commit_down, commit_up, and commit_through must share a display width"

                break
            end
        end
    end
end

---@param issues string[]
---@param cfg dagit.Config
local function validate_icons(issues, cfg)
    if not check_type(issues, "icons", cfg.icons, "table") then
        return
    end

    check_type(issues, "icons.enabled", cfg.icons.enabled, "boolean")

    for _, name in ipairs({ "head", "branch", "remote", "tag" }) do
        local value = cfg.icons[name]

        if type(value) ~= "string" then
            issues[#issues + 1] = string.format("icons.%s: expected string, got %s", name, type(value))
        end
    end
end

---@param issues string[]
---@param cfg dagit.Config
local function validate_keymaps(issues, cfg)
    if not check_type(issues, "keymaps", cfg.keymaps, "table") then
        return
    end

    local known = {
        copy_hash = true,
        close = true,
        refresh = true,
        expand = true,
        show = true,
        collapse = true,
    }

    for key, value in pairs(cfg.keymaps) do
        if not known[key] then
            issues[#issues + 1] = string.format("keymaps.%s: unknown keymap", key)
        elseif value ~= false and type(value) ~= "string" then
            issues[#issues + 1] = string.format("keymaps.%s: expected string or false, got %s", key, type(value))
        elseif value == "" then
            issues[#issues + 1] = string.format("keymaps.%s: expected a non-empty string or false", key)
        end
    end
end

--- Collect configuration problems.
---
---@param cfg dagit.Config
---@return string[]
function M.validate(cfg)
    local issues = {}

    if check_type(issues, "height", cfg.height, "number") then
        if cfg.height <= 0 or cfg.height ~= cfg.height then
            issues[#issues + 1] = "height: expected a positive number of rows, or a fraction between 0 and 1"
        end
    end

    check_enum(issues, "split", cfg.split, { "bottom", "top" })

    if check_type(issues, "max_count", cfg.max_count, "number") then
        if cfg.max_count < 1 or cfg.max_count % 1 ~= 0 then
            issues[#issues + 1] = "max_count: expected an integer >= 1"
        end
    end

    check_string_list(issues, "log_args", cfg.log_args)

    if check_type(issues, "date_format", cfg.date_format, "string") and cfg.date_format == "" then
        issues[#issues + 1] = 'date_format: expected a non-empty os.date format, or "relative"'
    end

    if check_type(issues, "author_max_width", cfg.author_max_width, "number") then
        if cfg.author_max_width < 4 or cfg.author_max_width % 1 ~= 0 then
            issues[#issues + 1] = "author_max_width: expected an integer >= 4"
        end
    end

    if check_type(issues, "ref_max_width", cfg.ref_max_width, "number") then
        if cfg.ref_max_width < 4 or cfg.ref_max_width % 1 ~= 0 then
            issues[#issues + 1] = "ref_max_width: expected an integer >= 4"
        end
    end

    if check_type(issues, "multi_tag_label", cfg.multi_tag_label, "string") and cfg.multi_tag_label == "" then
        issues[#issues + 1] = "multi_tag_label: expected a non-empty string"
    end

    check_type(issues, "dim_merges", cfg.dim_merges, "boolean")

    if check_type(issues, "git_cmd", cfg.git_cmd, "string") and cfg.git_cmd == "" then
        issues[#issues + 1] = "git_cmd: expected a non-empty string"
    end

    check_type(issues, "notify", cfg.notify, "boolean")
    validate_icons(issues, cfg)
    validate_symbols(issues, cfg)
    validate_keymaps(issues, cfg)

    if cfg.on_select ~= nil and type(cfg.on_select) ~= "function" then
        issues[#issues + 1] = string.format("on_select: expected function or nil, got %s", type(cfg.on_select))
    end

    local known = {
        height = true,
        split = true,
        max_count = true,
        log_args = true,
        date_format = true,
        author_max_width = true,
        ref_max_width = true,
        multi_tag_label = true,
        dim_merges = true,
        git_cmd = true,
        notify = true,
        icons = true,
        symbols = true,
        keymaps = true,
        on_select = true,
    }

    for key, _ in pairs(cfg) do
        if not known[key] then
            issues[#issues + 1] = string.format("%s: unknown configuration field", key)
        end
    end

    table.sort(issues)

    return issues
end

---@param value any
---@return table?
---@return string?
local function coerce_user_table(value, path)
    if value == nil then
        return nil, nil
    end

    if type(value) == "function" then
        local ok, result = pcall(value)

        if not ok then
            return nil, string.format("%s: function raised an error: %s", path, result)
        end

        value = result
    end

    if type(value) ~= "table" then
        return nil, string.format("%s: expected a table, got %s", path, type(value))
    end

    return value, nil
end

--- Merge defaults, `vim.g.dagit`, and `setup()` options.
---
--- Invalid configuration falls back to the defaults. The returned issues
--- describe the user's table so health checks can still report them.
---
---@return dagit.Config
---@return string[]
function M.resolve()
    local issues = {}
    local merged = copy_defaults()

    local global_config, global_error = coerce_user_table(vim.g.dagit, "vim.g.dagit")

    if global_error then
        issues[#issues + 1] = global_error
    elseif global_config then
        merged = merge(merged, global_config)
    end

    local setup_config, setup_error = coerce_user_table(user_opts, "setup()")

    if setup_error then
        issues[#issues + 1] = setup_error
    elseif setup_config then
        merged = merge(merged, setup_config)
    end

    local symbols_set = (type(global_config) == "table" and type(global_config.symbols) == "table")
        or (type(setup_config) == "table" and type(setup_config.symbols) == "table")

    if not symbols_set and not M.branch_drawing_supported() then
        merged.symbols = vim.deepcopy(portable_symbols)
    end

    vim.list_extend(issues, M.validate(merged))
    table.sort(issues)

    if #issues > 0 then
        return copy_defaults(), issues
    end

    ---@cast merged dagit.Config
    return merged, issues
end

--- Default configuration, for tests and documentation.
---
---@return dagit.Config
function M.defaults()
    return copy_defaults()
end

return M
