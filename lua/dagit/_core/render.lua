--- Turn commits into buffer lines and highlight spans.
---
--- Each row is `  graph hash HEAD branch subject`. The first cell is a
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
---@field span_marks { id: integer, start: integer, stop: integer, group: string, overlay: integer? }[]?
---@field detail_mark integer?
---@field commit_index integer
---@field kind "commit" | "detail"?
---@field graph_below string Marker column, continuing lanes, and the gap before the text.
---@field graph_below_spans dagit.HighlightSpan[]
---@field above_lines? string[][][] Virt lines above a commit where a branch joins the line.
---@field remote_only boolean? Commit is not on a local branch. Detail text is muted.

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

--- True when an |os.date()| format already prints a year.
---
---@param format string
---@return boolean
local function format_has_year(format)
    -- `%%` is a literal percent. `%F` is `%Y-%m-%d` and `%D` is `%m/%d/%y`.
    local stripped = format:gsub("%%%%", "\0\0")

    return stripped:find("%%[YyGgCcxDF]") ~= nil or stripped:find("%%%+") ~= nil
end

--- Print the year for a commit from another year.
---
--- The current year is left off. A format that already prints a year is
--- unchanged. The year is placed just before the clock.
---
---@param format string
---@param year integer
---@param now integer?
---@return string
local function with_year(format, year, now)
    if format_has_year(format) then
        return format
    end

    local today = os.date("*t", now or os.time())

    if year == today.year then
        return format
    end

    local stripped = format:gsub("%%%%", "\0\0")
    local at = stripped:find("%%[HIMSpRrTXc]") or stripped:find("%%%+")

    if not at then
        return format .. " %Y"
    end

    local prefix = format:sub(1, at - 1)

    if prefix:sub(-1) ~= " " then
        prefix = prefix .. " "
    end

    return prefix .. "%Y " .. format:sub(at)
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

    format = with_year(format, tonumber(year), now)

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

---@param color integer
---@param muted boolean?
---@return string
local function graph_group(color, muted)
    local name = "DagitGraph" .. color

    if muted then
        return name .. "Muted"
    end

    return name
end

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

--- Fade a text group on a commit that is not on a local branch.
---
---@param group string
---@param remote boolean
---@return string
local function quiet(group, remote)
    if remote and group ~= "DagitHead" and group ~= "DagitHeadMark" and group ~= "DagitUpstreamGone" and not group:find("Muted$") then
        return group .. "Muted"
    end

    return group
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

--- Shown after a local branch whose upstream ref no longer exists.
--- The leading space keeps the branch badge from touching the parenthesis.
local UPSTREAM_GONE = " (upstream gone)"

-- One space on each side of the word, so the reversed fill reads as a badge.
local HEAD_MARK = " HEAD "

-- Piece group replaced with the lane's reversed badge, `DagitGraphNRev`.
local BRANCH_MARK = "DagitBranchMark"

--- Lower sorts first beside the HEAD badge.
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

--- `HEAD branch …` pieces that fit in `config.ref_max_width`.
---
--- Tags are drawn on the right, not here. Head, local branches, and remotes
--- are kept in that order. Each branch name is its own reversed badge, with
--- a space on each side, and a plain space sits between badges. A detached
--- HEAD is the badge alone. `(upstream gone)` stays after that branch.
--- Names that do not fit are dropped from the end and then truncated. The
--- badges, the gaps, and `(upstream gone)` count toward the width.
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

    ---@type { text: string, kind: string, name: string, upstream_gone: boolean }[]
    local items = {}

    for _, entry in ipairs(primary) do
        local text = decorate(entry.ref.name, entry.ref.kind, config.icons)
        items[#items + 1] = {
            text = text,
            kind = entry.ref.kind,
            name = entry.ref.name,
            upstream_gone = entry.ref.upstream_gone == true,
        }
    end

    if #items == 0 then
        return {}
    end

    local function detached(item)
        return item.kind == "head" and item.name == "HEAD"
    end

    --- Branch names drawn as badges. Detached HEAD has none.
    ---
    ---@param list { text: string, upstream_gone: boolean, kind: string, name: string }[]
    ---@return { text: string, kind: string, name: string, upstream_gone: boolean }[]
    local function names_of(list)
        local names = {}

        for _, item in ipairs(list) do
            if not detached(item) then
                names[#names + 1] = item
            end
        end

        return names
    end

    local function has_badge(list)
        for _, item in ipairs(list) do
            if item.kind == "head" then
                return true
            end
        end

        return false
    end

    local function measure(list)
        local names = names_of(list)
        local width = 0

        if has_badge(list) then
            width = width + #HEAD_MARK
        end

        if #names == 0 then
            return width
        end

        -- Plain cell between the HEAD badge and the first name.
        if has_badge(list) then
            width = width + 1
        end

        for index, item in ipairs(names) do
            if index > 1 then
                width = width + 1
            end

            -- A space on each side, so the reversed fill reads as a badge.
            width = width + vim.api.nvim_strwidth(item.text) + 2

            if item.upstream_gone then
                width = width + vim.api.nvim_strwidth(UPSTREAM_GONE)
            end
        end

        return width
    end

    while #items > 1 and measure(items) > config.ref_max_width do
        table.remove(items)
    end

    local names = names_of(items)
    local overflow = measure(items) - config.ref_max_width

    if overflow > 0 and #names > 0 then
        local last = names[#names]
        local allowed = math.max(1, vim.api.nvim_strwidth(last.text) - overflow)
        last.text = M.truncate(last.text, allowed)
    end

    local pieces = {}

    if has_badge(items) then
        pieces[#pieces + 1] = { text = HEAD_MARK, group = "DagitHeadMark" }
    end

    if #names == 0 then
        return pieces
    end

    -- A plain cell between badges, so the reversed fills do not touch.
    if has_badge(items) then
        pieces[#pieces + 1] = { text = " ", group = "DagitPad" }
    end

    for index, item in ipairs(names) do
        if index > 1 then
            pieces[#pieces + 1] = { text = " ", group = "DagitPad" }
        end

        pieces[#pieces + 1] = { text = " " .. item.text .. " ", group = BRANCH_MARK }

        if item.upstream_gone then
            pieces[#pieces + 1] = { text = UPSTREAM_GONE, group = "DagitUpstreamGone" }
        end
    end

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

        for _, connector in ipairs(row.above or {}) do
            graph_width = math.max(graph_width, vim.api.nvim_strwidth(connector.text))
        end
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
        local remote = commit.remote_only == true
        local hash_group = commit.local_only and "DagitHashLocal" or "DagitHash"

        spans[#spans + 1] = {
            start = hash_start,
            stop = #text,
            group = marked(quiet(hash_group, remote), head),
        }

        for _, span in ipairs(row.spans) do
            spans[#spans + 1] = {
                start = span.start + #MARK,
                stop = span.stop + #MARK,
                group = marked(graph_group(span.color, span.muted), head),
            }
        end

        -- The branch badge fills with the lane color, so it matches the graph.
        local lane_group = graph_group(row.color, row.muted)
        local pieces = M.decoration(commit.refs, config)

        if #pieces > 0 then
            text = text .. " "

            for _, piece in ipairs(pieces) do
                if piece.group == BRANCH_MARK then
                    piece.group = lane_group .. "Rev"
                elseif piece.group ~= "DagitPad" then
                    piece.group = quiet(piece.group, remote)
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
                group = marked(quiet("DagitMerge", remote), head),
            }
        elseif head then
            spans[#spans + 1] = {
                start = subject_start,
                stop = #text,
                group = "DagitHead",
            }
        elseif remote then
            spans[#spans + 1] = {
                start = subject_start,
                stop = #text,
                group = "DagitTextMuted",
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
                virt[#virt + 1] = { text = label.text, group = marked(quiet(label.group, remote), head) }
            end

            virt[#virt + 1] = { text = "  ", group = "DagitPad" }
        end

        virt[#virt + 1] = {
            text = pad(authors[index], author_width, "left"),
            group = marked(quiet("DagitAuthor", remote), head),
        }
        virt[#virt + 1] = { text = "  ", group = "DagitPad" }
        virt[#virt + 1] = {
            text = pad(dates[index], date_width, "right"),
            group = marked(quiet("DagitDate", remote), head),
        }

        local below_pad = math.max(0, graph_width - vim.api.nvim_strwidth(row.below))
        local graph_below = MARK .. row.below .. string.rep(" ", below_pad)
        local below_spans = {}

        for _, span in ipairs(row.below_spans) do
            below_spans[#below_spans + 1] = {
                start = span.start + #MARK,
                stop = span.stop + #MARK,
                group = graph_group(span.color, span.muted),
            }
        end

        if graph_text ~= "" then
            graph_below = graph_below .. " "
        end

        local above_lines = nil

        if row.above and #row.above > 0 then
            above_lines = {}

            for _, connector in ipairs(row.above) do
                local padded = connector.text .. string.rep(" ", graph_width - vim.api.nvim_strwidth(connector.text))
                local chunks = { { MARK, "DagitPad" } }
                local cursor = 0

                for _, span in ipairs(connector.spans) do
                    if span.start > cursor then
                        chunks[#chunks + 1] = { padded:sub(cursor + 1, span.start), "DagitPad" }
                    end

                    chunks[#chunks + 1] = {
                        padded:sub(span.start + 1, span.stop),
                        graph_group(span.color, span.muted),
                    }
                    cursor = span.stop
                end

                if cursor < #padded then
                    chunks[#chunks + 1] = { padded:sub(cursor + 1), "DagitPad" }
                end

                above_lines[#above_lines + 1] = chunks
            end
        end

        lines[index] = {
            text = text,
            node_start = row.node_start + #MARK,
            node_length = row.node_length,
            node_group = marked(graph_group(row.color, row.muted), head),
            spans = spans,
            virt = virt,
            commit_index = index,
            graph_below = graph_below,
            graph_below_spans = below_spans,
            above_lines = above_lines,
            remote_only = remote,
        }
    end

    return lines
end

local FILE_GROUP = {
    A = "DagitFileAdded",
    M = "DagitFileModified",
    D = "DagitFileDeleted",
    R = "DagitFileRenamed",
    C = "DagitFileRenamed",
    T = "DagitFileModified",
}

--- `M path`, or `R old -> new` when Git recorded a rename or a copy.
---
---@param file dagit.CommitFile
---@return string
function M.file_text(file)
    local status = file.status or "?"

    if file.old_path and file.old_path ~= "" and file.old_path ~= file.path then
        return status .. " " .. file.old_path .. " -> " .. file.path
    end

    return status .. " " .. file.path
end

--- Spaces before the description and the file paths. The graph stays put.
local DETAIL_INDENT = "  "

--- File-count words, in the order the summary prints them.
local FILE_SUMMARY = {
    { status = "A", label = "added", group = "DagitFileAdded" },
    { status = "M", label = "modified", group = "DagitFileModified" },
    { status = "R", label = "renamed", group = "DagitFileRenamed" },
    { status = "D", label = "deleted", group = "DagitFileDeleted" },
    { status = "C", label = "copied", group = "DagitFileRenamed" },
    { status = "T", label = "type changed", group = "DagitFileModified" },
}

--- `3 added, 1 modified` when a commit changes more than five files.
---
--- Zero counts are left out. The parts keep the status color.
---
---@param files dagit.CommitFile[]
---@return string[][]?
function M.file_summary(files)
    if #files <= 5 then
        return nil
    end

    local known = {}

    for _, item in ipairs(FILE_SUMMARY) do
        known[item.status] = true
    end

    local counts = {}
    local other = 0

    for _, file in ipairs(files) do
        local status = file.status or "?"

        if known[status] then
            counts[status] = (counts[status] or 0) + 1
        else
            other = other + 1
        end
    end

    local parts = {}

    local function add(text, group)
        if #parts > 0 then
            parts[#parts + 1] = { ", ", "DagitBody" }
        end

        parts[#parts + 1] = { text, group }
    end

    for _, item in ipairs(FILE_SUMMARY) do
        local count = counts[item.status] or 0

        if count > 0 then
            add(count .. " " .. item.label, item.group)
        end
    end

    if other > 0 then
        add(other .. " changed", "DagitFileModified")
    end

    if #parts == 0 then
        return nil
    end

    return parts
end

--- Virtual lines under an expanded commit.
---
--- More than five files start with a count. The description comes next.
--- File rows follow, colored by status. A commit that is not local uses
--- the muted copy of those colors. Each line repeats the graph lanes
--- that continue past the commit, then the indent.
---
---@param line dagit.RenderedLine
---@param detail dagit.CommitDetail
---@return string[][]
function M.detail_virt_lines(line, detail)
    local prefix = {}
    local text = line.graph_below or ""
    local cursor = 0

    for _, span in ipairs(line.graph_below_spans or {}) do
        if span.start > cursor then
            prefix[#prefix + 1] = { text:sub(cursor + 1, span.start), "DagitPad" }
        end

        prefix[#prefix + 1] = { text:sub(span.start + 1, span.stop), span.group }
        cursor = span.stop
    end

    if cursor < #text then
        prefix[#prefix + 1] = { text:sub(cursor + 1), "DagitPad" }
    end

    local function row(content, group)
        local chunks = {}

        for _, chunk in ipairs(prefix) do
            chunks[#chunks + 1] = { chunk[1], chunk[2] }
        end

        if content ~= "" then
            chunks[#chunks + 1] = { DETAIL_INDENT .. content, group }
        end

        return chunks
    end

    local function row_parts(parts)
        local chunks = {}

        for _, chunk in ipairs(prefix) do
            chunks[#chunks + 1] = { chunk[1], chunk[2] }
        end

        for index, part in ipairs(parts) do
            local text = part[1]

            if index == 1 then
                text = DETAIL_INDENT .. text
            end

            chunks[#chunks + 1] = { text, part[2] }
        end

        return chunks
    end

    local virt_lines = {}
    local body = detail.body or {}
    local files = detail.files or {}
    local summary = M.file_summary(files)
    local remote = line.remote_only == true

    local function tone(group)
        return quiet(group, remote)
    end

    if summary then
        local parts = {}

        for _, part in ipairs(summary) do
            parts[#parts + 1] = { part[1], tone(part[2]) }
        end

        virt_lines[#virt_lines + 1] = row_parts(parts)
    end

    for _, line_text in ipairs(body) do
        virt_lines[#virt_lines + 1] = row(line_text, tone("DagitBody"))
    end

    if (summary or #body > 0) and #files > 0 then
        virt_lines[#virt_lines + 1] = row("", "DagitPad")
    end

    for _, file in ipairs(files) do
        virt_lines[#virt_lines + 1] = row(M.file_text(file), tone(FILE_GROUP[file.status] or "DagitFileModified"))
    end

    return virt_lines
end

--- Buffer rows for an expanded commit. The cursor can move through them.
---
---@param line dagit.RenderedLine
---@param detail dagit.CommitDetail
---@return dagit.RenderedLine[]
function M.detail_lines(line, detail)
    local rows = {}

    for _, chunks in ipairs(M.detail_virt_lines(line, detail)) do
        local parts = {}
        local spans = {}
        local byte = 0

        for _, chunk in ipairs(chunks) do
            local text = chunk[1]

            if text ~= "" then
                local start_byte = byte
                parts[#parts + 1] = text
                byte = byte + #text

                if chunk[2] ~= "DagitPad" then
                    spans[#spans + 1] = {
                        start = start_byte,
                        stop = byte,
                        group = chunk[2],
                    }
                end
            end
        end

        rows[#rows + 1] = {
            text = table.concat(parts),
            node_start = 0,
            node_length = 0,
            node_group = "DagitGraph1",
            spans = spans,
            virt = {},
            commit_index = line.commit_index,
            kind = "detail",
        }
    end

    return rows
end

return M
