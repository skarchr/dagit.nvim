--- Compact commit graph.
---
--- Each commit is one row. The first parent keeps the current lane, which
--- draws the main line straight down. Extra parents open a lane to the right.
--- The commit glyph carries the vertical stroke and is drawn to the cell
--- edge, so a straight lane meets the next row.
--- Lanes that lead to the same commit stay apart until that commit. The left
--- lane stays, and the others draw a line into it on that row. When this
--- commit has another parent, the cell beside the commit is an arrow pointing
--- at it. A parent lane that continues through the row draws a junction, so
--- the arrow meets the line. Where a branch is created, that cell stays a
--- plain line.
--- A child does not join early just because its parent is already another lane.
--- A lane keeps its column when a column to its left ends. The gap stays, so
--- the line does not jump. A new branch may start in that gap. A horizontal
--- that crosses the gap is drawn through it.
--- When a commit both merges a parent and is the parent of another branch,
--- the merged parent stays on the node. The other branch joins the line
--- above that node, so the two lines do not share a cell.

local M = {}

local PALETTE = 8

---@class dagit.GraphSpan
---@field start integer Zero-based byte offset.
---@field stop integer End byte, exclusive.
---@field color integer Palette index, starting at 1.
---@field muted boolean Lane belongs to a branch that is not local.

---@class dagit.GraphRow
---@field text string
---@field node_start integer
---@field node_length integer
---@field color integer
---@field muted boolean Commit node is on a branch that is not local.
---@field spans dagit.GraphSpan[]
---@field below string Vertical lanes that continue into the next row.
---@field below_spans dagit.GraphSpan[]
---@field above dagit.GraphConnector[] Lines drawn above the commit when a branch joins the line there.

---@class dagit.GraphConnector
---@field text string
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
--- A lane stays muted while it only carries commits that are not on a local
--- branch (`remote_only`). Reaching a commit that is on a local branch clears
--- the mute for that commit and the history below it.
---
---@param commits { hash: string, parents: string[], remote_only?: boolean }[]
---@param symbols dagit.Symbols
---@return dagit.GraphRow[]
function M.layout(commits, symbols)
    if #symbol_issues(symbols) > 0 then
        return {}
    end

    ---@type table<string, boolean>
    local remote_only = {}

    for _, commit in ipairs(commits) do
        if commit.remote_only then
            remote_only[commit.hash] = true
        end
    end

    ---@type { hash: string, color: integer, muted: boolean }[]
    local lanes = {}
    local next_color = 1
    local rows = {}

    -- A wider glyph would shift every lane, so it falls back to ASCII.
    -- A missing junction falls back to the plain vertical.
    local function single_cell(symbol, fallback)
        if type(symbol) == "string" and symbol ~= "" and vim.api.nvim_strwidth(symbol) == 1 then
            return symbol
        end

        return fallback
    end

    local arrow_right = single_cell(symbols.arrow_right, ">")
    local arrow_left = single_cell(symbols.arrow_left, "<")
    local join_right = single_cell(symbols.join_right, symbols.vertical)
    local join_left = single_cell(symbols.join_left, symbols.vertical)

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

    -- One elbow per target, nearest first. The line leaves `origin` and turns
    -- at `corner` in the target column. A column that already ended stays
    -- blank, so a later elbow does not paint across it.
    local function elbows(lanes, origin, targets, corner, color_at, muted_at)
        local revealed = {}

        for index, lane in ipairs(lanes) do
            if lane then
                revealed[index] = true
            end
        end

        local lines = {}
        local bar = (symbols.horizontal ~= nil and symbols.horizontal ~= "") and symbols.horizontal or "─"

        for _, target in ipairs(targets) do
            local from = origin

            if target > origin then
                for index = target - 1, origin, -1 do
                    if revealed[index] then
                        from = index
                        break
                    end
                end
            end

            local curve_color = color_at(target)
            local curve_muted = muted_at(target)
            local start_cell = (from - 1) * 2 + 1
            local corner_cell = (target - 1) * 2
            local pieces_at = {}
            local spans_at = {}
            local byte_at = 0

            local function append_at(piece, piece_color, piece_muted)
                if piece == "" then
                    return
                end

                local start_byte = byte_at
                pieces_at[#pieces_at + 1] = piece
                byte_at = byte_at + #piece

                if piece ~= " " and piece_color > 0 then
                    spans_at[#spans_at + 1] = {
                        start = start_byte,
                        stop = byte_at,
                        color = piece_color,
                        muted = piece_muted or false,
                    }
                end
            end

            local cell = 0

            for index = 1, #lanes do
                local glyph = " "
                local glyph_color = 0
                local glyph_muted = false
                local link = " "
                local link_color = 0
                local link_muted_cell = false
                local lane = lanes[index]

                if revealed[index] and type(lane) == "table" then
                    glyph = symbols.vertical
                    glyph_color = lane.color
                    glyph_muted = lane.muted == true
                end

                if cell == corner_cell then
                    glyph = corner
                    glyph_color = curve_color
                    glyph_muted = curve_muted
                elseif cell >= start_cell and cell < corner_cell then
                    glyph = bar
                    glyph_color = curve_color
                    glyph_muted = curve_muted
                end

                if cell + 1 >= start_cell and cell + 1 < corner_cell then
                    link = bar
                    link_color = curve_color
                    link_muted_cell = curve_muted
                end

                append_at(glyph, glyph_color, glyph_muted)
                append_at(link, link_color, link_muted_cell)
                cell = cell + 2
            end

            lines[#lines + 1] = {
                text = table.concat(pieces_at):gsub("%s+$", ""),
                spans = spans_at,
            }
        end

        return lines
    end

    for _, commit in ipairs(commits) do
        local parents = commit.parents or {}
        local arrivals = {}

        for index, lane in ipairs(lanes) do
            if lane and lane.hash == commit.hash then
                lane.arriving = true
                arrivals[#arrivals + 1] = index
            end
        end

        -- A lane that already holds this hash drew a line down to it.
        local continues_up = #arrivals > 0
        local idx = arrivals[1]

        if not idx then
            for index, lane in ipairs(lanes) do
                if not lane then
                    idx = index
                    break
                end
            end

            if not idx then
                idx = #lanes + 1
            end

            lanes[idx] = {
                hash = commit.hash,
                color = allocate(),
                muted = remote_only[commit.hash] == true,
            }
        elseif not remote_only[commit.hash] then
            lanes[idx].muted = false
        end

        local color = lanes[idx].color
        local muted = lanes[idx].muted
        local new_lanes = {}

        for index, lane in ipairs(lanes) do
            if lane then
                new_lanes[index] = {
                    hash = lane.hash,
                    color = lane.color,
                    muted = lane.muted,
                    arriving = lane.arriving,
                }
            else
                new_lanes[index] = false
            end
        end

        ---@type table<integer, integer>
        local introduced = {}
        ---@type table<integer, boolean>
        local introduced_muted = {}
        ---@type table<integer, integer>
        local dropped = {}
        ---@type table<integer, boolean>
        local dropped_muted = {}
        ---@type table<integer, boolean>
        local linked = {}

        local fresh = {}

        if #parents == 0 then
            new_lanes[idx] = false
        else
            new_lanes[idx] = { hash = parents[1], color = color, muted = muted }

            for parent_index = 2, #parents do
                local parent = parents[parent_index]

                if not find(new_lanes, parent) then
                    fresh[#fresh + 1] = {
                        hash = parent,
                        color = allocate(),
                        introduced = true,
                        muted = remote_only[parent] == true,
                    }
                end
            end
        end

        -- A lane that was waiting for this commit merges here. Record it
        -- before placing a new parent, so a parent opened on this row does
        -- not land on the cells the arrival is using.
        for index, lane in ipairs(new_lanes) do
            if lane and lane.arriving and index ~= idx then
                dropped[index] = lane.color
                dropped_muted[index] = lane.muted
                -- A new parent needs the cells beside the node. A branch that
                -- arrives on that side joins the line above the node instead.
                if not (index > idx and #fresh > 0) then
                    linked[index] = true
                    linked[idx] = true
                end
                new_lanes[index] = false
            end
        end

        local above = {}
        local deferred = {}

        for drop_at, _ in pairs(dropped) do
            if drop_at > idx and #fresh > 0 then
                deferred[#deferred + 1] = drop_at
            end
        end

        table.sort(deferred)

        if #deferred > 0 then
            -- The elbows above still use the arriving columns. The merged
            -- parent reuses the nearest of those columns, so a lane further
            -- to the right stays where the previous row drew it.
            above = elbows(new_lanes, idx, deferred, symbols.merge_right, function(column)
                return dropped[column] or color
            end, function(column)
                return dropped_muted[column] or false
            end)

            -- Those arrivals already joined the line above. A reused column
            -- is the merged parent, drawn from the node. An unused one stays
            -- blank so the node row does not draw the join a second time.
            for _, slot in ipairs(deferred) do
                dropped[slot] = nil
                dropped_muted[slot] = nil
            end

            local pending = {}
            local slot_at = 1

            for _, parent_lane in ipairs(fresh) do
                local slot = deferred[slot_at]

                if slot then
                    new_lanes[slot] = parent_lane
                    slot_at = slot_at + 1
                else
                    pending[#pending + 1] = parent_lane
                end
            end

            local function last_index(list)
                local last = 0

                for index, _ in ipairs(list) do
                    last = index
                end

                return last
            end

            for _, parent_lane in ipairs(pending) do
                local at = last_index(new_lanes) + 1
                new_lanes[at] = parent_lane
            end
        else
            -- Insert every missing parent before recording column indexes.
            -- `table.insert` shifts later lanes, so indexes are resolved once
            -- the row's lanes have stopped moving.
            local insert_at = idx + 1

            for _, parent_lane in ipairs(fresh) do
                table.insert(new_lanes, insert_at, parent_lane)
                insert_at = insert_at + 1
            end
        end

        ---@type table<integer, boolean>
        local merged_parent = {}

        for parent_index = 2, #parents do
            local at = find(new_lanes, parents[parent_index])

            if at and at ~= idx then
                linked[at] = true
                merged_parent[at] = true
            end
        end

        for index, lane in ipairs(new_lanes) do
            if lane and lane.introduced then
                introduced[index] = lane.color
                introduced_muted[index] = lane.muted
            end
        end

        ---@type table<integer, boolean>
        local connect = {}
        ---@type table<integer, integer>
        local link_colors = {}
        ---@type table<integer, boolean>
        local link_muted = {}
        ---@type table<integer, integer>
        local link_rank = {}
        ---@type table<integer, boolean>
        local link_merge = {}

        -- A branch keeps its own color while it crosses other lanes. The
        -- vertical it passes keeps that lane's color; only the horizontal
        -- span is the branch.
        local function endpoint_color(column)
            if dropped[column] then
                return dropped[column]
            end

            if dropped[idx] then
                return color
            end

            if introduced[column] then
                return introduced[column]
            end

            local lane = new_lanes[column]

            if type(lane) == "table" then
                return lane.color
            end

            return color
        end

        local function endpoint_muted(column)
            if dropped[column] then
                return dropped_muted[column] or false
            end

            if dropped[idx] then
                return muted
            end

            if introduced[column] then
                return introduced_muted[column] or false
            end

            local lane = new_lanes[column]

            if type(lane) == "table" then
                return lane.muted or false
            end

            return muted
        end

        for column, _ in pairs(linked) do
            if column ~= idx then
                local branch_color = endpoint_color(column)
                local branch_muted = endpoint_muted(column)
                local distance = math.abs(column - idx)
                local lo = math.min(idx, column)
                local hi = math.max(idx, column)

                for cursor = lo, hi - 1 do
                    connect[cursor] = true
                    local rank = link_rank[cursor]

                    -- The nearer branch owns a shared cell so an outer branch
                    -- does not repaint the inner one.
                    if not rank or distance < rank then
                        link_colors[cursor] = branch_color
                        link_muted[cursor] = branch_muted
                        link_rank[cursor] = distance
                        -- Only a parent of this commit gets an arrow. A lane
                        -- that arrives here is where a branch was created.
                        link_merge[cursor] = merged_parent[column] == true
                    end
                end
            end
        end

        -- A false entry means this column bends away instead of continuing
        -- downward through the circle.
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
            local piece_muted = muted

            if index == idx then
                kind = "commit"
            elseif dropped[index] then
                kind = index > idx and "merge_right" or "merge_left"
                piece_color = dropped[index]
                piece_muted = dropped_muted[index]
            elseif introduced[index] and lane then
                kind = "branch_start"
                piece_color = lane.color
                piece_muted = lane.muted
            elseif lane then
                kind = "pass"
                piece_color = lane.color
                piece_muted = lane.muted
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

                -- The lane keeps going up and down, and grows the bar the
                -- arrow connects to. A lane that starts or ends on this row
                -- already has that bar in its corner.
                if merged_parent[index] then
                    if index > idx then
                        symbol = join_left
                    elseif index < idx then
                        symbol = join_right
                    end
                end
            elseif kind == "branch_start" then
                symbol = symbols.branch_start
            elseif kind == "merge_right" then
                symbol = symbols.merge_right
            elseif kind == "merge_left" then
                symbol = symbols.merge_left
            end

            local link = " "

            if connect[index] then
                link = symbols.horizontal

                -- The head sits in the one cell that touches the commit.
                -- Further cells of the same span stay a plain bar.
                if link_merge[index] then
                    if index == idx then
                        link = arrow_left
                    elseif index + 1 == idx then
                        link = arrow_right
                    end
                end
            end
            local link_color = link_colors[index] or piece_color
            local glyph_link_muted = link_muted[index]

            if glyph_link_muted == nil then
                glyph_link_muted = piece_muted
            end

            -- An empty column between two linked lanes is part of the line.
            if kind == "empty" and connect[index] then
                symbol = symbols.horizontal
                piece_color = link_color
                piece_muted = glyph_link_muted
            end

            local function append(text, glyph_color, glyph_muted)
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
                        muted = glyph_muted or false,
                    }
                end
            end

            append(symbol, piece_color, piece_muted)
            append(link, link_color, glyph_link_muted)
        end

        local text = table.concat(pieces):gsub("%s+$", "")
        local last = 0

        for index, lane in ipairs(new_lanes) do
            if lane then
                last = index
            end
        end

        -- Drop columns only after the last live lane. A gap to the left of a
        -- lane stays, so that lane is still in the same column on the next row.
        local compacted = {}

        for index = 1, last do
            local lane = new_lanes[index]

            if lane then
                compacted[index] = {
                    hash = lane.hash,
                    color = lane.color,
                    muted = lane.muted,
                }
            else
                compacted[index] = false
            end
        end

        lanes = compacted

        -- Detail rows sit between this commit and the next one. They repeat
        -- the lanes that leave this row, so the graph does not break open.
        local below_pieces = {}
        local below_spans = {}
        local below_byte = 0

        local function append_below(piece, piece_color, piece_muted)
            if piece == "" then
                return
            end

            local start_byte = below_byte
            below_pieces[#below_pieces + 1] = piece
            below_byte = below_byte + #piece

            if piece ~= " " and piece_color > 0 then
                below_spans[#below_spans + 1] = {
                    start = start_byte,
                    stop = below_byte,
                    color = piece_color,
                    muted = piece_muted or false,
                }
            end
        end

        for index = 1, #compacted do
            local lane = compacted[index]

            if lane then
                append_below(symbols.vertical, lane.color, lane.muted == true)
            else
                append_below(" ", 0, false)
            end

            append_below(" ", 0, false)
        end

        rows[#rows + 1] = {
            text = text,
            node_start = node_start,
            node_length = node_length,
            color = color,
            muted = muted,
            spans = spans,
            below = table.concat(below_pieces):gsub("%s+$", ""),
            below_spans = below_spans,
            above = above,
        }
    end

    return rows
end

return M
