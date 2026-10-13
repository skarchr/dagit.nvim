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
---@field marked integer? Commit row that shows `>`.
---@field line_mark integer?
---@field chevron_mark integer?
---@field drawing boolean?
---@field expanded table<string, boolean>
---@field details table<string, dagit.CommitDetail>
---@field filter "all" | "local" | "remote"
---@field shown dagit.Commit[] Commits left after the filter. Row indexes point here.

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

--- `line_hl_group` covers an extmark range's background. A reversed badge
--- is drawn again as overlay text, which keeps its own fill.
---
---@param group string
---@return boolean
local function keeps_fill(group)
    return group:find("DagitHeadMark", 1, true) == 1 or group:find("Rev", 1, true) ~= nil
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

            local stored = {
                id = id,
                start = span.start,
                stop = span.stop,
                group = span.group,
            }

            if keeps_fill(span.group) then
                stored.overlay = vim.api.nvim_buf_set_extmark(buf, NAMESPACE, row, span.start, {
                    virt_text = { { line.text:sub(span.start + 1, span.stop), span.group } },
                    virt_text_pos = "overlay",
                    hl_mode = "replace",
                    priority = 65535,
                })
            end

            line.span_marks[#line.span_marks + 1] = stored
        end
    end

    if #line.virt > 0 then
        line.virt_mark = vim.api.nvim_buf_set_extmark(buf, NAMESPACE, row, 0, {
            virt_text = virt_chunks(line, false),
            virt_text_pos = "right_align",
            hl_mode = "combine",
        })
    end

    if line.above_lines and #line.above_lines > 0 then
        vim.api.nvim_buf_set_extmark(buf, NAMESPACE, row, 0, {
            virt_lines = line.above_lines,
            virt_lines_above = true,
        })
    end
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

        if span.overlay then
            vim.api.nvim_buf_set_extmark(state.buf, NAMESPACE, row - 1, span.start, {
                id = span.overlay,
                virt_text = { { line.text:sub(span.start + 1, span.stop), span.group } },
                virt_text_pos = "overlay",
                hl_mode = "replace",
                priority = 65535,
            })
        end
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

    if state.marked == row then
        state.chevron_mark = nil
    end

    apply_line_marks(state.buf, line, row - 1)
end

local FILTERS = { "all", "local", "remote" }

local FILTER_FIELD = {
    ["local"] = "on_local",
    remote = "on_remote",
}

--- Commits the active filter leaves on screen.
---
--- `all` is the loaded log. `local` keeps commits reachable from a local
--- branch or HEAD. `remote` keeps commits reachable from a remote-tracking
--- ref.
---
---@param commits dagit.Commit[]
---@param filter string?
---@return dagit.Commit[]
local function visible_commits(commits, filter)
    local field = FILTER_FIELD[filter or "all"]

    if not field then
        return commits
    end

    local shown = {}

    for _, commit in ipairs(commits) do
        if commit[field] then
            shown[#shown + 1] = commit
        end
    end

    return shown
end

--- Filter line for the window bar. Brackets mark the active name.
---
---@param filter string?
---@return string
function M.filter_bar(filter)
    local active = filter or "all"
    local parts = {}

    for _, name in ipairs(FILTERS) do
        local chosen = name == active
        local label = chosen and ("[" .. name .. "]") or name
        local group = chosen and "DagitHead" or "DagitFilter"

        parts[#parts + 1] = "%#" .. group .. "#" .. label
    end

    return "%#DagitFilter# " .. table.concat(parts, "  ")
end

---@param filter string?
---@param direction integer
---@return string
local function step_filter(filter, direction)
    local index = 1

    for at, name in ipairs(FILTERS) do
        if name == filter then
            index = at
            break
        end
    end

    return FILTERS[((index - 1 + direction) % #FILTERS) + 1]
end

--- Keep the filter line pinned to the top of every history window.
---
---@param state dagit.ViewState
local function paint_filter(state)
    local bar = M.filter_bar(state.filter)

    for _, win in ipairs(vim.api.nvim_list_wins()) do
        if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == state.buf then
            vim.wo[win].winbar = bar
        end
    end
end

--- Commit rows, with the open description and file list under each one.
---
---@param state dagit.ViewState
---@param config dagit.Config
---@return dagit.RenderedLine[]
local function compose(state, config)
    local shown = visible_commits(state.commits, state.filter)
    state.shown = shown
    local commits = render.build(shown, config)
    local lines = {}

    state.expanded = state.expanded or {}
    state.details = state.details or {}

    for index, line in ipairs(commits) do
        line.kind = "commit"
        lines[#lines + 1] = line

        local commit = shown[index]
        local detail = commit and state.expanded[commit.hash] and state.details[commit.hash]

        if detail then
            for _, extra in ipairs(render.detail_lines(line, detail)) do
                lines[#lines + 1] = extra
            end
        end
    end

    return lines
end

---@param state dagit.ViewState
local function draw(state)
    local config = configuration.resolve()
    state.lines = compose(state, config)
    state.selected = nil
    state.marked = nil
    state.line_mark = nil
    state.chevron_mark = nil
    state.drawing = true

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

    state.drawing = false
    paint_filter(state)
end

--- Buffer row of the commit that owns `row`. Detail rows belong to the commit above them.
---
---@param state dagit.ViewState
---@param row integer
---@return integer?
local function owner_row(state, row)
    local line = state.lines[row]

    if not line then
        return nil
    end

    if line.kind ~= "detail" then
        return row
    end

    for index = row - 1, 1, -1 do
        local candidate = state.lines[index]

        if candidate and candidate.kind ~= "detail" and candidate.commit_index == line.commit_index then
            return index
        end
    end
end

--- Bold `>` on the commit row. On the cursor row it also takes the cursor background.
---
---@param state dagit.ViewState
---@param row integer
---@param on_cursor boolean
local function show_chevron(state, row, on_cursor)
    local group = on_cursor and highlights.line_group("DagitHead") or "DagitHead"
    local opts = {
        end_col = 1,
        hl_group = group,
        hl_mode = "combine",
        priority = 20,
    }

    if state.chevron_mark then
        opts.id = state.chevron_mark
    end

    local ok, id = pcall(vim.api.nvim_buf_set_extmark, state.buf, NAMESPACE, row - 1, 0, opts)

    if not ok then
        opts.id = nil
        id = vim.api.nvim_buf_set_extmark(state.buf, NAMESPACE, row - 1, 0, opts)
    end

    state.chevron_mark = id
end

---@param state dagit.ViewState
---@param row integer One-based cursor row.
local function select_row(state, row)
    local line = state.lines[row]

    if not line or state.selected == row then
        return
    end

    local owner = owner_row(state, row)

    if not owner then
        return
    end

    if state.line_mark then
        pcall(vim.api.nvim_buf_del_extmark, state.buf, NAMESPACE, state.line_mark)
        state.line_mark = nil
    end

    if state.selected and state.selected ~= row then
        paint_row(state, state.selected, false)
    end

    -- Repaint the cursor row with CursorLine's background. Virtual text is not
    -- covered by the window's cursorline, so the gaps would stay dark.
    highlights.selection()

    if state.marked ~= owner then
        if state.marked then
            write_marker(state, state.marked, " ")
            paint_row(state, state.marked, false)
        end

        write_marker(state, owner, ">")
        state.marked = owner
        state.chevron_mark = nil
    elseif state.selected == owner and owner ~= row then
        paint_row(state, owner, false)
    end

    paint_row(state, row, true)
    show_chevron(state, owner, owner == row)

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

    if not state or state.drawing then
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

    buffer_map(buf, config.keymaps.expand, function()
        require("dagit").expand()
    end, "Show or hide the commit description and files")

    buffer_map(buf, config.keymaps.show, function()
        require("dagit").show()
    end, "Show or hide the commit description and files")

    buffer_map(buf, config.keymaps.collapse, function()
        require("dagit").collapse()
    end, "Hide every expanded commit")

    buffer_map(buf, config.keymaps.filter_next, function()
        M.filter_next()
    end, "Show the next commit filter")

    buffer_map(buf, config.keymaps.filter_prev, function()
        M.filter_prev()
    end, "Show the previous commit filter")

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
        "WinBar:DagitNormal",
        "WinBarNC:DagitNormal",
        "Cursor:DagitCursor",
        "lCursor:DagitCursor",
        "TermCursor:DagitCursor",
    }, ",")
end

--- One-based row of the commit that is checked out.
--- The first row is used when that commit is outside the loaded log.
---
---@param commits dagit.Commit[]
---@return integer
local function checked_out_row(commits)
    for index, commit in ipairs(commits) do
        for _, ref in ipairs(commit.refs) do
            if ref.kind == "head" then
                return index
            end
        end
    end

    return 1
end

--- Buffer row of a commit index. Skips description and file rows.
---
---@param state dagit.ViewState
---@param commit_index integer
---@return integer
local function commit_buffer_row(state, commit_index)
    for index, line in ipairs(state.lines) do
        if line.kind ~= "detail" and line.commit_index == commit_index then
            return index
        end
    end

    return 1
end

--- Commits the last draw indexed. Falls back to the full log before the first draw.
---
---@param state dagit.ViewState
---@return dagit.Commit[]
local function listed_commits(state)
    return state.shown or state.commits
end

--- Buffer row of the commit with `hash`, or nil when it is not loaded.
---
---@param state dagit.ViewState
---@param hash string?
---@return integer?
local function hash_buffer_row(state, hash)
    if not hash then
        return nil
    end

    local source = listed_commits(state)

    for index, line in ipairs(state.lines) do
        if line.kind ~= "detail" then
            local commit = source[line.commit_index]

            if commit and commit.hash == hash then
                return index
            end
        end
    end
end

---@param state dagit.ViewState
---@param at_head boolean? Place the highlight on the checked-out commit.
---@return boolean
local function reload(state, at_head)
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

    local win = vim.fn.bufwinid(state.buf)
    local keep_hash

    if win ~= -1 and not at_head then
        local cursor = vim.api.nvim_win_get_cursor(win)[1]
        local current = state.lines[cursor]
        local current_commit = current and listed_commits(state)[current.commit_index]

        keep_hash = current_commit and current_commit.hash
    end

    state.commits = commits
    draw(state)

    if win ~= -1 and #state.lines > 0 then
        local row

        if at_head then
            row = commit_buffer_row(state, checked_out_row(listed_commits(state)))
        else
            row = hash_buffer_row(state, keep_hash) or vim.api.nvim_win_get_cursor(win)[1]
        end

        row = math.max(1, math.min(row, #state.lines))
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

            return reload(state, true)
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
        expanded = {},
        details = {},
        filter = config.filter,
        shown = {},
    }

    hide_cursor()

    return reload(states[existing_buf], true)
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
    local line = states[buf].lines[row]

    if not line then
        return nil
    end

    return listed_commits(states[buf])[line.commit_index]
end

--- History state when the cursor is inside the history window.
---
--- A missing window warns. Another buffer returns nil without a warning.
---
---@return dagit.ViewState? state
---@return integer? win
local function active_state()
    local buf, win = find_window()

    if not buf or not win or not states[buf] then
        notify("Git history is not open", vim.log.levels.WARN)

        return nil
    end

    if vim.api.nvim_get_current_buf() ~= buf then
        return nil
    end

    return states[buf], win
end

--- Commit that owns the cursor row.
---
---@param state dagit.ViewState
---@param win integer
---@return dagit.Commit?
local function commit_at_cursor(state, win)
    local row = vim.api.nvim_win_get_cursor(win)[1]
    local line = state.lines[row]

    return line and listed_commits(state)[line.commit_index]
end

--- Move the filter by `direction` and keep the cursor commit when it stays visible.
---
---@param direction integer
---@return string?
local function cycle_filter(direction)
    local state, win = active_state()

    if not state or not win then
        return nil
    end

    local current = commit_at_cursor(state, win)
    local keep = current and current.hash

    state.filter = step_filter(state.filter or "all", direction)
    draw(state)

    if #state.lines > 0 then
        local row = hash_buffer_row(state, keep) or 1

        row = math.max(1, math.min(row, #state.lines))
        vim.api.nvim_win_set_cursor(win, { row, 0 })
        select_row(state, row)
    end

    return state.filter
end

--- Select the next commit filter.
---
---@return string?
function M.filter_next()
    return cycle_filter(1)
end

--- Select the previous commit filter.
---
---@return string?
function M.filter_prev()
    return cycle_filter(-1)
end

--- Read the description and files once per hash.
---
---@param state dagit.ViewState
---@param hash string
---@return dagit.CommitDetail?
local function load_detail(state, hash)
    local detail = state.details[hash]

    if detail then
        return detail
    end

    local fetched, err = git.changes(configuration.resolve().git_cmd, state.cwd, hash)

    if not fetched then
        notify(err or "Could not read the commit", vim.log.levels.ERROR)

        return nil
    end

    state.details[hash] = fetched

    return fetched
end

--- Redraw and leave the cursor on the commit row for `hash`.
---
---@param state dagit.ViewState
---@param win integer
---@param hash string?
local function reveal(state, win, hash)
    draw(state)

    local focus = hash_buffer_row(state, hash) or 1

    vim.api.nvim_win_set_cursor(win, { focus, 0 })
    select_row(state, focus)
end

--- Open the description and files for `hash` when they are not already open.
---
---@param state dagit.ViewState
---@param win integer
---@param hash string
---@return boolean
local function open_hash(state, win, hash)
    if state.expanded[hash] then
        return true
    end

    local detail = load_detail(state, hash)

    if not detail then
        return false
    end

    if #detail.body == 0 and #detail.files == 0 then
        return true
    end

    state.expanded[hash] = true
    reveal(state, win, hash)

    return true
end

--- Show or hide the description and files under the cursor commit.
---
---@return boolean
function M.expand()
    local state, win = active_state()

    if not state or not win then
        return false
    end

    local commit = commit_at_cursor(state, win)

    if not commit then
        notify("No commit under the cursor", vim.log.levels.WARN)

        return false
    end

    if state.expanded[commit.hash] then
        state.expanded[commit.hash] = nil
        reveal(state, win, commit.hash)

        return true
    end

    return open_hash(state, win, commit.hash)
end

--- Show or hide the description and files under the cursor commit.
---
---@return boolean
function M.show()
    return M.expand()
end

--- Hide the description and files under every commit.
---
---@return boolean
function M.collapse()
    local state, win = active_state()

    if not state or not win then
        return false
    end

    if not next(state.expanded) then
        return true
    end

    local commit = commit_at_cursor(state, win)

    state.expanded = {}
    reveal(state, win, commit and commit.hash)

    return true
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
