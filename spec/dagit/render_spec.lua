local configuration = require("dagit._core.configuration")
local render = require("dagit._core.render")

local function commit(fields)
    return vim.tbl_extend("force", {
        hash = "abc",
        parents = {},
        author = "Ada",
        timestamp = "2026-10-08T10:00:00Z",
        subject = "subject",
        refs = {},
    }, fields)
end

describe("render.format_date", function()
    it("includes the clock in the default date", function()
        local text = render.format_date("2026-10-08T10:05:00Z", configuration.defaults().date_format)

        assert.truthy(text:find("10:05", 1, true) ~= nil)
    end)

    it("adds the clock when the date format has no time", function()
        local config = configuration.defaults()
        config.date_format = "%d %b"

        local lines = render.build({
            commit({ timestamp = "2026-10-08T10:05:00Z" }),
        }, config)

        local shown = ""

        for _, chunk in ipairs(lines[1].virt) do
            shown = shown .. chunk.text
        end

        assert.truthy(shown:find("10:05", 1, true) ~= nil)
    end)

    it("formats an ISO timestamp with os.date", function()
        local text = render.format_date("2026-10-08T10:00:00Z", "%Y-%m-%d")

        assert.equal("2026-10-08", text)
    end)

    it("formats a relative age", function()
        local now = os.time({ year = 2026, month = 10, day = 8, hour = 12, min = 0, sec = 0 })
        local text = render.format_date("2026-10-08T10:00:00", "relative", now)

        assert.equal("2h ago", text)
    end)
end)

describe("render.build", function()
    it("places the subject after the graph and aligns the meta columns", function()
        local config = configuration.defaults()
        config.icons.enabled = false
        config.date_format = "%d %b"

        local lines = render.build({
            commit({
                hash = "m",
                parents = { "a", "b" },
                subject = "Merge the feature branch",
                author = "Ada",
                refs = { { name = "main", kind = "head" } },
            }),
            commit({
                hash = "b",
                parents = { "c" },
                subject = "Add a check",
                author = "Bea",
            }),
        }, config)

        local symbols = config.symbols
        local fork = "  " .. symbols.commit_down .. symbols.horizontal .. symbols.branch_start .. " "
        local spine = "  " .. symbols.vertical .. " " .. symbols.commit_through .. " "

        assert.truthy(vim.startswith(lines[1].text, fork))
        assert.truthy(lines[1].text:find("m (HEAD -> main) Merge the feature branch", 1, true) ~= nil)
        assert.truthy(vim.startswith(lines[2].text, spine))
        assert.truthy(lines[2].text:find("b Add a check", 1, true) ~= nil)
        assert.truthy(lines[1].node_group:find("Bold$") ~= nil)

        local function span_text(line, group)
            for _, span in ipairs(line.spans) do
                if span.group == group then
                    return line.text:sub(span.start + 1, span.stop)
                end
            end
        end

        assert.equal("m", span_text(lines[1], "DagitHashBold"))
        assert.equal("HEAD -> ", span_text(lines[1], "DagitHead"))
        assert.equal("b", span_text(lines[2], "DagitHash"))

        local function virt(line)
            local parts = {}

            for _, chunk in ipairs(line.virt) do
                parts[#parts + 1] = chunk.text
            end

            return table.concat(parts)
        end

        local first = virt(lines[1])
        local second = virt(lines[2])

        assert.equal(vim.api.nvim_strwidth(first), vim.api.nvim_strwidth(second))
        assert.truthy(first:find("Ada", 1, true) ~= nil)
        assert.truthy(second:find("Bea", 1, true) ~= nil)
        assert.truthy(first:find("main", 1, true) == nil)

        local function group_of(line, text)
            for _, chunk in ipairs(line.virt) do
                if chunk.text:find(text, 1, true) then
                    return chunk.group
                end
            end
        end

        assert.equal("DagitAuthorBold", group_of(lines[1], "Ada"))
        assert.equal("DagitAuthor", group_of(lines[2], "Bea"))

        local merge_span = nil

        for _, span in ipairs(lines[1].spans) do
            if span.group == "DagitMergeBold" then
                merge_span = span
            end
        end

        assert.truthy(merge_span)
        assert.equal("Merge the feature branch", lines[1].text:sub(merge_span.start + 1, merge_span.stop))
    end)

    it("collapses several tags and keeps the branch inside the ref column", function()
        local config = configuration.defaults()
        config.icons.enabled = false
        config.ref_max_width = 24

        local lines = render.build({
            commit({
                hash = "t",
                subject = "tagged",
                refs = {
                    { name = "feature/a-very-long-branch-name", kind = "branch" },
                    { name = "deploy/test/2024", kind = "tag" },
                    { name = "deploy/qa/2024", kind = "tag" },
                },
            }),
            commit({
                hash = "one",
                subject = "one tag",
                refs = {
                    { name = "main", kind = "head" },
                    { name = "v1.2.3", kind = "tag" },
                },
            }),
        }, config)

        local function decoration(line)
            return line.text:match("%b()")
        end

        local function tag_of(line)
            for _, chunk in ipairs(line.virt) do
                if chunk.group:gsub("Bold$", "") == "DagitRefTag" then
                    return chunk.text
                end
            end
        end

        local branch = decoration(lines[1])

        assert.truthy(vim.api.nvim_strwidth(branch) <= config.ref_max_width)
        assert.truthy(branch:find("feature/", 1, true) ~= nil)
        assert.truthy(branch:find("deploy/", 1, true) == nil)
        assert.equal("(HEAD -> main)", decoration(lines[2]))
        assert.equal("multi tag", tag_of(lines[1]))
        assert.equal("v1.2.3", tag_of(lines[2]))
    end)

    it("uses one multi tag label when a commit has several tags", function()
        local config = configuration.defaults()
        config.icons.enabled = false
        config.ref_max_width = 40

        local lines = render.build({
            commit({
                refs = {
                    { name = "main", kind = "branch" },
                    { name = "deploy/test", kind = "tag" },
                    { name = "deploy/qa", kind = "tag" },
                },
            }),
        }, config)

        assert.truthy(lines[1].text:find("(main)", 1, true) ~= nil)

        local label = nil

        for _, chunk in ipairs(lines[1].virt) do
            if chunk.group == "DagitRefTag" then
                label = chunk.text
            end
        end

        assert.equal("multi tag", label)
    end)

    it("paints branch names with the lane color and leaves tags alone", function()
        local config = configuration.defaults()
        config.icons.enabled = false

        local lines = render.build({
            commit({
                hash = "m",
                parents = { "a", "b" },
                refs = {
                    { name = "main", kind = "head" },
                    { name = "origin/main", kind = "remote" },
                },
            }),
            commit({
                hash = "b",
                parents = { "c" },
                refs = {
                    { name = "feature", kind = "branch" },
                    { name = "v1", kind = "tag" },
                },
            }),
        }, config)

        local function group_of(line, text)
            for _, span in ipairs(line.spans) do
                if line.text:sub(span.start + 1, span.stop) == text then
                    return span.group
                end
            end
        end

        assert.equal(lines[1].node_group, group_of(lines[1], "main"))
        assert.equal(lines[1].node_group, group_of(lines[1], "origin/main"))
        assert.equal(lines[2].node_group, group_of(lines[2], "feature"))

        local tag_group = nil

        for _, chunk in ipairs(lines[2].virt) do
            if chunk.text == "v1" then
                tag_group = chunk.group
            end
        end

        assert.equal("DagitRefTag", tag_group)
        assert.truthy(lines[1].node_group ~= lines[2].node_group)
    end)
end)
