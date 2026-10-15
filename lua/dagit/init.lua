--- Public API for dagit.
---
--- Changing a function signature here in an incompatible way requires a new
--- major version. Modules under `dagit._core` are private.

local configuration = require("dagit._core.configuration")

local M = {}

--- Override the default configuration.
---
--- This does not open a window and does not install keymaps. The history
--- view works without calling `setup()`. `vim.g.dagit` is merged underneath
--- `opts` when both are set.
---
---@param opts dagit.Opts?
---@return dagit.Config
function M.setup(opts)
    configuration.set_user_opts(opts or {})

    local config, issues = configuration.resolve()

    if #issues > 0 then
        vim.notify(
            "Invalid configuration. Using defaults.\n" .. table.concat(issues, "\n"),
            vim.log.levels.ERROR,
            { title = "dagit" }
        )
    end

    return config
end

--- Open the git history in a horizontal split.
---
---@param opts dagit.OpenOpts?
---@return boolean opened
function M.open(opts)
    return require("dagit._core.view").open(opts)
end

--- Close the git history window.
function M.close()
    require("dagit._core.view").close()
end

--- Reload the open git history.
---
---@return boolean
function M.refresh()
    return require("dagit._core.view").refresh()
end

--- Commit displayed on the cursor row.
---
---@return dagit.Commit?
function M.commit()
    return require("dagit._core.view").commit()
end

--- Copy the full hash of the commit under the cursor.
---
---@return string?
function M.copy_hash()
    return require("dagit._core.view").copy_hash()
end

--- Show or hide the description and files for the commit under the cursor.
---
---@return boolean
function M.expand()
    return require("dagit._core.view").expand()
end

--- Show or hide the description and files for the commit under the cursor.
---
---@return boolean
function M.show()
    return require("dagit._core.view").show()
end

--- Hide the description and files under every commit.
---
---@return boolean
function M.collapse()
    return require("dagit._core.view").collapse()
end

--- Select the next commit filter and redraw.
---
--- The names, in order, are `all`, `local`, `remote`, and `head`.
---
---@return string? filter Active filter, or nil when the history is not focused.
function M.filter_next()
    return require("dagit._core.view").filter_next()
end

--- Select the previous commit filter and redraw.
---
---@return string? filter Active filter, or nil when the history is not focused.
function M.filter_prev()
    return require("dagit._core.view").filter_prev()
end

--- Run a `:Dagit` invocation.
---
---@param opts { fargs: string[] }
function M.command(opts)
    require("dagit._core.command").run(opts)
end

--- Completion for `:Dagit`.
---
---@param arg_lead string
---@param cmdline string
---@param _ integer
---@return string[]
function M.complete(arg_lead, cmdline, _)
    return require("dagit._core.command").complete(arg_lead, cmdline)
end

return M
