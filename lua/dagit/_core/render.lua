--- Turn commits into buffer lines and highlight spans.
---
--- Each row is `  graph hash (HEAD -> branch) subject`. The first cell is a
--- blank the view replaces with `>` on the highlighted row. Tags, the author,
--- and the date stay right-aligned so they pin to the window edge.

local graph = require("dagit._core.graph")

local M = {}

---@class dagit.HighlightSpan
---@field start integer
---@field stop integer
---@field group string

---@class dagit.VirtChunk
---@field text string
---@field group string

---@class dagit.RenderedLine
---@field text string
---@field node_start integer
---@field node_length integer
---@field node_group string
---@field spans dagit.HighlightSpan[]
---@field virt dagit.VirtChunk[]
---@field virt_mark integer?
---@field span_marks { id: integer, start: integer, stop: integer, group: string }[]?
---@field commit_index integer

--- True when an |os.date()| format already prints a clock.
---
---@param format string
---@return boolean
local function format_has_time(format)
    -- `%%` is a literal percent. `%+` is the implementation-defined date and time.
    return format:find("%%[HIMSpRrTXc]") ~= nil or format:find("%%%+") ~= nil
end

--- Keep a date-only format, and put `HH:MM` after it.
---
--- `date_format` can be `"%d %b"` from an older config. The history still
--- shows the clock beside that date.
---
---@param format string
---@return string
local function with_clock(format)
    if format == "relative" or format_has_time(format) then
        return format
    end

    return format .. " %H:%M"
end

---@param timestamp string
---@param format string
---@param now integer?
---@return string
function M.format_date(timestamp, format, now)
    local year, month, day, hour, minute, second = timestamp:match("^(%d+)%-(%d+)%-(%d+)T(%d+):(%d+):(%d+)")

    if not year then
        return timestamp
    end

    local instant = os.time({
        year = tonumber(year),
        month = tonumber(month),
        day = tonumber(day),
        hour = tonumber(hour),
        min = tonumber(minute),
        sec = tonumber(second),
    })

    if format == "relative" then
        local delta = math.max(0, (now or os.time()) - instant)

        if delta < 60 then
            return "just now"
        elseif delta < 3600 then
            return string.format("%dm ago", math.floor(delta / 60))
        elseif delta < 86400 then
            return string.format("%dh ago", math.floor(delta / 3600))
        elseif delta < 86400 * 14 then
            return string.format("%dd ago", math.floor(delta / 86400))
        end

        format = "%d %b %H:%M"
    end

    local ok, formatted = pcall(os.date, format, instant)

    if not ok or type(formatted) ~= "string" then
        return timestamp
    end

    return formatted
end

--- Shorten `text` so its display width is at most `max_width`.
---
---@param text string
---@param max_width integer
---@return string
function M.truncate(text, max_width)
    if vim.api.nvim_strwidth(text) <= max_width then
        return text
    end

    local limit = math.max(1, max_width - 1)
    local result = {}
    local width = 0

    for char in text:gmatch("[%z\1-\127\194-\244][\128-\191]*") do
        local char_width = vim.api.nvim_strwidth(char)

        if width + char_width > limit then
            break
        end

        result[#result + 1] = char
        width = width + char_width
    end

    return table.concat(result) .. "…"
end

---@param text string
---@param width integer
---@param align "left" | "right"
---@return string
local function pad(text, width, align)
    local gap = math.max(0, width - vim.api.nvim_strwidth(text))
    local spaces = string.rep(" ", gap)

    if align == "right" then
        return spaces .. text
    end

    return text .. spaces
end

local REF_GROUP = {
    head = "DagitRefHead",
    branch = "DagitRefBranch",
    remote = "DagitRefRemote",
    tag = "DagitRefTag",
}

-- Two cells so the graph stays aligned. The view draws `>` in the first cell
-- of the highlighted row and leaves a space everywhere else.
local MARK = "  "

-- Shown in the row. `<C-o>` still copies the full hash.
local HASH_LENGTH = 7

---@param commit dagit.Commit
---@return boolean
local function is_head(commit)
    for _, ref in ipairs(commit.refs or {}) do
        if ref.kind == "head" then
            return true
        end
    end

    return false
end

---@param group string
---@param head boolean
---@return string
local function marked(group, head)
    -- `DagitHead` is already bold. A second Bold copy is not defined.
    if head and group ~= "DagitPad" and group ~= "DagitHead" then
        return group .. "Bold"
    end

    return group
end

---@param hash string
---@return string
local function short_hash(hash)
    if #hash <= HASH_LENGTH then
        return hash
    end

    return hash:sub(1, HASH_LENGTH)
end

--- Lower sorts first inside `(HEAD -> branch)`.
local REF_PRIORITY = {
    head = 1,
    branch = 2,
    remote = 3,
}

---@param name string
---@param kind string
---@param icons dagit.Icons
---@return string text
---@return string group
local function decorate(name, kind, icons)
    local icon = ""

    if icons.enabled then
        local glyph = icons[kind] or ""

        if glyph ~= "" then
            icon = glyph .. " "
        end
    end

    return icon .. name, REF_GROUP[kind] or "DagitRefBranch"
end

--- `(HEAD -> branch, …)` pieces that fit in `config.ref_max_width`.
---
--- Tags are drawn on the right, not here. Head, local branches, and remotes
--- are kept in that order. Names that do not fit are dropped from the end
--- and then truncated. The parentheses count toward the width.
---
---@param refs dagit.Ref[]
---@param config dagit.Config
---@return { text: string, group: string }[]
function M.decoration(refs, config)
    local primary = {}

    for index, ref in ipairs(refs or {}) do
        if ref.kind ~= "tag" then
            primary[#primary + 1] = { ref = ref, index = index }
        end
    end

    table.sort(primary, function(left, right)
        local left_priority = REF_PRIORITY[left.ref.kind] or 9
        local right_priority = REF_PRIORITY[right.ref.kind] or 9

        if left_priority ~= right_priority then
            return left_priority < right_priority
        end

        return left.index < right.index
    end)

    ---@type { text: string, group: string, kind: string, name: string }[]
    local items = {}

    for _, entry in ipairs(primary) do
        local text, group = decorate(entry.ref.name, entry.ref.kind, config.icons)
        items[#items + 1] = { text = text, group = group, kind = entry.ref.kind, name = entry.ref.name }
    end

    if #items == 0 then
        return {}
    end

    local function pointer(item)
        return item.kind == "head" and item.name ~= "HEAD"
    end

    local function measure(list)
        -- Parentheses, plus ", " between names, plus "HEAD -> " on the branch HEAD points at.
        local width = 2

        for index, item in ipairs(list) do
            if index > 1 then
                width = width + 2
            end

            if pointer(item) then
                width = width + #"HEAD -> "
            end

            width = width + vim.api.nvim_strwidth(item.text)
        end

        return width
    end

    while #items > 1 and measure(items) > config.ref_max_width do
        table.remove(items)
    end

    local overflow = measure(items) - config.ref_max_width

    if overflow > 0 then
        local last = items[#items]
        local allowed = math.max(1, vim.api.nvim_strwidth(last.text) - overflow)
        last.text = M.truncate(last.text, allowed)
    end

    local pieces = { { text = "(", group = "DagitDecor" } }

    for index, item in ipairs(items) do
        if index > 1 then
            pieces[#pieces + 1] = { text = ", ", group = "DagitDecor" }
        end

        if pointer(item) then
            pieces[#pieces + 1] = { text = "HEAD -> ", group = "DagitHead" }
        end

        pieces[#pieces + 1] = { text = item.text, group = item.group }
    end

    pieces[#pieces + 1] = { text = ")", group = "DagitDecor" }
    return pieces
end

--- The tag drawn on the right, or nil when the commit has none.
---
--- More than one tag is replaced by `multi_tag_label`. The label is truncated
--- to `config.ref_max_width`.
---
---@param refs dagit.Ref[]
---@param config dagit.Config
---@return { text: string, group: string }?
function M.tag_label(refs, config)
    local tags = {}

    for _, ref in ipairs(refs or {}) do
        if ref.kind == "tag" then
            tags[#tags + 1] = ref
        end
    end

    if #tags == 0 then
        return nil
    end

    local text, group

    if #tags == 1 then
        text, group = decorate(tags[1].name, "tag", config.icons)
    else
        text, group = decorate(config.multi_tag_label, "tag", config.icons)
    end

    return { text = M.truncate(text, config.ref_max_width), group = group }
end

---@param commits dagit.Commit[]
---@param config dagit.Config
---@return dagit.RenderedLine[]
function M.build(commits, config)
    local layout = graph.layout(commits, config.symbols)
    local graph_width = 0

    for _, row in ipairs(layout) do
        graph_width = math.max(graph_width, vim.api.nvim_strwidth(row.text))
    end

    local dates = {}
    local authors = {}
    local tags = {}
    local tag_width = 0

    for index, commit in ipairs(commits) do
        dates[index] = M.format_date(commit.timestamp, with_clock(config.date_format))
        authors[index] = M.truncate(commit.author, config.author_max_width)
        tags[index] = M.tag_label(commit.refs, config)

        if tags[index] then
            tag_width = math.max(tag_width, vim.api.nvim_strwidth(tags[index].text))
        end
    end

    local author_width = 0
    local date_width = 0

    for index = 1, #commits do
        author_width = math.max(author_width, vim.api.nvim_strwidth(authors[index]))
        date_width = math.max(date_width, vim.api.nvim_strwidth(dates[index]))
    end

    local lines = {}

    for index, commit in ipairs(commits) do
        local row = layout[index]
        local head = is_head(commit)
        local graph_text = row.text .. string.rep(" ", graph_width - vim.api.nvim_strwidth(row.text))
        local text = MARK .. graph_text

        if graph_text ~= "" then
            text = text .. " "
        end

        local hash_text = short_hash(commit.hash)
        local hash_start = #text
        text = text .. hash_text

        local spans = {}

        spans[#spans + 1] = {
            start = hash_start,
            stop = #text,
            group = marked("DagitHash", head),
        }

        for _, span in ipairs(row.spans) do
            spans[#spans + 1] = {
                start = span.start + #MARK,
                stop = span.stop + #MARK,
                group = marked("DagitGraph" .. span.color, head),
            }
        end

        -- The branch name uses the lane color, so it matches the graph.
        local lane_group = "DagitGraph" .. row.color
        local pieces = M.decoration(commit.refs, config)

        if #pieces > 0 then
            text = text .. " "

            for _, piece in ipairs(pieces) do
                local fixed = piece.group == "DagitHead" or piece.group == "DagitDecor"

                if not fixed then
                    piece.group = lane_group
                end

                local start = #text
                text = text .. piece.text
                spans[#spans + 1] = {
                    start = start,
                    stop = #text,
                    group = marked(piece.group, head),
                }
            end
        end

        text = text .. " "
        local subject_start = #text
        text = text .. commit.subject

        local merge = config.dim_merges and #commit.parents > 1

        if merge then
            spans[#spans + 1] = {
                start = subject_start,
                stop = #text,
                group = marked("DagitMerge", head),
            }
        elseif head then
            spans[#spans + 1] = {
                start = subject_start,
                stop = #text,
                group = "DagitHead",
            }
        end

        local virt = {}

        if tag_width > 0 then
            local label = tags[index]
            local label_text = label and label.text or ""
            local gap = tag_width - vim.api.nvim_strwidth(label_text)

            if gap > 0 then
                virt[#virt + 1] = { text = string.rep(" ", gap), group = "DagitPad" }
            end

            if label then
                virt[#virt + 1] = { text = label.text, group = marked(label.group, head) }
            end

            virt[#virt + 1] = { text = "  ", group = "DagitPad" }
        end

        virt[#virt + 1] = { text = pad(authors[index], author_width, "left"), group = marked("DagitAuthor", head) }
        virt[#virt + 1] = { text = "  ", group = "DagitPad" }
        virt[#virt + 1] = { text = pad(dates[index], date_width, "right"), group = marked("DagitDate", head) }

        lines[index] = {
            text = text,
            node_start = row.node_start + #MARK,
            node_length = row.node_length,
            node_group = marked("DagitGraph" .. row.color, head),
            spans = spans,
            virt = virt,
            commit_index = index,
        }
    end

    return lines
end

return M
