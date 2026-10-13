--- Highlight groups linked to the active colorscheme.
---
--- Links use `default = true`, so a colorscheme or the user's config can
--- override any `Dagit*` group without this module fighting them.

local M = {}

local LINKS = {
    DagitHash = "Label",
    DagitHashLocal = "DiagnosticWarn",
    DagitUpstreamGone = "DiagnosticError",
    DagitDecor = "Delimiter",
    DagitFilter = "Comment",
    DagitMerge = "Comment",
    DagitAuthor = "Comment",
    DagitDate = "NonText",
    DagitRefHead = "Special",
    DagitRefBranch = "String",
    DagitRefRemote = "Function",
    DagitRefTag = "Constant",
    DagitBody = "Comment",
    -- Same colors `git diff --name-status` uses: green, yellow, red, cyan.
    DagitFileAdded = "DiagnosticOk",
    DagitFileModified = "DiagnosticWarn",
    DagitFileDeleted = "DiagnosticError",
    DagitFileRenamed = "DiagnosticHint",
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
    "DagitHashLocal",
    "DagitUpstreamGone",
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
    "DagitHeadMark",
}

for index = 1, 8 do
    LINE_SOURCES[#LINE_SOURCES + 1] = "DagitGraph" .. index .. "Muted"
end

for _, name in ipairs({
    "DagitHashMuted",
    "DagitHashLocalMuted",
    "DagitDecorMuted",
    "DagitMergeMuted",
    "DagitAuthorMuted",
    "DagitDateMuted",
    "DagitRefTagMuted",
    "DagitTextMuted",
    "DagitBody",
    "DagitBodyMuted",
    "DagitFileAdded",
    "DagitFileAddedMuted",
    "DagitFileModified",
    "DagitFileModifiedMuted",
    "DagitFileDeleted",
    "DagitFileDeletedMuted",
    "DagitFileRenamed",
    "DagitFileRenamedMuted",
}) do
    LINE_SOURCES[#LINE_SOURCES + 1] = name
end

local group = vim.api.nvim_create_augroup("dagit_highlights", { clear = true })
local defined = false

-- How much of the lane color a remote-only branch keeps. The rest fades
-- toward the window background so the lane stays recognizable and quieter.
local MUTED_KEEP = 0.5

---@param color integer
---@return integer red
---@return integer green
---@return integer blue
local function channels(color)
    local red = math.floor(color / 65536) % 256
    local green = math.floor(color / 256) % 256
    local blue = color % 256

    return red, green, blue
end

---@param foreground integer
---@param background integer
---@return integer
local function mix(foreground, background)
    local red, green, blue = channels(foreground)
    local back_red, back_green, back_blue = channels(background)

    local function blend(fore, back)
        return math.floor(fore * MUTED_KEEP + back * (1 - MUTED_KEEP) + 0.5)
    end

    return blend(red, back_red) * 65536 + blend(green, back_green) * 256 + blend(blue, back_blue)
end

--- Quiet copy of a group, faded toward the history background.
---
--- A group you define yourself is left alone.
---
---@param source_name string
---@param muted_name string
---@param toward integer
local function mute_one(source_name, muted_name, toward)
    local source = vim.api.nvim_get_hl(0, { name = source_name, link = false })

    if source.fg then
        vim.api.nvim_set_hl(0, muted_name, {
            fg = mix(source.fg, toward),
            ctermfg = source.ctermfg,
            default = true,
        })
    else
        vim.api.nvim_set_hl(0, muted_name, { link = "Comment", default = true })
    end
end

--- Quiet copies for remote-only branches and the text on those commits.
local function define_muted()
    local window = vim.api.nvim_get_hl(0, { name = "DagitNormal", link = false })
    local background = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
    local toward = window.bg or background.bg

    if not toward then
        toward = vim.o.background == "light" and 0xFFFFFF or 0x000000
    end

    for index = 1, 8 do
        mute_one("DagitGraph" .. index, "DagitGraph" .. index .. "Muted", toward)
    end

    for _, name in ipairs({
        "DagitHash",
        "DagitHashLocal",
        "DagitDecor",
        "DagitMerge",
        "DagitAuthor",
        "DagitDate",
        "DagitRefTag",
        "DagitBody",
        "DagitFileAdded",
        "DagitFileModified",
        "DagitFileDeleted",
        "DagitFileRenamed",
    }) do
        mute_one(name, name .. "Muted", toward)
    end

    -- The subject has no group of its own. It uses the window foreground.
    mute_one("Normal", "DagitTextMuted", toward)
end

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

    local head_label = base == "DagitHead" or base == "DagitHeadMark"

    if LINKS[base] or base:find("^DagitGraph%d") or base:find("Muted$") or head_label then
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
        reverse = hl.reverse,
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

--- Keep a field only when it has a value. `nvim_set_hl` rejects nil entries.
---
---@param fields table<string, any>
---@return vim.api.keyset.highlight
local function present(fields)
    local hl = {}

    for key, value in pairs(fields) do
        if value ~= nil then
            hl[key] = value
        end
    end

    return hl
end

--- Accent color used for the HEAD badge. `Special` is the theme accent.
---
---@return integer?, integer?
local function accent_color()
    local special = vim.api.nvim_get_hl(0, { name = "Special", link = false })

    return special.fg, special.ctermfg
end

--- Background the HEAD letters are cut out of, so the badge reads as reversed.
---
---@return integer?, integer?
local function paper_color()
    local window = vim.api.nvim_get_hl(0, { name = "DagitNormal", link = false })

    if window.bg or window.ctermbg then
        return window.bg, window.ctermbg
    end

    local normal = vim.api.nvim_get_hl(0, { name = "Normal", link = false })

    return normal.bg, normal.ctermbg
end

--- `HEAD` is the theme accent filled behind the history background.
local function define_head_label()
    local accent, accent_cterm = accent_color()
    local paper, paper_cterm = paper_color()

    if paper and accent then
        vim.api.nvim_set_hl(0, "DagitHeadMark", present({
            fg = paper,
            bg = accent,
            ctermfg = paper_cterm,
            ctermbg = accent_cterm,
            bold = true,
            default = true,
        }))
    else
        vim.api.nvim_set_hl(0, "DagitHeadMark", present({
            fg = accent,
            ctermfg = accent_cterm,
            bold = true,
            reverse = true,
            default = true,
        }))
    end
end

--- Cursor-row copy of the range under the HEAD badge.
--- The cursor line covers that range's background, so the letters use the
--- accent. The overlay keeps the reversed fill on top of the cursor line.
---
---@param cursor vim.api.keyset.hl_info
local function head_mark_line(cursor)
    local mark = vim.api.nvim_get_hl(0, { name = "DagitHeadMark", link = false })
    local accent = mark.bg or mark.fg
    local accent_cterm = mark.ctermbg or mark.ctermfg

    local function paint(name)
        vim.api.nvim_set_hl(0, name, present({
            fg = accent,
            bg = cursor.bg,
            ctermfg = accent_cterm,
            ctermbg = cursor.ctermbg,
            bold = true,
        }))
    end

    paint("DagitHeadMarkLine")
    paint("DagitHeadMarkBoldLine")
end

--- Rebuild the cursor-row groups from the colorscheme's `CursorLine`.
function M.selection()
    local cursor = vim.api.nvim_get_hl(0, { name = "CursorLine", link = false })

    for _, source in ipairs(LINE_SOURCES) do
        cursor_line(source, cursor, false)
        cursor_line(source .. "Bold", cursor, true)
    end

    cursor_line("DagitHead", cursor, true)
    head_mark_line(cursor)

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

    -- Bold, with the colorscheme foreground. The highlighted row's `>` and a
    -- non-merge HEAD subject use this. The word HEAD is `DagitHeadMark`.
    vim.api.nvim_set_hl(0, "DagitHead", { bold = true, default = true })
    define_head_label()

    -- `blend = 100` makes the TUI hide the cursor through the civis capability.
    vim.api.nvim_set_hl(0, "DagitCursor", { blend = 100, default = true })

    define_muted()

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
