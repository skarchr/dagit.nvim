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
        assert.truthy(lines[1]:find(" HEAD  (", 1, true) ~= nil)
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
        local saw_head_overlay = false

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

            if details and details.virt_text_pos == "overlay" then
                for _, chunk in ipairs(details.virt_text or {}) do
                    if chunk[1] == " HEAD " and chunk[2]:find("DagitHeadMark", 1, true) == 1 then
                        saw_head_overlay = true
                    end
                end
            end
        end

        assert.equal(true, saw_head_overlay)
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

    it("opens on the checked-out commit when it is not the newest row", function()
        vim.cmd("enew")
        local dir = repo()
        git(dir, "checkout", "-q", "feature")
        local head = git(dir, "rev-parse", "HEAD")
        local opened = require("dagit").open({ cwd = dir, height = 12, log_args = { "--all" } })

        assert.equal(true, opened)
        local commit = require("dagit").commit()
        assert.truthy(commit)
        assert.equal(head, commit.hash)

        local row = vim.api.nvim_win_get_cursor(0)[1]
        local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
        assert.truthy(row > 1)
        assert.truthy(vim.startswith(lines[1], "  "))
        assert.truthy(vim.startswith(lines[row], "> "))
        assert.truthy(lines[row]:find(" HEAD  (", 1, true) ~= nil)

        vim.cmd("normal! j")
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_get_current_buf() })
        local moved = require("dagit").commit()
        assert.truthy(moved)
        assert.truthy(moved.hash ~= head)
        assert.equal(true, require("dagit").refresh())
        local kept = require("dagit").commit()
        assert.truthy(kept)
        assert.equal(moved.hash, kept.hash)

        require("dagit").close()
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

    it("toggles the description and files under the commit", function()
        vim.cmd("enew")
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        git(dir, "init", "-b", "main")
        git(dir, "config", "user.email", "dagit@example.com")
        git(dir, "config", "user.name", "Dagit Test")
        git(dir, "config", "commit.gpgsign", "false")
        write(dir .. "/gone.txt", "gone\n")
        write(dir .. "/keep.txt", "keep\n")
        write(dir .. "/old-name.txt", "same\n")
        git(dir, "add", "gone.txt", "keep.txt", "old-name.txt")
        git(dir, "commit", "-m", "first")
        git(dir, "mv", "old-name.txt", "new-name.txt")
        git(dir, "rm", "gone.txt")
        write(dir .. "/keep.txt", "changed\n")
        vim.fn.mkdir(dir .. "/dir", "p")
        write(dir .. "/dir/nested.txt", "new\n")
        git(dir, "add", "-A")
        git(dir, "commit", "-m", "Rework the files", "-m", "Explain the rework.", "-m", "Second paragraph.")

        local opened = require("dagit").open({ cwd = dir, height = 16, log_args = { "--all" } })
        assert.equal(true, opened)

        local function mapped(want)
            local wanted = vim.api.nvim_replace_termcodes(want, true, true, true)

            for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
                if map.lhs == want or map.lhs == wanted then
                    return true
                end
            end

            return false
        end

        assert.equal(true, mapped("<CR>"))
        assert.equal(true, mapped("z"))
        assert.equal(true, mapped("Z"))
        assert.equal(false, mapped("<Space>"))

        local function buffer_text()
            return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
        end

        local function span_group(needle)
            local namespace = vim.api.nvim_create_namespace("dagit")
            local marks = vim.api.nvim_buf_get_extmarks(0, namespace, 0, -1, { details = true })

            for _, mark in ipairs(marks) do
                local details = mark[4]

                if details and details.hl_group and details.end_col then
                    local row = vim.api.nvim_buf_get_lines(0, mark[2], mark[2] + 1, false)[1] or ""
                    local text = row:sub(mark[3] + 1, details.end_col)

                    if text:find(needle, 1, true) then
                        return details.hl_group
                    end
                end
            end
        end

        local function move_to(pattern)
            vim.fn.search(pattern, "w")
            vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_get_current_buf() })
        end

        assert.equal(true, require("dagit").expand())
        local blob = buffer_text()
        local explain = blob:find("Explain the rework.", 1, true)
        local second = blob:find("Second paragraph.", 1, true)
        local modified = blob:find("M keep.txt", 1, true)
        local added = blob:find("A dir/nested.txt", 1, true)
        local deleted = blob:find("D gone.txt", 1, true)
        local renamed = blob:find("R old-name.txt -> new-name.txt", 1, true)

        assert.truthy(explain)
        assert.truthy(explain < second)
        assert.truthy(second < modified)
        assert.truthy(second < added)
        assert.truthy(second < deleted)
        assert.truthy(second < renamed)
        assert.equal("DagitBody", span_group("Explain the rework."))
        assert.equal("DagitFileModified", span_group("M keep.txt"))
        assert.equal("DagitFileAdded", span_group("A dir/nested.txt"))
        assert.equal("DagitFileDeleted", span_group("D gone.txt"))
        assert.equal("DagitFileRenamed", span_group("R old-name.txt -> new-name.txt"))

        local resolved = require("dagit._core.configuration").resolve()
        assert.truthy(blob:find(resolved.symbols.vertical, 1, true) ~= nil)

        local head = require("dagit").commit()
        vim.cmd("normal! j")
        vim.api.nvim_exec_autocmds("CursorMoved", { buffer = vim.api.nvim_get_current_buf() })
        local lines = vim.api.nvim_buf_get_lines(0, 0, 2, false)
        assert.truthy(vim.startswith(lines[1], "> "))
        assert.truthy(lines[2]:find("  Explain the rework.", 1, true) ~= nil)
        assert.equal(head.hash, require("dagit").commit().hash)

        assert.equal(true, require("dagit").refresh())
        assert.truthy(buffer_text():find("Explain the rework.", 1, true) ~= nil)

        move_to(" first")
        local older = require("dagit").commit()
        assert.truthy(older)
        assert.equal("first", older.subject)
        assert.equal(true, require("dagit").expand())
        assert.truthy(buffer_text():find("A gone.txt", 1, true) ~= nil)
        assert.truthy(buffer_text():find("D gone.txt", 1, true) ~= nil)

        assert.equal(true, require("dagit").expand())
        assert.equal(nil, buffer_text():find("A gone.txt", 1, true))
        assert.truthy(buffer_text():find("Explain the rework.", 1, true) ~= nil)

        move_to("Rework the files")
        assert.equal(true, require("dagit").expand())
        assert.equal(nil, buffer_text():find("Explain the rework.", 1, true))

        assert.equal(true, require("dagit").show())
        assert.truthy(buffer_text():find("Explain the rework.", 1, true) ~= nil)
        assert.equal(true, require("dagit").show())
        assert.equal(nil, buffer_text():find("Explain the rework.", 1, true))
        assert.equal(true, require("dagit").show())
        assert.truthy(buffer_text():find("Explain the rework.", 1, true) ~= nil)

        move_to(" first")
        assert.equal(true, require("dagit").show())
        assert.truthy(buffer_text():find("A gone.txt", 1, true) ~= nil)
        assert.truthy(buffer_text():find("Explain the rework.", 1, true) ~= nil)

        assert.equal(true, require("dagit").collapse())
        assert.equal(nil, buffer_text():find("Explain the rework.", 1, true))
        assert.equal(nil, buffer_text():find("A gone.txt", 1, true))
        assert.equal("first", require("dagit").commit().subject)

        require("dagit").close()
    end)

    it("filters commits from the line fixed at the top", function()
        vim.cmd("enew")
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        git(dir, "init", "-b", "trunk")
        git(dir, "config", "user.email", "dagit@example.com")
        git(dir, "config", "user.name", "Dagit Test")
        git(dir, "config", "commit.gpgsign", "false")
        write(dir .. "/f", "root\n")
        git(dir, "add", "f")
        git(dir, "commit", "-m", "root")
        write(dir .. "/f", "tagged\n")
        git(dir, "add", "f")
        git(dir, "commit", "-m", "tagged")
        git(dir, "tag", "v1")
        write(dir .. "/f", "local tip\n")
        git(dir, "add", "f")
        git(dir, "commit", "-m", "local tip")
        git(dir, "checkout", "-b", "side", "HEAD~2")
        write(dir .. "/f", "remote tip\n")
        git(dir, "add", "f")
        git(dir, "commit", "-m", "remote tip")
        git(dir, "update-ref", "refs/remotes/origin/side", "HEAD")
        git(dir, "checkout", "trunk")
        git(dir, "branch", "-D", "side")

        assert.equal(true, require("dagit").open({ cwd = dir, height = 12, log_args = { "--all" } }))

        local view = require("dagit._core.view")

        local function plain(bar)
            return (bar:gsub("%%#[%w]+#", ""))
        end

        local function has(subject)
            local text = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")

            return text:find(subject, 1, true) ~= nil
        end

        assert.equal(view.filter_bar("all"), vim.wo.winbar)
        assert.equal(" [all]  local  remote", plain(vim.wo.winbar))
        assert.truthy(vim.wo.winhighlight:find("WinBar:DagitNormal", 1, true))
        assert.equal("local tip", require("dagit").commit().subject)
        assert.equal(true, has("root"))
        assert.equal(true, has("tagged"))
        assert.equal(true, has("local tip"))
        assert.equal(true, has("remote tip"))

        local maps = vim.api.nvim_buf_get_keymap(0, "n")
        local saw_tab = false
        local saw_shift_tab = false

        for _, map in ipairs(maps) do
            if map.lhs == "<Tab>" then
                saw_tab = true
            end

            if map.lhs == "<S-Tab>" then
                saw_shift_tab = true
            end
        end

        assert.equal(true, saw_tab)
        assert.equal(true, saw_shift_tab)

        assert.equal("local", require("dagit").filter_next())
        assert.equal(view.filter_bar("local"), vim.wo.winbar)
        assert.equal("local tip", require("dagit").commit().subject)
        assert.equal(true, has("root"))
        assert.equal(true, has("tagged"))
        assert.equal(true, has("local tip"))
        assert.equal(false, has("remote tip"))

        assert.equal("remote", require("dagit").filter_next())
        assert.equal(view.filter_bar("remote"), vim.wo.winbar)
        assert.equal(true, has("root"))
        assert.equal(false, has("tagged"))
        assert.equal(false, has("local tip"))
        assert.equal(true, has("remote tip"))
        assert.equal("remote tip", require("dagit").commit().subject)

        assert.equal("all", require("dagit").filter_next())
        assert.equal(view.filter_bar("all"), vim.wo.winbar)
        assert.equal(true, has("remote tip"))
        assert.equal(true, has("local tip"))

        assert.equal("remote", require("dagit").filter_prev())
        assert.equal(view.filter_bar("remote"), vim.wo.winbar)
        assert.equal("all", require("dagit").filter_next())

        require("dagit").close()
    end)

    it("opens on the configured filter", function()
        vim.cmd("enew")
        local configuration = require("dagit._core.configuration")
        configuration.set_user_opts({ filter = "remote" })
        local dir = repo()
        local view = require("dagit._core.view")

        assert.equal(true, require("dagit").open({ cwd = dir, height = 8 }))
        assert.equal(view.filter_bar("remote"), vim.wo.winbar)

        assert.equal("all", require("dagit").filter_next())
        assert.equal(true, require("dagit").open())
        assert.equal(view.filter_bar("all"), vim.wo.winbar)

        require("dagit").close()
        assert.equal(true, require("dagit").open({ cwd = dir, height = 8 }))
        assert.equal(view.filter_bar("remote"), vim.wo.winbar)

        require("dagit").close()
        configuration.set_user_opts(nil)
    end)

    it("completes subcommands", function()
        vim.cmd("runtime plugin/dagit.lua")
        local matches = require("dagit").complete("c", "Dagit c", 0)

        assert.same({ "close", "copy" }, matches)
    end)
end)
