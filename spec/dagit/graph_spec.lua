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

    it("draws a branch to the right of a merge", function()
        assert.same({
            symbols.commit_down .. symbols.horizontal .. symbols.branch_start,
            symbols.vertical .. " " .. symbols.commit_through,
            symbols.vertical .. " " .. symbols.commit_through,
            symbols.vertical .. " " .. symbols.commit_through,
            symbols.commit_through .. symbols.horizontal .. symbols.merge_right,
            symbols.commit_up,
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
            symbols.commit_down .. symbols.horizontal .. symbols.branch_start,
            symbols.vertical .. symbols.horizontal .. symbols.commit_up,
            symbols.commit_up,
        }, texts({
            { hash = "M", parents = { "A", "B" } },
            { hash = "B", parents = { "A" } },
            { hash = "A", parents = {} },
        }))
    end)

    it("joins two tips into their common parent", function()
        assert.same({
            symbols.commit_down,
            symbols.vertical .. symbols.horizontal .. symbols.commit,
            symbols.commit_up,
        }, texts({
            { hash = "A", parents = { "C" } },
            { hash = "B", parents = { "C" } },
            { hash = "C", parents = {} },
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

        local crossing = rows[4]

        local function colors_of(glyph)
            local found = {}

            for _, span in ipairs(crossing.spans) do
                if crossing.text:sub(span.start + 1, span.stop) == glyph then
                    found[#found + 1] = span.color
                end
            end

            return found
        end

        assert.same({ 4, 4, 4 }, colors_of(symbols.horizontal))
        assert.same({ 1, 2, 3 }, colors_of(symbols.vertical))
        assert.equal(4, crossing.color)
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
end)
