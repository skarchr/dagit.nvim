--- Compact commit graph.
---
--- Each commit is one row. The first parent keeps the current lane, which
--- draws the main line straight down. Extra parents open a lane to the right.
--- The commit glyph carries the vertical stroke and is drawn to the cell
--- edge, so a straight lane meets the next row.
--- When two lanes would continue into the same commit, the left lane stays
--- and the other lane draws a merge into it.

local M = {}

local PALETTE = 8

---@class dagit.GraphSpan
---@field start integer Zero-based byte offset.
---@field stop integer End byte, exclusive.
---@field color integer Palette index, starting at 1.

---@class dagit.GraphRow
---@field text string
---@field node_start integer
---@field node_length integer
---@field color integer
---@field spans dagit.GraphSpan[]

---@param symbols dagit.Symbols
---@return string[]
local function symbol_issues(symbols)
    if type(symbols) ~= "table" then
        return { "symbols table is required" }
    end

    return {}
end

--- Draw `commits` from newest to oldest.
---
---@param commits { hash: string, parents: string[] }[]
---@param symbols dagit.Symbols
---@return dagit.GraphRow[]
function M.layout(commits, symbols)
    if #symbol_issues(symbols) > 0 then
        return {}
    end

    ---@type { hash: string, color: integer }[]
    local lanes = {}
    local next_color = 1
    local rows = {}

    local function allocate()
        local color = next_color
        next_color = next_color % PALETTE + 1

        return color
    end

    local function find(list, hash, skip)
        for index, lane in ipairs(list) do
            if lane and lane.hash == hash and index ~= skip then
                return index
            end
        end
    end

    for _, commit in ipairs(commits) do
        local parents = commit.parents or {}
        local idx = find(lanes, commit.hash)
        -- A lane that already holds this hash drew a line down to it.
        local continues_up = idx ~= nil

        if not idx then
            idx = #lanes + 1
            lanes[idx] = { hash = commit.hash, color = allocate() }
        end

        local color = lanes[idx].color
        local new_lanes = {}

        for index, lane in ipairs(lanes) do
            new_lanes[index] = { hash = lane.hash, color = lane.color }
        end

        ---@type table<integer, integer>
        local introduced = {}
        ---@type table<integer, integer>
        local dropped = {}
        ---@type table<integer, boolean>
        local linked = {}

        if #parents == 0 then
            new_lanes[idx] = false
        else
            new_lanes[idx] = { hash = parents[1], color = color }

            -- Insert every missing parent before recording column indexes.
            -- `table.insert` shifts later lanes, so indexes are resolved once
            -- the row's lanes have stopped moving.
            local insert_at = idx + 1

            for parent_index = 2, #parents do
                local parent = parents[parent_index]

                if not find(new_lanes, parent) then
                    local lane = { hash = parent, color = allocate(), introduced = true }
                    table.insert(new_lanes, insert_at, lane)
                    insert_at = insert_at + 1
                end
            end

            for parent_index = 2, #parents do
                local at = find(new_lanes, parents[parent_index])

                if at and at ~= idx then
                    linked[at] = true
                end
            end
        end

        local seen = {}

        for index, lane in ipairs(new_lanes) do
            if lane then
                local keeper = seen[lane.hash]

                if keeper then
                    dropped[index] = lane.color
                    linked[index] = true
                    linked[keeper] = true
                    new_lanes[index] = false
                else
                    seen[lane.hash] = index
                end
            end
        end

        for index, lane in ipairs(new_lanes) do
            if lane and lane.introduced then
                introduced[index] = lane.color
            end
        end

        ---@type table<integer, boolean>
        local connect = {}

        for column, _ in pairs(linked) do
            if column ~= idx then
                local lo = math.min(idx, column)
                local hi = math.max(idx, column)

                for cursor = lo, hi - 1 do
                    connect[cursor] = true
                end
            end
        end

        -- After duplicate lanes collapse, a false entry means this column
        -- bends away instead of continuing downward through the circle.
        local continues_down = type(new_lanes[idx]) == "table"

        local function node_symbol()
            local symbol

            if continues_up and continues_down then
                symbol = symbols.commit_through
            elseif continues_down then
                symbol = symbols.commit_down
            elseif continues_up then
                symbol = symbols.commit_up
            end

            if type(symbol) ~= "string" or symbol == "" then
                return symbols.commit
            end

            return symbol
        end

        local pieces = {}
        local spans = {}
        local byte = 0
        local node_start = 0
        local node_length = #symbols.commit

        for index = 1, #new_lanes do
            local lane = new_lanes[index]
            local kind
            local piece_color = color

            if index == idx then
                kind = "commit"
            elseif introduced[index] and lane then
                kind = "branch_start"
                piece_color = lane.color
            elseif dropped[index] then
                kind = index > idx and "merge_right" or "merge_left"
                piece_color = dropped[index]
            elseif lane then
                kind = "pass"
                piece_color = lane.color
            else
                kind = "empty"
            end

            local symbol = " "

            if kind == "commit" then
                symbol = node_symbol()
                node_start = byte
                node_length = #symbol
            elseif kind == "pass" then
                symbol = symbols.vertical
            elseif kind == "branch_start" then
                symbol = symbols.branch_start
            elseif kind == "merge_right" then
                symbol = symbols.merge_right
            elseif kind == "merge_left" then
                symbol = symbols.merge_left
            end

            local link = connect[index] and symbols.horizontal or " "
            local link_color = piece_color
            local next_cell_color = nil

            if index < #new_lanes then
                if introduced[index + 1] then
                    next_cell_color = introduced[index + 1]
                elseif dropped[index + 1] then
                    next_cell_color = dropped[index + 1]
                elseif new_lanes[index + 1] then
                    next_cell_color = new_lanes[index + 1].color
                end
            end

            if connect[index] and next_cell_color then
                link_color = next_cell_color
            end

            local function append(text, glyph_color)
                if text == "" then
                    return
                end

                local start_byte = byte
                pieces[#pieces + 1] = text
                byte = byte + #text

                if text ~= " " and glyph_color > 0 then
                    spans[#spans + 1] = {
                        start = start_byte,
                        stop = byte,
                        color = glyph_color,
                    }
                end
            end

            append(symbol, piece_color)
            append(link, link_color)
        end

        local text = table.concat(pieces):gsub("%s+$", "")
        local compacted = {}

        for _, lane in ipairs(new_lanes) do
            if lane then
                compacted[#compacted + 1] = lane
            end
        end

        lanes = compacted
        rows[#rows + 1] = {
            text = text,
            node_start = node_start,
            node_length = node_length,
            color = color,
            spans = spans,
        }
    end

    return rows
end

return M
