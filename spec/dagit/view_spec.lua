local function git(dir, ...)
    local result = vim.system({ "git", "-C", dir, ... }, { text = true }):wait()

    if result.code ~= 0 then
        error(vim.trim(result.stderr or result.stdout or "git failed"))
    end

    return vim.trim(result.stdout or "")
end

local function write(path, text)
    local file = assert(io.open(path, "w"))
    file:write(text)
    file:close()
end

local function repo()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    git(dir, "init", "-b", "main")
    git(dir, "config", "user.email", "dagit@example.com")
    git(dir, "config", "user.name", "Dagit Test")
    git(dir, "config", "commit.gpgsign", "false")
    write(dir .. "/README.md", "one\n")
    git(dir, "add", "README.md")
    git(dir, "commit", "-m", "first")
    git(dir, "checkout", "-b", "feature")
    write(dir .. "/README.md", "two\n")
    git(dir, "add", "README.md")
    git(dir, "commit", "-m", "feature work")
    git(dir, "checkout", "main")
    git(dir, "merge", "--no-ff", "feature", "-m", "Merge pull request #7")

    return dir
end

describe("view", function()
    it("opens a bottom split and copies the hash under the cursor", function()
        vim.cmd("enew")
        local dir = repo()
        local head = git(dir, "rev-parse", "HEAD")
        local guicursor = vim.o.guicursor
        local opened = require("dagit").open({ cwd = dir, height = 12, log_args = { "--all" } })

        assert.equal(true, opened)
        assert.equal("dagit", vim.bo.filetype)
        assert.equal(true, vim.wo.cursorline)
        assert.equal(false, vim.wo.wrap)
        assert.truthy(vim.wo.winhighlight:find("Normal:DagitNormal", 1, true))
        assert.truthy(vim.wo.winhighlight:find("NormalNC:DagitNormal", 1, true))
        assert.truthy(vim.wo.winhighlight:find("Cursor:DagitCursor", 1, true))
        assert.truthy(vim.o.guicursor:find("DagitCursor", 1, true) ~= nil)
        assert.equal("nofile", vim.bo.buftype)

        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        assert.truthy(#lines >= 3)

        local saw_merge = false

        for _, line in ipairs(lines) do
            if line:find("Merge pull request #7", 1, true) then
                saw_merge = true
            end
        end

        assert.equal(true, saw_merge)
        local resolved = require("dagit._core.configuration").resolve()
        assert.truthy(vim.startswith(lines[1], "> " .. resolved.symbols.commit_down))
        assert.truthy(lines[1]:find(head:sub(1, 7), 1, true) ~= nil)
        assert.truthy(lines[1]:find("HEAD -> ", 1, true) ~= nil)
        assert.truthy(lines[1]:find("main)", 1, true) ~= nil)
        assert.truthy(lines[2]:find("feature)", 1, true) ~= nil)

        local hash = require("dagit").copy_hash()
        assert.equal(head, hash)
        assert.equal(head, vim.fn.getreg('"'))

        vim.cmd("normal! j")
        -- `nvim -l` does not always emit CursorMoved for :normal. Fire it so
        -- the selection mark is tested the same way an interactive session is.
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_get_current_buf() })
        local moved = vim.api.nvim_buf_get_lines(0, 0, 2, false)
        assert.truthy(vim.startswith(moved[1], "  " .. resolved.symbols.commit_down))
        assert.truthy(vim.startswith(moved[2], "> "))
        local second = require("dagit").commit()
        assert.truthy(second)
        assert.truthy(second.hash ~= head)

        local marks = vim.api.nvim_buf_get_extmarks(0, vim.api.nvim_create_namespace("dagit"), 0, -1, {
            details = true,
        })
        local highlighted_rows = {}
        local selected_author = false
        local saw_time = false

        for _, mark in ipairs(marks) do
            local details = mark[4]

            if details and details.line_hl_group == "CursorLine" then
                highlighted_rows[#highlighted_rows + 1] = mark[2]
            end

            if details and details.virt_text_pos == "right_align" and mark[2] == 1 then
                for _, chunk in ipairs(details.virt_text) do
                    if chunk[2] == "DagitAuthorLine" or chunk[2] == "DagitLine" then
                        selected_author = true
                    end

                    if chunk[1]:find("%d%d:%d%d") then
                        saw_time = true
                    end
                end
            end
        end

        assert.same({ 1 }, highlighted_rows)
        assert.equal(true, selected_author)
        assert.equal(true, saw_time)

        local maps = vim.api.nvim_buf_get_keymap(0, "n")
        local found = false

        for _, map in ipairs(maps) do
            if map.lhs == "<C-O>" or map.lhs == "<C-o>" then
                found = true
            end
        end

        assert.equal(true, found)

        require("dagit").close()
        assert.equal(nil, require("dagit").commit())
        assert.equal(guicursor, vim.o.guicursor)
    end)

    it("shows an error when the directory is not a repository", function()
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")

        local opened = require("dagit").open({ cwd = dir, height = 8 })

        assert.equal(false, opened)
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        assert.truthy(lines[1]:find("not a git repository", 1, true) ~= nil)
        require("dagit").close()
    end)

    it("completes subcommands", function()
        vim.cmd("runtime plugin/dagit.lua")
        local matches = require("dagit").complete("c", "Dagit c", 0)

        assert.same({ "close", "copy" }, matches)
    end)
end)
