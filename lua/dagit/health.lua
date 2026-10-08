--- Health checks for `:checkhealth dagit`.

local configuration = require("dagit._core.configuration")

local M = {}

--- Configuration problems for the current user settings.
---
---@return string[]
function M.get_issues()
    local _, issues = configuration.resolve()

    return issues
end

function M.check()
    local config, issues = configuration.resolve()

    vim.health.start("dagit")

    if vim.fn.executable(config.git_cmd) == 1 then
        local version = vim.system({ config.git_cmd, "--version" }, { text = true }):wait()
        vim.health.ok(vim.trim(version.stdout or "git executable found"))
    else
        vim.health.error(string.format("Cannot execute %q. Install Git or set git_cmd.", config.git_cmd))
    end

    if #issues == 0 then
        vim.health.ok("Configuration is valid")
    else
        for _, issue in ipairs(issues) do
            vim.health.error(issue)
        end

        vim.health.warn("Invalid settings were ignored. dagit is using its defaults.")
    end

    local root = vim.system({ config.git_cmd, "rev-parse", "--show-toplevel" }, { text = true }):wait()

    if root.code == 0 then
        vim.health.ok("Repository: " .. vim.trim(root.stdout or ""))
    else
        vim.health.info("The current directory is not inside a Git repository")
    end
end

return M
