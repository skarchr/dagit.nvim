local configuration = require("dagit._core.configuration")

local function reset()
    vim.g.dagit = nil
    configuration.set_user_opts(nil)
end

describe("configuration", function()
    it("uses defaults when nothing is configured", function()
        reset()
        local config, issues = configuration.resolve()

        assert.same({}, issues)
        assert.equal(16, config.height)
        assert.equal("bottom", config.split)
        assert.same({ "--all" }, config.log_args)
        assert.equal("<C-o>", config.keymaps.copy_hash)
    end)

    it("merges a partial setup over vim.g", function()
        reset()
        vim.g.dagit = { height = 20, icons = { enabled = false } }
        configuration.set_user_opts({ date_format = "relative", log_args = { "HEAD" } })

        local config, issues = configuration.resolve()

        assert.same({}, issues)
        assert.equal(20, config.height)
        assert.equal(false, config.icons.enabled)
        assert.equal("󰘬", config.icons.branch)
        assert.equal("relative", config.date_format)
        assert.same({ "HEAD" }, config.log_args)
        reset()
    end)

    it("accepts vim.g.dagit as a function", function()
        reset()
        vim.g.dagit = function()
            return { split = "top" }
        end

        local config, issues = configuration.resolve()

        assert.same({}, issues)
        assert.equal("top", config.split)
        reset()
    end)

    it("reports invalid fields and falls back to defaults", function()
        reset()
        vim.g.dagit = { height = 0, split = "left", mystery = true }

        local config, issues = configuration.resolve()

        assert.equal(16, config.height)
        assert.equal("bottom", config.split)
        assert.truthy(#issues >= 3)
        reset()
    end)

    it("keeps branch-drawing symbols on a terminal that paints them", function()
        reset()
        local saved = {
            ghostty = vim.env.GHOSTTY_RESOURCES_DIR,
            kitty = vim.env.KITTY_WINDOW_ID,
            term = vim.env.TERM,
            program = vim.env.TERM_PROGRAM,
        }
        vim.env.GHOSTTY_RESOURCES_DIR = "/Applications/Ghostty.app/Contents/Resources"
        vim.env.KITTY_WINDOW_ID = nil
        vim.env.TERM = "xterm-256color"
        vim.env.TERM_PROGRAM = "herdr"

        local config = configuration.resolve()

        assert.equal(configuration.defaults().symbols.commit_through, config.symbols.commit_through)
        vim.env.GHOSTTY_RESOURCES_DIR = saved.ghostty
        vim.env.KITTY_WINDOW_ID = saved.kitty
        vim.env.TERM = saved.term
        vim.env.TERM_PROGRAM = saved.program
        reset()
    end)

    it("uses nerd font circles when the terminal does not draw branch glyphs", function()
        reset()
        local saved = {
            ghostty = vim.env.GHOSTTY_RESOURCES_DIR,
            kitty = vim.env.KITTY_WINDOW_ID,
            term = vim.env.TERM,
            program = vim.env.TERM_PROGRAM,
        }
        vim.env.GHOSTTY_RESOURCES_DIR = nil
        vim.env.KITTY_WINDOW_ID = nil
        vim.env.TERM = "xterm-256color"
        vim.env.TERM_PROGRAM = "Apple_Terminal"

        local config = configuration.resolve()

        assert.equal("●", config.symbols.commit)
        assert.equal("│", config.symbols.vertical)
        vim.env.GHOSTTY_RESOURCES_DIR = saved.ghostty
        vim.env.KITTY_WINDOW_ID = saved.kitty
        vim.env.TERM = saved.term
        vim.env.TERM_PROGRAM = saved.program
        reset()
    end)

    it("rejects commit symbols with different display widths", function()
        reset()
        local issues = configuration.validate(vim.tbl_extend("force", configuration.defaults(), {
            symbols = vim.tbl_extend("force", configuration.defaults().symbols, {
                commit = "●",
                commit_through = "●●",
            }),
        }))

        assert.truthy(
            vim.tbl_contains(
                issues,
                "symbols.commit, commit_down, commit_up, and commit_through must share a display width"
            )
        )
        reset()
    end)
end)
