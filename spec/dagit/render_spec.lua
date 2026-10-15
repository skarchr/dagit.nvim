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

    it("hides the year for a commit from the current year", function()
        local now = os.time({ year = 2026, month = 10, day = 8, hour = 12, min = 0, sec = 0 })
        local text = render.format_date("2026-10-08T10:05:00Z", "%d %b %H:%M", now)
        local instant = os.time({ year = 2026, month = 10, day = 8, hour = 10, min = 5, sec = 0 })

        assert.equal(os.date("%d %b %H:%M", instant), text)
    end)

    it("shows the year for a commit from a previous year", function()
        local now = os.time({ year = 2026, month = 10, day = 8, hour = 12, min = 0, sec = 0 })
        local text = render.format_date("2025-03-02T09:15:00Z", "%d %b %H:%M", now)
        local instant = os.time({ year = 2025, month = 3, day = 2, hour = 9, min = 15, sec = 0 })

        assert.equal(os.date("%d %b %Y %H:%M", instant), text)
    end)
end)

describe("render.build", function()
    it("joins a side branch above a merge and keeps the parent on the node", function()
        local config = configuration.defaults()
        config.icons.enabled = false
        local symbols = config.symbols

        local lines = render.build({
            commit({ hash = "main", parents = { "merge" }, subject = "main" }),
            commit({ hash = "topic", parents = { "merge" }, subject = "topic" }),
            commit({ hash = "merge", parents = { "base", "side" }, subject = "Merge the side branch" }),
            commit({ hash = "side", parents = { "base" }, subject = "side" }),
            commit({ hash = "base", parents = {}, subject = "base" }),
        }, config)

        local merge = "  " .. symbols.commit_through .. symbols.arrow_left .. symbols.branch_start .. " "
        assert.truthy(vim.startswith(lines[3].text, merge))
        assert.equal(1, #lines[3].above_lines)

        local shown = ""

        for _, chunk in ipairs(lines[3].above_lines[1]) do
            shown = shown .. chunk[1]
        end

        assert.truthy(shown:find(symbols.merge_right, 1, true) ~= nil)
        assert.truthy(shown:find(symbols.diagonal_right, 1, true) == nil)
    end)

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
        local fork = "  " .. symbols.commit_down .. symbols.arrow_left .. symbols.branch_start .. " "
        local spine = "  " .. symbols.vertical .. " " .. symbols.commit_through .. " "

        assert.truthy(vim.startswith(lines[1].text, fork))
        assert.truthy(lines[1].text:find("m  HEAD   main  Merge the feature branch", 1, true) ~= nil)
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
        assert.equal(" HEAD ", span_text(lines[1], "DagitHeadMarkBold"))
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
            local parts = {}

            for _, span in ipairs(line.spans) do
                local group = span.group

                if group:find("Rev", 1, true) or group:find("HeadMark", 1, true) or group:find("UpstreamGone", 1, true) then
                    parts[#parts + 1] = line.text:sub(span.start + 1, span.stop)
                end
            end

            return table.concat(parts)
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
        assert.truthy(lines[2].text:find(" HEAD   main ", 1, true) ~= nil)
        assert.equal(" HEAD  main ", decoration(lines[2]))
        assert.equal("multi tag", tag_of(lines[1]))
        assert.equal("v1.2.3", tag_of(lines[2]))

        local detached = render.build({
            commit({
                hash = "d",
                subject = "loose",
                refs = { { name = "HEAD", kind = "head" } },
            }),
        }, config)

        assert.truthy(detached[1].text:find("d  HEAD  loose", 1, true) ~= nil)
        assert.equal(nil, detached[1].text:find("(", 1, true))
    end)

    it("writes upstream gone after the branch in its own color", function()
        local config = configuration.defaults()
        config.icons.enabled = false
        config.ref_max_width = 40

        local lines = render.build({
            commit({
                hash = "gone",
                subject = "only here",
                refs = {
                    { name = "feature", kind = "branch", upstream_gone = true },
                    { name = "origin/kept", kind = "remote" },
                },
            }),
            commit({
                hash = "head",
                subject = "checked out",
                refs = { { name = "feature", kind = "head", upstream_gone = true } },
            }),
        }, config)

        assert.truthy(lines[1].text:find(" feature  (upstream gone)  origin/kept ", 1, true) ~= nil)
        assert.truthy(lines[2].text:find(" HEAD   feature  (upstream gone)", 1, true) ~= nil)

        local function span_text(line, group)
            for _, span in ipairs(line.spans) do
                if span.group == group then
                    return line.text:sub(span.start + 1, span.stop)
                end
            end
        end

        assert.equal(" (upstream gone)", span_text(lines[1], "DagitUpstreamGone"))
        assert.equal(" (upstream gone)", span_text(lines[2], "DagitUpstreamGoneBold"))

        config.ref_max_width = 20

        local tight = render.build({
            commit({
                refs = { { name = "topic", kind = "branch", upstream_gone = true } },
            }),
        }, config)

        local decoration = ""

        for _, span in ipairs(tight[1].spans) do
            local group = span.group

            if group:find("Rev", 1, true) or group:find("UpstreamGone", 1, true) then
                decoration = decoration .. tight[1].text:sub(span.start + 1, span.stop)
            end
        end

        assert.truthy(vim.api.nvim_strwidth(decoration) <= config.ref_max_width)
        assert.truthy(decoration:find("(upstream gone)", 1, true) ~= nil)
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

        assert.truthy(lines[1].text:find(" main ", 1, true) ~= nil)

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

        local function badge_group(node_group)
            if node_group:find("Bold$") then
                return node_group:gsub("Bold$", "") .. "RevBold"
            end

            return node_group .. "Rev"
        end

        assert.equal(badge_group(lines[1].node_group), group_of(lines[1], " main "))
        assert.equal(badge_group(lines[1].node_group), group_of(lines[1], " origin/main "))
        assert.equal(badge_group(lines[2].node_group), group_of(lines[2], " feature "))

        local tag_group = nil

        for _, chunk in ipairs(lines[2].virt) do
            if chunk.text == "v1" then
                tag_group = chunk.group
            end
        end

        assert.equal("DagitRefTag", tag_group)
        assert.truthy(lines[1].node_group ~= lines[2].node_group)
    end)

    it("colors a local-only hash and mutes a branch that is not local", function()
        local config = configuration.defaults()
        config.icons.enabled = false

        local lines = render.build({
            commit({
                hash = "local01",
                parents = { "shared1" },
                subject = "Ahead of the remote",
                local_only = true,
                refs = { { name = "main", kind = "head" } },
            }),
            commit({
                hash = "remote1",
                parents = { "shared1" },
                subject = "Only on the remote",
                remote_only = true,
                refs = { { name = "origin/topic", kind = "remote" } },
            }),
            commit({ hash = "shared1", parents = {} }),
        }, config)

        local function group_of(line, text)
            for _, span in ipairs(line.spans) do
                if line.text:sub(span.start + 1, span.stop) == text then
                    return span.group
                end
            end
        end

        assert.equal("DagitHashLocalBold", group_of(lines[1], "local01"))
        assert.equal("DagitHead", group_of(lines[1], "Ahead of the remote"))
        assert.equal(nil, lines[1].node_group:find("Muted", 1, true))
        assert.truthy(lines[2].node_group:find("Muted$") ~= nil)
        assert.equal(lines[2].node_group .. "Rev", group_of(lines[2], " origin/topic "))
        assert.equal("DagitHashMuted", group_of(lines[2], "remote1"))
        assert.equal("DagitTextMuted", group_of(lines[2], "Only on the remote"))

        local function virt_group(line, text)
            for _, chunk in ipairs(line.virt) do
                if chunk.text:find(text, 1, true) then
                    return chunk.group
                end
            end
        end

        assert.equal("DagitAuthorMuted", virt_group(lines[2], "Ada"))
        assert.equal("DagitAuthorBold", virt_group(lines[1], "Ada"))
    end)
end)

describe("render.detail_virt_lines", function()
    local function joined(row)
        local parts = {}

        for _, chunk in ipairs(row) do
            parts[#parts + 1] = chunk[1]
        end

        return table.concat(parts)
    end

    local function group_of(row, text)
        for _, chunk in ipairs(row) do
            if chunk[1]:find(text, 1, true) then
                return chunk[2]
            end
        end
    end

    it("puts the description above the colored file list", function()
        local config = configuration.defaults()
        local lines = render.build({
            commit({ hash = "bbb", parents = { "aaa" }, subject = "second" }),
            commit({ hash = "aaa", subject = "first" }),
        }, config)

        local virt = render.detail_virt_lines(lines[1], {
            body = { "Explain the change", "", "Second paragraph." },
            files = {
                { status = "M", path = "lua/a.lua" },
                { status = "A", path = "dir/nested.txt" },
                { status = "D", path = "gone.txt" },
                { status = "R", path = "new-name.txt", old_path = "old-name.txt" },
            },
        })

        local blob = {}

        for index, row in ipairs(virt) do
            blob[index] = joined(row)
        end

        blob = table.concat(blob, "\n")
        local explain = blob:find("Explain the change", 1, true)
        local second = blob:find("Second paragraph.", 1, true)
        local modified = blob:find("M lua/a.lua", 1, true)
        local added = blob:find("A dir/nested.txt", 1, true)
        local deleted = blob:find("D gone.txt", 1, true)
        local renamed = blob:find("R old-name.txt -> new-name.txt", 1, true)

        assert.truthy(explain)
        assert.truthy(explain < second)
        assert.truthy(second < modified)
        assert.truthy(modified < added)
        assert.truthy(added < deleted)
        assert.truthy(deleted < renamed)
        assert.truthy(blob:find(config.symbols.vertical, 1, true) ~= nil)
        assert.equal("DagitBody", group_of(virt[1], "Explain the change"))
        assert.equal("DagitFileModified", group_of(virt[5], "M lua/a.lua"))
        assert.equal("DagitFileAdded", group_of(virt[6], "A dir/nested.txt"))
        assert.equal("DagitFileDeleted", group_of(virt[7], "D gone.txt"))
        assert.equal("DagitFileRenamed", group_of(virt[8], "R old-name.txt -> new-name.txt"))
        assert.truthy(joined(virt[1]):find("  Explain the change", 1, true) ~= nil)
        assert.truthy(joined(virt[5]):find("  M lua/a.lua", 1, true) ~= nil)
    end)

    it("starts with the files when the commit has no description", function()
        local lines = render.build({
            commit({ hash = "aaa", subject = "first" }),
        }, configuration.defaults())

        local virt = render.detail_virt_lines(lines[1], {
            body = {},
            files = { { status = "A", path = "a.txt" } },
        })

        assert.equal(1, #virt)
        assert.truthy(joined(virt[1]):find("  A a.txt", 1, true) ~= nil)
        assert.equal("DagitFileAdded", group_of(virt[1], "A a.txt"))
    end)

    it("summarizes more than five files before the description", function()
        local lines = render.build({
            commit({ hash = "aaa", subject = "first" }),
        }, configuration.defaults())

        local files = {
            { status = "A", path = "a.txt" },
            { status = "A", path = "b.txt" },
            { status = "M", path = "c.txt" },
            { status = "R", path = "new.txt", old_path = "old.txt" },
            { status = "D", path = "gone.txt" },
            { status = "C", path = "copy.txt", old_path = "source.txt" },
        }

        local quiet = render.detail_virt_lines(lines[1], {
            body = { "Explain the change" },
            files = { files[1], files[2], files[3], files[4], files[5] },
        })
        local virt = render.detail_virt_lines(lines[1], {
            body = { "Explain the change" },
            files = files,
        })

        assert.equal(nil, joined(quiet[1]):find("added", 1, true))
        assert.truthy(joined(virt[1]):find("2 added, 1 modified, 1 renamed, 1 deleted, 1 copied", 1, true) ~= nil)
        assert.equal("DagitFileAdded", group_of(virt[1], "2 added"))
        assert.equal("DagitFileModified", group_of(virt[1], "1 modified"))
        assert.equal("DagitFileRenamed", group_of(virt[1], "1 renamed"))
        assert.equal("DagitFileDeleted", group_of(virt[1], "1 deleted"))
        assert.equal("DagitFileRenamed", group_of(virt[1], "1 copied"))
        assert.truthy(joined(virt[2]):find("Explain the change", 1, true) ~= nil)
        assert.equal(nil, joined(virt[1]):find("Explain the change", 1, true))
    end)

    it("mutes the description and files on a commit that is not local", function()
        local lines = render.build({
            commit({
                hash = "remote1",
                subject = "Only on the remote",
                remote_only = true,
            }),
        }, configuration.defaults())

        local files = {
            { status = "A", path = "a.txt" },
            { status = "A", path = "b.txt" },
            { status = "M", path = "c.txt" },
            { status = "R", path = "new.txt", old_path = "old.txt" },
            { status = "D", path = "gone.txt" },
            { status = "C", path = "copy.txt", old_path = "source.txt" },
        }
        local virt = render.detail_virt_lines(lines[1], {
            body = { "Explain the change" },
            files = files,
        })

        assert.equal("DagitFileAddedMuted", group_of(virt[1], "2 added"))
        assert.equal("DagitFileModifiedMuted", group_of(virt[1], "1 modified"))
        assert.equal("DagitFileRenamedMuted", group_of(virt[1], "1 renamed"))
        assert.equal("DagitFileDeletedMuted", group_of(virt[1], "1 deleted"))
        assert.equal("DagitBodyMuted", group_of(virt[1], ", "))
        assert.equal("DagitBodyMuted", group_of(virt[2], "Explain the change"))
        assert.equal("DagitFileRenamedMuted", group_of(virt[7], "R old.txt -> new.txt"))
    end)
end)

describe("view filter line", function()
    local view = require("dagit._core.view")

    local function plain(bar)
        return (bar:gsub("%%#[%w]+#", ""))
    end

    it("wraps the active filter in brackets", function()
        assert.equal(" [all]  local  remote  head", plain(view.filter_bar("all")))
        assert.equal(" all  [local]  remote  head", plain(view.filter_bar("local")))
        assert.equal(" all  local  [remote]  head", plain(view.filter_bar("remote")))
        assert.equal(" all  local  remote  [head]", plain(view.filter_bar("head")))
        assert.truthy(view.filter_bar("local"):find("%%#DagitHead#%[local%]") ~= nil)
    end)
end)
