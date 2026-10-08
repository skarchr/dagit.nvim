--- Highlight groups linked to the active colorscheme.
---
--- Links use `default = true`, so a colorscheme or the user's config can
--- override any `Dagit*` group without this module fighting them.

local M = {}

local LINKS = {
    DagitHash = "Label",
    DagitDecor = "Delimiter",
    DagitMerge = "Comment",
    DagitAuthor = "Comment",
    DagitDate = "NonText",
    DagitRefHead = "Special",
    DagitRefBranch = "String",
    DagitRefRemote = "Function",
    DagitRefTag = "Constant",
    DagitGraph1 = "Function",
    DagitGraph2 = "String",
    DagitGraph3 = "Special",
    DagitGraph4 = "Constant",
    DagitGraph5 = "Type",
    DagitGraph6 = "Identifier",
    DagitGraph7 = "Keyword",
    DagitGraph8 = "Number",
}

--- Groups copied onto the cursor row so the highlight runs through virtual text.
--- `CursorLine` does not paint right-aligned virtual text, and a chunk drawn
--- with `Normal` covers the row with the editor background.
local LINE_SOURCES = {
    "DagitHash",
    "DagitDecor",
    "DagitMerge",
    "DagitAuthor",
    "DagitDate",
    "DagitRefHead",
    "DagitRefBranch",
    "DagitRefRemote",
    "DagitRefTag",
    "DagitGraph1",
    "DagitGraph2",
    "DagitGraph3",
    "DagitGraph4",
    "DagitGraph5",
    "DagitGraph6",
    "DagitGraph7",
    "DagitGraph8",
}

local group = vim.api.nvim_create_augroup("dagit_highlights", { clear = true })
local defined = false

-- The history view is a normal split, so its background is `Normal`.
-- The Snacks explorer paints `SnacksPickerList` (itself linked to
-- `SnacksPicker`, which colorschemes usually point at `NormalFloat`).
local SIDEBAR_GROUPS = { "SnacksPickerList", "SnacksPicker", "NormalFloat" }

--- First highlight group that matches the Snacks explorer background.
---
---@return string?
local function sidebar_group()
    for _, name in ipairs(SIDEBAR_GROUPS) do
        if vim.fn.hlexists(name) == 1 then
            return name
        end
    end
end

--- Highlight group used for `group` on the cursor row.
---
---@param group string
---@return string
function M.line_group(group)
    local base = group:gsub("Bold$", "")

    if LINKS[base] or base:find("^DagitGraph%d$") or base == "DagitHead" then
        return group .. "Line"
    end

    return "DagitLine"
end

---@param source string
---@param cursor vim.api.keyset.hl_info
---@param force_bold boolean?
local function cursor_line(source, cursor, force_bold)
    local hl = vim.api.nvim_get_hl(0, { name = source, link = false })

    vim.api.nvim_set_hl(0, source .. "Line", {
        fg = hl.fg,
        bg = cursor.bg,
        sp = hl.sp,
        ctermfg = hl.ctermfg,
        ctermbg = cursor.ctermbg,
        bold = force_bold or hl.bold,
        italic = hl.italic,
        underline = hl.underline,
        undercurl = hl.undercurl,
        strikethrough = hl.strikethrough,
    })
end

--- Copy a group and force bold, for the commit HEAD points at.
---
---@param source string
local function define_bold(source)
    local hl = vim.api.nvim_get_hl(0, { name = source, link = false })

    vim.api.nvim_set_hl(0, source .. "Bold", {
        fg = hl.fg,
        bg = hl.bg,
        sp = hl.sp,
        ctermfg = hl.ctermfg,
        ctermbg = hl.ctermbg,
        bold = true,
        italic = hl.italic,
        underline = hl.underline,
        undercurl = hl.undercurl,
        strikethrough = hl.strikethrough,
        reverse = hl.reverse,
    })
end

--- Rebuild the cursor-row groups from the colorscheme's `CursorLine`.
function M.selection()
    local cursor = vim.api.nvim_get_hl(0, { name = "CursorLine", link = false })

    for _, source in ipairs(LINE_SOURCES) do
        cursor_line(source, cursor, false)
        cursor_line(source .. "Bold", cursor, true)
    end

    cursor_line("DagitHead", cursor, true)

    vim.api.nvim_set_hl(0, "DagitLine", {
        bg = cursor.bg,
        ctermbg = cursor.ctermbg,
    })
end

function M.define()
    for name, link in pairs(LINKS) do
        vim.api.nvim_set_hl(0, name, { link = link, default = true })
    end

    -- Padding must not paint the editor background over the cursor row.
    vim.api.nvim_set_hl(0, "DagitPad", { bg = "NONE", ctermbg = "NONE", default = true })

    local sidebar = sidebar_group()

    if sidebar then
        vim.api.nvim_set_hl(0, "DagitNormal", { link = sidebar, default = true })
    end

    -- Bold, with the colorscheme foreground. The highlighted row's `>`, the
    -- `HEAD ->` label, and a non-merge HEAD subject use this.
    vim.api.nvim_set_hl(0, "DagitHead", { bold = true, default = true })

    -- `blend = 100` makes the TUI hide the cursor through the civis capability.
    vim.api.nvim_set_hl(0, "DagitCursor", { blend = 100, default = true })

    for _, source in ipairs(LINE_SOURCES) do
        define_bold(source)
    end

    M.selection()
end

--- Define groups once, and again after a colorscheme clears them.
function M.install()
    M.define()

    if defined then
        return
    end

    defined = true

    vim.api.nvim_create_autocmd("ColorScheme", {
        group = group,
        callback = M.define,
        desc = "Relink dagit highlight groups to the colorscheme",
    })
end

return M
