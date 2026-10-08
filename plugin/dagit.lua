--- Command and `<Plug>` maps. Kept free of `require` so startup stays cheap.

if vim.g.loaded_dagit then
    return
end

vim.g.loaded_dagit = true

vim.api.nvim_create_user_command("Dagit", function(opts)
    require("dagit").command(opts)
end, {
    nargs = "*",
    complete = function(arg_lead, cmdline, cursor_pos)
        return require("dagit").complete(arg_lead, cmdline, cursor_pos)
    end,
    desc = "Open and operate the git history log",
})

vim.keymap.set("n", "<Plug>(DagitCopyHash)", function()
    require("dagit").copy_hash()
end, { desc = "Copy the commit hash under the cursor" })

vim.keymap.set("n", "<Plug>(DagitRefresh)", function()
    require("dagit").refresh()
end, { desc = "Reload the git history" })

vim.keymap.set("n", "<Plug>(DagitClose)", function()
    require("dagit").close()
end, { desc = "Close the git history" })

vim.keymap.set("n", "<Plug>(DagitOpen)", function()
    require("dagit").open()
end, { desc = "Open the git history" })
