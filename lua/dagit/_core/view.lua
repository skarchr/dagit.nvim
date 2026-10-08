--- History buffer and the bottom split that shows it.

local configuration = require("dagit._core.configuration")
local git = require("dagit._core.git")
local highlights = require("dagit._core.highlights")
local render = require("dagit._core.render")

local M = {}

local NAMESPACE = vim.api.nvim_create_namespace("dagit")

---@class dagit.ViewState
---@field buf integer
---@field cwd string
---@field log_args string[]
---@field max_count integer
---@field commits dagit.Commit[]
---@field lines dagit.RenderedLine[]
---@field selected integer?
---@field line_mark integer?

---@type table<integer, dagit.ViewState>
local states = {}

local warned = false

--- Saved `'guicursor'` while the history window hides the caret.
---@type string?
local saved_guicursor = nil

local function hide_cursor()
    if saved_guicursor == nil then
        saved_guicursor = vim.o.guicursor
    end

    -- The row highlight is the selection. A caret on one cell is unused.
    vim.o.guicursor = "a:DagitCursor/DagitCursor"
end

local function show_cursor()
    if saved_guicursor == nil then
        return
    end

    vim.o.guicursor = saved_guicursor
    saved_guicursor = nil
end

---@param message string
---@param level integer
local function notify(message, level)
    local config = configuration.resolve()

    if not config.notify and level ~= vim.log.levels.ERROR then
        return
    end

    vim.notify(message, level, { title = "dagit" })
end

local function warn_configuration()
    if warned then
        return
    end

    local _, issues = configuration.resolve()

    if #issues == 0 then
        return
    end

    warned = true
    notify("Invalid configuration. Using defaults.\n" .. table.concat(issues, "\n"), vim.log.levels.ERROR)
end

---@param buf integer
---@return dagit.ViewState?
local function state_of(buf)
    return states[buf]
end

---@return integer? buf
---@return integer? win
local function find_window()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
        local buf = vim.api.nvim_win_get_buf(win)

        if states[buf] then
            return buf, win
        end
    end

    for buf, _ in pairs(states) do
        if vim.api.nvim_buf_is_valid(buf) then
            return buf, nil
        end
    end
end

---@param line dagit.RenderedLine
---@param selected boolean
---@return string[][]
local function virt_chunks(line, selected)
    local chunks = {}

    for _, chunk in ipairs(line.virt) do
        local group = chunk.group

        if selected then
            group = highlights.line_group(group)
        end

        chunks[#chunks + 1] = { chunk.text, group }
    end

    return chunks
end

---@param buf integer
---@param line dagit.RenderedLine
---@param row integer Zero-based line.
local function apply_line_marks(buf, line, row)
    line.span_marks = {}

    for _, span in ipairs(line.spans) do
        if span.stop > span.start then
            local id = vim.api.nvim_buf_set_extmark(buf, NAMESPACE, row, span.start, {
                end_col = span.stop,
                hl_group = span.group,
                hl_mode = "combine",
            })

            line.span_marks[#line.span_marks + 1] = {
                id = id,
                start = span.start,
                stop = span.stop,
                group = span.group,
            }
        end
    end

    line.virt_mark = vim.api.nvim_buf_set_extmark(buf, NAMESPACE, row, 0, {
        virt_text = virt_chunks(line, false),
        virt_text_pos = "right_align",
        hl_mode = "combine",
    })
end

---@param state dagit.ViewState
---@param row integer One-based row.
---@param selected boolean
local function paint_row(state, row, selected)
    local line = state.lines[row]

    if not line then
        return
    end

    for _, span in ipairs(line.span_marks or {}) do
        local group = selected and highlights.line_group(span.group) or span.group

        vim.api.nvim_buf_set_extmark(state.buf, NAMESPACE, row - 1, span.start, {
            id = span.id,
            end_col = span.stop,
            hl_group = group,
            hl_mode = "combine",
        })
    end

    if line.virt_mark then
        vim.api.nvim_buf_set_extmark(state.buf, NAMESPACE, row - 1, 0, {
            id = line.virt_mark,
            virt_text = virt_chunks(line, selected),
            virt_text_pos = "right_align",
            hl_mode = "combine",
        })
    end
end

--- Put `>` or a space in the first cell. Other extmarks on the row are redrawn.
---
---@param state dagit.ViewState
---@param row integer One-based row.
---@param glyph string
local function write_marker(state, row, glyph)
    local line = state.lines[row]

    if not line or line.text:sub(1, 1) == glyph then
        return
    end

    line.text = glyph .. line.text:sub(2)
    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_set_text(state.buf, row - 1, 0, row - 1, 1, { glyph })
    vim.bo[state.buf].modifiable = false
    vim.bo[state.buf].modified = false

    -- Replacing the first cell can drop extmarks that sit on that column.
    vim.api.nvim_buf_clear_namespace(state.buf, NAMESPACE, row - 1, row)
    line.virt_mark = nil
    line.span_marks = nil
    apply_line_marks(state.buf, line, row - 1)
end

---@param state dagit.ViewState
local function draw(state)
    local config = configuration.resolve()
    state.lines = render.build(state.commits, config)
    state.selected = nil
    state.line_mark = nil

    local texts = {}

    for index, line in ipairs(state.lines) do
        texts[index] = line.text
    end

    if #texts == 0 then
        texts[1] = "No commits"
    end

    vim.bo[state.buf].modifiable = true
    vim.api.nvim_buf_clear_namespace(state.buf, NAMESPACE, 0, -1)
    vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, texts)
    vim.bo[state.buf].modifiable = false
    vim.bo[state.buf].modified = false

    for index, line in ipairs(state.lines) do
        apply_line_marks(state.buf, line, index - 1)
    end
end

---@param state dagit.ViewState
---@param row integer One-based cursor row.
local function select_row(state, row)
    local line = state.lines[row]

    if not line or state.selected == row then
        return
    end

    if state.selected then
        write_marker(state, state.selected, " ")
        paint_row(state, state.selected, false)
    end

    -- Repaint the row with CursorLine's background. Virtual text is not
    -- covered by the window's cursorline, so the gaps would stay dark.
    highlights.selection()
    write_marker(state, row, ">")
    paint_row(state, row, true)

    -- `>` sits in the buffer. This highlight makes it bold on the cursor row.
    vim.api.nvim_buf_set_extmark(state.buf, NAMESPACE, row - 1, 0, {
        end_col = 1,
        hl_group = highlights.line_group("DagitHead"),
        hl_mode = "combine",
        priority = 20,
    })

    state.line_mark = vim.api.nvim_buf_set_extmark(state.buf, NAMESPACE, row - 1, 0, {
        line_hl_group = "CursorLine",
        hl_eol = true,
        priority = 10,
    })
    state.selected = row
end

---@param buf integer
local function on_cursor_moved(buf)
    local state = state_of(buf)

    if not state then
        return
    end

    local win = vim.fn.bufwinid(buf)

    if win == -1 then
        return
    end

    select_row(state, vim.api.nvim_win_get_cursor(win)[1])
end

---@param lhs string
---@return string
local function normalize_lhs(lhs)
    return vim.api.nvim_replace_termcodes(lhs, true, true, true)
end

---@param buf integer
local function buffer_map(buf, lhs, rhs, desc)
    if not lhs or lhs == false then
        return
    end

    local wanted = normalize_lhs(lhs)

    for _, map in ipairs(vim.api.nvim_buf_get_keymap(buf, "n")) do
        if map.lhs == lhs or normalize_lhs(map.lhs) == wanted then
            return
        end
    end

    vim.keymap.set("n", lhs, rhs, {
        buffer = buf,
        silent = true,
        nowait = true,
        desc = desc,
    })
end

---@param buf integer
local function apply_keymaps(buf)
    local config = configuration.resolve()

    buffer_map(buf, config.keymaps.copy_hash, function()
        require("dagit").copy_hash()
    end, "Copy the commit hash under the cursor")

    buffer_map(buf, config.keymaps.close, function()
        require("dagit").close()
    end, "Close the git history")

    buffer_map(buf, config.keymaps.refresh, function()
        require("dagit").refresh()
    end, "Reload the git history")

    if config.on_select then
        buffer_map(buf, "<CR>", function()
            local commit = require("dagit").commit()

            if commit then
                config.on_select(commit)
            end
        end, "Select the commit under the cursor")
    end
end

---@param buf integer
local function apply_buffer_options(buf)
    vim.bo[buf].buftype = "nofile"
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].swapfile = false
    vim.bo[buf].buflisted = false
    vim.bo[buf].modifiable = false
    vim.bo[buf].undolevels = -1
    -- Commit subjects are external text. A modeline in a subject must not
    -- change editor options.
    vim.bo[buf].modeline = false
end

---@param win integer
---@param height number
local function apply_window_options(win, height)
    local screen = math.max(1, vim.o.lines - vim.o.cmdheight - 2)
    local rows

    if height > 0 and height < 1 then
        rows = math.max(1, math.floor(screen * height))
    else
        rows = math.floor(height)
    end

    vim.api.nvim_win_set_height(win, math.max(1, math.min(rows, screen)))

    vim.wo[win].cursorline = true
    vim.wo[win].cursorlineopt = "line"
    vim.wo[win].wrap = false
    vim.wo[win].number = false
    vim.wo[win].relativenumber = false
    vim.wo[win].signcolumn = "no"
    vim.wo[win].foldenable = false
    vim.wo[win].spell = false
    vim.wo[win].list = false
    vim.wo[win].winfixheight = true
    vim.wo[win].colorcolumn = ""
    -- Match the Snacks explorer. A split paints `Normal`; the explorer paints
    -- `SnacksPickerList` / `NormalFloat`. `DagitNormal` is that link.
    -- `DagitCursor` has blend 100, so the caret does not cover a cell.
    vim.wo[win].winhighlight = table.concat({
        "Normal:DagitNormal",
        "NormalNC:DagitNormal",
        "Cursor:DagitCursor",
        "lCursor:DagitCursor",
        "TermCursor:DagitCursor",
    }, ",")
end

---@param state dagit.ViewState
---@return boolean
local function reload(state)
    local commits, err = git.log(configuration.resolve().git_cmd, state.cwd, state.log_args, state.max_count)

    if not commits then
        notify(err or "Could not read git history", vim.log.levels.ERROR)

        if #state.commits == 0 then
            vim.bo[state.buf].modifiable = true
            vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, { err or "Could not read git history" })
            vim.bo[state.buf].modifiable = false
            vim.bo[state.buf].modified = false
        end

        return false
    end

    state.commits = commits
    draw(state)

    local win = vim.fn.bufwinid(state.buf)

    if win ~= -1 and #state.lines > 0 then
        local cursor = vim.api.nvim_win_get_cursor(win)
        local row = math.min(cursor[1], #state.lines)
        vim.api.nvim_win_set_cursor(win, { row, 0 })
        select_row(state, row)
    end

    return true
end

---@param cwd string
---@return string?
local function current_directory(cwd)
    if cwd and cwd ~= "" then
        return cwd
    end

    local name = vim.api.nvim_buf_get_name(0)

    if name ~= "" and not name:find("^dagit://") then
        local parent = vim.fs.dirname(name)

        if parent and parent ~= "" then
            return parent
        end
    end

    return vim.fn.getcwd()
end

--- Open the history split, or focus it when it is already open.
---
---@param opts dagit.OpenOpts?
---@return boolean opened
function M.open(opts)
    warn_configuration()
    highlights.install()

    opts = opts or {}
    local config = configuration.resolve()
    local existing_buf, existing_win = find_window()

    if existing_buf and existing_win then
        vim.api.nvim_set_current_win(existing_win)

        if opts.log_args or opts.max_count or opts.cwd then
            local state = states[existing_buf]
            state.cwd = current_directory(opts.cwd)
            state.log_args = opts.log_args or state.log_args
            state.max_count = opts.max_count or state.max_count

            return reload(state)
        end

        return true
    end

    local cwd = current_directory(opts.cwd)
    local log_args = opts.log_args or vim.deepcopy(config.log_args)
    local max_count = opts.max_count or config.max_count
    local height = opts.height or config.height

    if not existing_buf then
        existing_buf = vim.api.nvim_create_buf(false, true)
        local named = pcall(vim.api.nvim_buf_set_name, existing_buf, "dagit://log")

        if not named then
            pcall(vim.api.nvim_buf_set_name, existing_buf, "dagit://log-" .. existing_buf)
        end
        apply_buffer_options(existing_buf)
        vim.b[existing_buf].dagit = true
        vim.bo[existing_buf].filetype = "dagit"
        apply_keymaps(existing_buf)

        vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
            buffer = existing_buf,
            callback = function()
                states[existing_buf] = nil
                show_cursor()
            end,
            desc = "Drop dagit history state when the buffer is wiped",
        })

        vim.api.nvim_create_autocmd("WinEnter", {
            buffer = existing_buf,
            callback = hide_cursor,
            desc = "Hide the caret in the git history window",
        })

        vim.api.nvim_create_autocmd("WinLeave", {
            buffer = existing_buf,
            callback = show_cursor,
            desc = "Restore the caret when leaving the git history window",
        })

        vim.api.nvim_create_autocmd("CursorMoved", {
            buffer = existing_buf,
            callback = function()
                on_cursor_moved(existing_buf)
            end,
            desc = "Mark the commit row under the cursor",
        })
    end

    local split = config.split == "top" and "topleft split" or "botright split"
    vim.cmd(split)

    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, existing_buf)
    apply_window_options(win, height)

    states[existing_buf] = {
        buf = existing_buf,
        cwd = cwd,
        log_args = log_args,
        max_count = max_count,
        commits = {},
        lines = {},
    }

    hide_cursor()

    return reload(states[existing_buf])
end

--- Close the history window.
function M.close()
    local buf, win = find_window()

    show_cursor()

    if win and #vim.api.nvim_list_wins() > 1 then
        vim.api.nvim_win_close(win, true)
    elseif win then
        vim.cmd("enew")
    end

    if buf and vim.api.nvim_buf_is_valid(buf) then
        vim.api.nvim_buf_delete(buf, { force = true })
    end
end

--- Reload commits into the open history buffer.
---
---@return boolean
function M.refresh()
    local buf = find_window()

    if not buf or not states[buf] then
        notify("Git history is not open", vim.log.levels.WARN)

        return false
    end

    return reload(states[buf])
end

--- Commit under the cursor in the history window.
---
---@return dagit.Commit?
function M.commit()
    local buf, win = find_window()

    if not buf or not win or not states[buf] then
        return nil
    end

    if vim.api.nvim_get_current_buf() ~= buf then
        return nil
    end

    local row = vim.api.nvim_win_get_cursor(win)[1]

    return states[buf].commits[row]
end

--- Copy the full hash of the commit under the cursor.
---
---@return string? hash
function M.copy_hash()
    local commit = M.commit()

    if not commit then
        notify("No commit under the cursor", vim.log.levels.WARN)

        return nil
    end

    vim.fn.setreg('"', commit.hash)

    if vim.fn.has("clipboard") == 1 then
        vim.fn.setreg("+", commit.hash)
    end

    notify("Copied " .. commit.hash:sub(1, 12), vim.log.levels.INFO)

    return commit.hash
end

return M
