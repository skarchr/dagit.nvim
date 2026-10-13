describe("highlights", function()
    local highlights = require("dagit._core.highlights")

    local function clear(name)
        vim.cmd("highlight clear " .. name)
    end

    it("links the window background to the snacks explorer group", function()
        clear("DagitNormal")
        vim.api.nvim_set_hl(0, "SnacksPicker", { link = "NormalFloat" })
        vim.api.nvim_set_hl(0, "SnacksPickerList", { link = "SnacksPicker" })

        highlights.define()

        local hl = vim.api.nvim_get_hl(0, { name = "DagitNormal", link = true })
        assert.equal("SnacksPickerList", hl.link)
    end)

    it("draws the HEAD row in bold and hides the cursor group", function()
        highlights.define()

        local author = vim.api.nvim_get_hl(0, { name = "DagitAuthorBold", link = false })
        local head = vim.api.nvim_get_hl(0, { name = "DagitHead", link = false })
        local cursor = vim.api.nvim_get_hl(0, { name = "DagitCursor", link = false })

        assert.equal(true, author.bold)
        assert.equal(true, head.bold)
        assert.equal(100, cursor.blend)
        assert.equal("DagitAuthorBoldLine", highlights.line_group("DagitAuthorBold"))
        assert.equal("DagitHeadLine", highlights.line_group("DagitHead"))

        local hash = vim.api.nvim_get_hl(0, { name = "DagitHash", link = true })
        assert.equal("Label", hash.link)

        local local_hash = vim.api.nvim_get_hl(0, { name = "DagitHashLocal", link = true })
        assert.equal("DiagnosticWarn", local_hash.link)

        local upstream = vim.api.nvim_get_hl(0, { name = "DagitUpstreamGone", link = true })
        assert.equal("DiagnosticError", upstream.link)

        local added = vim.api.nvim_get_hl(0, { name = "DagitFileAdded", link = true })
        local modified = vim.api.nvim_get_hl(0, { name = "DagitFileModified", link = true })
        local deleted = vim.api.nvim_get_hl(0, { name = "DagitFileDeleted", link = true })
        local renamed = vim.api.nvim_get_hl(0, { name = "DagitFileRenamed", link = true })
        local body = vim.api.nvim_get_hl(0, { name = "DagitBody", link = true })

        assert.equal("DiagnosticOk", added.link)
        assert.equal("DiagnosticWarn", modified.link)
        assert.equal("DiagnosticError", deleted.link)
        assert.equal("DiagnosticHint", renamed.link)
        assert.equal("Comment", body.link)
        assert.equal("DagitUpstreamGoneBoldLine", highlights.line_group("DagitUpstreamGoneBold"))

        local lane = vim.api.nvim_get_hl(0, { name = "DagitGraph1", link = false })
        local muted = vim.api.nvim_get_hl(0, { name = "DagitGraph1Muted", link = false })
        local reversed = vim.api.nvim_get_hl(0, { name = "DagitGraph1Rev", link = false })
        local reversed_muted = vim.api.nvim_get_hl(0, { name = "DagitGraph1MutedRev", link = false })
        local paper = vim.api.nvim_get_hl(0, { name = "DagitNormal", link = false })
        assert.truthy(lane.fg)
        assert.truthy(muted.fg)
        assert.truthy(muted.fg ~= lane.fg)
        assert.equal(lane.fg, reversed.bg)
        assert.equal(paper.bg, reversed.fg)
        assert.equal(true, reversed.bold)
        assert.equal(muted.fg, reversed_muted.bg)
        assert.equal(paper.bg, reversed_muted.fg)
        assert.equal("DagitGraph1MutedLine", highlights.line_group("DagitGraph1Muted"))
        assert.equal("DagitGraph1RevBoldLine", highlights.line_group("DagitGraph1RevBold"))
        assert.equal("DagitHashLocalBoldLine", highlights.line_group("DagitHashLocalBold"))

        local bold = vim.api.nvim_get_hl(0, { name = "DagitGraph1MutedBold", link = false })
        assert.equal(true, bold.bold)

        local text = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
        local muted_text = vim.api.nvim_get_hl(0, { name = "DagitTextMuted", link = false })
        assert.truthy(text.fg)
        assert.truthy(muted_text.fg)
        assert.truthy(muted_text.fg ~= text.fg)
        assert.equal("DagitTextMutedLine", highlights.line_group("DagitTextMuted"))

        local added_full = vim.api.nvim_get_hl(0, { name = "DagitFileAdded", link = false })
        local added_muted = vim.api.nvim_get_hl(0, { name = "DagitFileAddedMuted", link = false })
        local body_full = vim.api.nvim_get_hl(0, { name = "DagitBody", link = false })
        local body_muted = vim.api.nvim_get_hl(0, { name = "DagitBodyMuted", link = false })

        assert.truthy(added_muted.fg)
        assert.truthy(body_muted.fg)
        assert.truthy(added_full.fg ~= added_muted.fg)
        assert.truthy(body_full.fg ~= body_muted.fg)
        assert.equal("DagitFileAddedMutedLine", highlights.line_group("DagitFileAddedMuted"))
        assert.equal("DagitBodyMutedLine", highlights.line_group("DagitBodyMuted"))
    end)

    it("draws HEAD as a reversed accent", function()
        clear("DagitNormal")
        clear("DagitHeadMark")
        vim.api.nvim_set_hl(0, "NormalFloat", { fg = 0xD0D0D0, bg = 0x222222 })
        vim.api.nvim_set_hl(0, "Special", { fg = 0xFFAA00, ctermfg = 214 })
        vim.api.nvim_set_hl(0, "CursorLine", { bg = 0x333355 })

        highlights.define()

        local mark = vim.api.nvim_get_hl(0, { name = "DagitHeadMark", link = false })
        local marked_line = vim.api.nvim_get_hl(0, { name = "DagitHeadMarkBoldLine", link = false })

        assert.equal(0xFFAA00, mark.bg)
        assert.equal(0x222222, mark.fg)
        assert.equal(true, mark.bold)
        assert.equal(0xFFAA00, marked_line.fg)
        assert.equal(0x333355, marked_line.bg)
        assert.equal("DagitHeadMarkBoldLine", highlights.line_group("DagitHeadMarkBold"))
    end)

    it("keeps a background the user already defined", function()
        vim.api.nvim_set_hl(0, "DagitNormal", { link = "StatusLine" })

        highlights.define()

        local hl = vim.api.nvim_get_hl(0, { name = "DagitNormal", link = true })
        assert.equal("StatusLine", hl.link)
        clear("DagitNormal")
    end)
end)
