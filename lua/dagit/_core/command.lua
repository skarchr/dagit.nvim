--- `:Dagit` subcommands.
---
--- The command is registered from `plugin/dagit.lua`. This module stays
--- unloaded until the user runs or completes the command.

local git = require("dagit._core.git")
local configuration = require("dagit._core.configuration")
local view = require("dagit._core.view")

local M = {}

local SUBCOMMANDS = { "log", "refresh", "close", "copy" }

---@param opts { fargs: string[] }
function M.run(opts)
    local fargs = opts.fargs or {}
    local subcommand = fargs[1] or "log"
    local rest = #fargs > 1 and vim.list_slice(fargs, 2, #fargs) or {}

    if subcommand == "log" then
        ---@type dagit.OpenOpts
        local open_opts = {}

        if #rest > 0 then
            open_opts.log_args = rest
        end

        view.open(open_opts)
    elseif subcommand == "refresh" then
        view.refresh()
    elseif subcommand == "close" then
        view.close()
    elseif subcommand == "copy" then
        view.copy_hash()
    else
        vim.notify("Unknown command: " .. subcommand, vim.log.levels.ERROR, { title = "dagit" })
    end
end

---@param arg_lead string
---@param cmdline string
---@return string[]
function M.complete(arg_lead, cmdline)
    local words = vim.split(cmdline, "%s+")
    local dagit_index = 1

    for index, word in ipairs(words) do
        if word == "Dagit" or word:find("Dagit$") then
            dagit_index = index
            break
        end
    end

    local subcommand = words[dagit_index + 1]
    local typing_subcommand = #words <= dagit_index + 1

    if typing_subcommand then
        return vim.tbl_filter(function(name)
            return vim.startswith(name, arg_lead)
        end, SUBCOMMANDS)
    end

    if subcommand ~= "log" then
        return {}
    end

    local config = configuration.resolve()
    local names = git.ref_names(config.git_cmd, vim.fn.getcwd())

    return vim.tbl_filter(function(name)
        return vim.startswith(name, arg_lead)
    end, names)
end

return M
