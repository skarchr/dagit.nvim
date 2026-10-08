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
    end)

    it("keeps a background the user already defined", function()
        vim.api.nvim_set_hl(0, "DagitNormal", { link = "StatusLine" })

        highlights.define()

        local hl = vim.api.nvim_get_hl(0, { name = "DagitNormal", link = true })
        assert.equal("StatusLine", hl.link)
        clear("DagitNormal")
    end)
end)
