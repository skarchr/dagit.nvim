local configuration = require("dagit._core.configuration")
local graph = require("dagit._core.graph")

local symbols = configuration.defaults().symbols

local function texts(commits)
    local rows = graph.layout(commits, symbols)
    local lines = {}

    for index, row in ipairs(rows) do
        lines[index] = row.text
    end

    return lines
end

describe("graph.layout", function()
    it("draws a straight line for linear history", function()
        assert.same({
            symbols.commit_down,
            symbols.commit_through,
            symbols.commit_up,
        }, texts({
            { hash = "c3", parents = { "c2" } },
            { hash = "c2", parents = { "c1" } },
            { hash = "c1", parents = {} },
        }))
    end)

    it("records the lanes that continue below a commit", function()
        local linear = graph.layout({
            { hash = "c3", parents = { "c2" } },
            { hash = "c2", parents = { "c1" } },
            { hash = "c1", parents = {} },
        }, symbols)

        assert.equal(symbols.vertical, linear[1].below)
        assert.equal(symbols.vertical, linear[2].below)
        assert.equal("", linear[3].below)

        local branched = graph.layout({
            { hash = "M", parents = { "A", "B" } },
            { hash = "B", parents = { "A" } },
            { hash = "A", parents = {} },
        }, symbols)

        assert.equal(symbols.vertical .. " " .. symbols.vertical, branched[1].below)
        -- The branch stays in its column until the shared parent row.
        assert.equal(symbols.vertical .. " " .. symbols.vertical, branched[2].below)
        assert.equal("", branched[3].below)
    end)

    it("draws a branch to the right of a merge", function()
        assert.same({
            symbols.commit_down .. symbols.arrow_left .. symbols.branch_start,
            symbols.vertical .. " " .. symbols.commit_through,
            symbols.vertical .. " " .. symbols.commit_through,
            symbols.vertical .. " " .. symbols.commit_through,
            symbols.commit_through .. " " .. symbols.vertical,
            symbols.commit_up .. symbols.horizontal .. symbols.merge_right,
        }, texts({
            { hash = "M", parents = { "A", "B3" } },
            { hash = "B3", parents = { "B2" } },
            { hash = "B2", parents = { "B1" } },
            { hash = "B1", parents = { "C" } },
            { hash = "A", parents = { "C" } },
            { hash = "C", parents = {} },
        }))
    end)

    it("draws a one-commit branch merged back into its parent", function()
        assert.same({
            symbols.commit_down .. symbols.arrow_left .. symbols.branch_start,
            symbols.vertical .. " " .. symbols.commit_through,
            symbols.commit_up .. symbols.horizontal .. symbols.merge_right,
        }, texts({
            { hash = "M", parents = { "A", "B" } },
            { hash = "B", parents = { "A" } },
            { hash = "A", parents = {} },
        }))
    end)

    it("joins two tips into their common parent", function()
        assert.same({
            symbols.commit_down,
            symbols.vertical .. " " .. symbols.commit_down,
            symbols.commit_up .. symbols.horizontal .. symbols.merge_right,
        }, texts({
            { hash = "A", parents = { "C" } },
            { hash = "B", parents = { "C" } },
            { hash = "C", parents = {} },
        }))
    end)

    it("keeps a lane in its column when a column to its left closes", function()
        assert.same({
            symbols.commit_down,
            symbols.vertical .. " " .. symbols.commit_down,
            symbols.vertical .. " " .. symbols.vertical .. " " .. symbols.commit_down,
            symbols.commit_through .. symbols.horizontal .. symbols.merge_right .. " " .. symbols.vertical,
            symbols.commit_through .. "   " .. symbols.vertical,
            symbols.vertical .. "   " .. symbols.commit_through,
            symbols.commit_up .. symbols.horizontal .. symbols.horizontal .. symbols.horizontal .. symbols.merge_right,
        }, texts({
            { hash = "tip", parents = { "ecfc" } },
            { hash = "wip", parents = { "ecfc" } },
            { hash = "api1", parents = { "api2" } },
            { hash = "ecfc", parents = { "main2" } },
            { hash = "main2", parents = { "base" } },
            { hash = "api2", parents = { "base" } },
            { hash = "base", parents = {} },
        }))
    end)

    it("starts a new branch in a column a finished lane left open", function()
        assert.same({
            symbols.commit_down,
            symbols.vertical .. " " .. symbols.commit_down,
            symbols.commit_up .. " " .. symbols.vertical,
            symbols.commit_down .. " " .. symbols.vertical,
            symbols.vertical .. " " .. symbols.commit_through,
            symbols.commit_up .. symbols.horizontal .. symbols.merge_right,
        }, texts({
            { hash = "L", parents = { "Lroot" } },
            { hash = "R", parents = { "R2" } },
            { hash = "Lroot", parents = {} },
            { hash = "new", parents = { "base" } },
            { hash = "R2", parents = { "base" } },
            { hash = "base", parents = {} },
        }))
    end)

    it("keeps the merged parent on the node when a side branch joins the line above", function()
        local rows = graph.layout({
            { hash = "main", parents = { "merge" } },
            { hash = "topic", parents = { "merge" } },
            { hash = "merge", parents = { "base", "side" } },
            { hash = "side", parents = { "base" } },
            { hash = "base", parents = {} },
        }, symbols)

        assert.equal(symbols.commit_down, rows[1].text)
        assert.equal(symbols.vertical .. " " .. symbols.commit_down, rows[2].text)
        assert.equal(symbols.commit_through .. symbols.arrow_left .. symbols.branch_start, rows[3].text)
        assert.equal(1, #rows[3].above)
        assert.equal(symbols.vertical .. symbols.horizontal .. symbols.merge_right, rows[3].above[1].text)
        assert.equal(symbols.vertical .. " " .. symbols.commit_through, rows[4].text)

        local join_color = nil

        for _, span in ipairs(rows[3].above[1].spans) do
            if rows[3].above[1].text:sub(span.start + 1, span.stop) == symbols.merge_right then
                join_color = span.color
            end
        end

        -- The line above keeps the arriving branch. The node keeps the merged parent.
        assert.equal(2, join_color)
        assert.equal(3, rows[3].spans[2].color)
    end)

    it("draws each merged parent from the node when a side branch joins above", function()
        local rows = graph.layout({
            { hash = "main", parents = { "merge" } },
            { hash = "topic", parents = { "merge" } },
            { hash = "merge", parents = { "base", "left", "right" } },
            { hash = "left", parents = { "base" } },
            { hash = "right", parents = { "base" } },
            { hash = "base", parents = {} },
        }, symbols)

        assert.equal(
            symbols.commit_through
                .. symbols.arrow_left
                .. symbols.branch_start
                .. symbols.horizontal
                .. symbols.branch_start,
            rows[3].text
        )
        assert.equal(1, #rows[3].above)
        assert.equal(symbols.vertical .. symbols.horizontal .. symbols.merge_right, rows[3].above[1].text)
    end)

    it("keeps sibling lines apart until their shared parent", function()
        assert.same({
            symbols.commit_down,
            symbols.vertical .. " " .. symbols.commit_down,
            symbols.commit_through .. " " .. symbols.vertical,
            symbols.commit_through .. symbols.horizontal .. symbols.merge_right,
        }, texts({
            { hash = "sunday", parents = { "origin" } },
            { hash = "main", parents = { "base" } },
            { hash = "origin", parents = { "base" } },
            { hash = "base", parents = { "older" } },
        }))
    end)

    it("keeps a branch line's color across lanes it crosses", function()
        local rows = graph.layout({
            { hash = "left", parents = { "left-1" } },
            { hash = "mid", parents = { "mid-1" } },
            { hash = "inner", parents = { "inner-1" } },
            { hash = "right", parents = { "left-1" } },
            { hash = "inner-1", parents = { "base" } },
            { hash = "mid-1", parents = { "base" } },
            { hash = "left-1", parents = { "base" } },
            { hash = "base", parents = {} },
        }, symbols)

        local function colors_of(row, glyph)
            local found = {}

            for _, span in ipairs(row.spans) do
                if row.text:sub(span.start + 1, span.stop) == glyph then
                    found[#found + 1] = span.color
                end
            end

            return found
        end

        -- `right` shares a parent with `left`, so its line waits for that parent.
        assert.same({}, colors_of(rows[4], symbols.horizontal))

        local crossing = rows[7]

        -- The lines meet where the branch was created, so the span stays a bar.
        assert.same({ 4, 4, 4 }, colors_of(crossing, symbols.horizontal))
        assert.same({ 2, 3 }, colors_of(crossing, symbols.vertical))
        assert.equal(1, crossing.color)
    end)

    it("meets a continuing parent on the right with a junction", function()
        local rows = graph.layout({
            { hash = "main_tip", parents = { "merge" } },
            { hash = "feature_tip", parents = { "feature_mid" } },
            { hash = "merge", parents = { "main_mid", "feature_mid" } },
            { hash = "feature_mid", parents = { "base" } },
            { hash = "main_mid", parents = { "base" } },
            { hash = "base", parents = {} },
        }, symbols)

        assert.equal(symbols.commit_through .. symbols.arrow_left .. symbols.join_left, rows[3].text)

        local function color_of(glyph)
            for _, span in ipairs(rows[3].spans) do
                if rows[3].text:sub(span.start + 1, span.stop) == glyph then
                    return span.color
                end
            end
        end

        -- The arrow and the junction are the parent lane, so they read as one line.
        assert.equal(color_of(symbols.join_left), color_of(symbols.arrow_left))
        -- The root is where the branch was created, so that join stays a bar.
        assert.equal(symbols.commit_up .. symbols.horizontal .. symbols.merge_right, rows[6].text)
    end)

    it("points a merge from a continuing lane into that commit", function()
        assert.same({
            symbols.commit_down,
            symbols.vertical .. " " .. symbols.commit_down,
            symbols.join_right .. symbols.arrow_right .. symbols.commit_through,
            symbols.vertical .. " " .. symbols.commit_through,
            symbols.commit_through .. " " .. symbols.vertical,
            symbols.commit_up .. symbols.horizontal .. symbols.merge_right,
        }, texts({
            { hash = "main_tip", parents = { "main_mid" } },
            { hash = "feature_tip", parents = { "merge" } },
            { hash = "merge", parents = { "feature_prev", "main_mid" } },
            { hash = "feature_prev", parents = { "base" } },
            { hash = "main_mid", parents = { "base" } },
            { hash = "base", parents = {} },
        }))
    end)

    it("draws a wide arrow as a single cell", function()
        local wide = vim.deepcopy(symbols)
        wide.arrow_right = "＞"
        wide.arrow_left = "＜"

        local rows = graph.layout({
            { hash = "M", parents = { "A", "B" } },
            { hash = "B", parents = { "A" } },
            { hash = "A", parents = {} },
        }, wide)

        assert.equal(wide.commit_down .. "<" .. wide.branch_start, rows[1].text)
        assert.equal(wide.commit_up .. wide.horizontal .. wide.merge_right, rows[3].text)
    end)

    it("gives the side branch its own color", function()
        local rows = graph.layout({
            { hash = "M", parents = { "A", "B" } },
            { hash = "B", parents = { "C" } },
            { hash = "A", parents = { "C" } },
            { hash = "C", parents = {} },
        }, symbols)

        assert.equal(1, rows[1].color)
        assert.equal(2, rows[2].color)
        assert.equal(1, rows[3].color)
        assert.truthy(rows[2].node_start > 0)
        assert.equal(#symbols.commit_down, rows[1].node_length)
    end)

    it("mutes a remote-only branch until a local commit joins the lane", function()
        local rows = graph.layout({
            { hash = "D", parents = { "C" }, remote_only = true },
            { hash = "C", parents = { "B" } },
            { hash = "B", parents = {} },
        }, symbols)

        assert.equal(true, rows[1].muted)
        assert.equal(false, rows[2].muted)
        assert.equal(false, rows[3].muted)
    end)

    it("mutes the fork of a branch that is not local", function()
        local rows = graph.layout({
            { hash = "M", parents = { "A", "B" } },
            { hash = "B", parents = { "C" }, remote_only = true },
            { hash = "A", parents = { "C" } },
            { hash = "C", parents = {} },
        }, symbols)

        assert.equal(false, rows[1].muted)
        assert.equal(true, rows[2].muted)
        assert.equal(false, rows[3].muted)

        local fork_muted = nil

        for _, span in ipairs(rows[1].spans) do
            if rows[1].text:sub(span.start + 1, span.stop) == symbols.branch_start then
                fork_muted = span.muted
            end
        end

        assert.equal(true, fork_muted)
    end)
end)
