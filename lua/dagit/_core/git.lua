--- Read commit history from Git.
---
--- Parsing is separate from the process call so tests can feed fixture text.

local M = {}

local RECORD = "\x1e"
local FIELD = "\x1f"

--- Split a `--decorate=full` decoration list into refs.
---
---@param decoration string
---@return dagit.Ref[]
function M.parse_refs(decoration)
    if decoration == nil or decoration == "" then
        return {}
    end

    local refs = {}

    for part in decoration:gmatch("[^,]+") do
        part = vim.trim(part)

        if part ~= "" then
            local is_head = part:find("^HEAD %-> ") ~= nil
            part = part:gsub("^HEAD %-> ", "")

            local name, kind

            if part == "HEAD" then
                name = "HEAD"
                kind = "head"
            elseif part:find("^refs/heads/") then
                name = part:sub(#"refs/heads/" + 1)
                kind = is_head and "head" or "branch"
            elseif part:find("^refs/remotes/") then
                name = part:sub(#"refs/remotes/" + 1)

                -- `origin/HEAD` repeats the remote's default branch.
                if name ~= "HEAD" and not name:find("/HEAD$") then
                    kind = "remote"
                end
            elseif part:find("^refs/tags/") then
                name = part:sub(#"refs/tags/" + 1)
                kind = "tag"
            elseif part:find("^tag: ") then
                name = part:sub(6)
                kind = "tag"
            end

            if kind and name and name ~= "" then
                refs[#refs + 1] = { name = name, kind = kind }
            end
        end
    end

    return refs
end

--- Parse `git log` output produced by `M.log`.
---
---@param text string
---@return dagit.Commit[]
function M.parse(text)
    local commits = {}

    if text == nil or text == "" then
        return commits
    end

    for record in (text .. RECORD):gmatch("(.-)" .. RECORD) do
        -- `git log --pretty=format:` writes a newline after each record separator.
        record = vim.trim(record)

        if record ~= "" then
            local fields = vim.split(record, FIELD, { plain = true })
            local hash = vim.trim(fields[1] or "")

            if hash ~= "" then
                local parents = {}
                local parent_field = fields[2] or ""

                if parent_field ~= "" then
                    parents = vim.split(parent_field, " ", { trimempty = true })
                end

                commits[#commits + 1] = {
                    hash = hash,
                    parents = parents,
                    author = fields[3] or "",
                    timestamp = fields[4] or "",
                    subject = (fields[5] or ""):gsub("\r", ""),
                    refs = M.parse_refs(fields[6] or ""),
                }
            end
        end
    end

    return commits
end

--- Run a git command in `cwd` and return stdout.
---
---@param git_cmd string
---@param cwd string
---@param args string[]
---@return string? stdout
---@return string? error
local function run(git_cmd, cwd, args)
    local command = { git_cmd, "-C", cwd }
    vim.list_extend(command, args)

    local result = vim.system(command, { text = true }):wait()

    if result.code ~= 0 then
        local message = vim.trim(result.stderr or result.stdout or "git failed")

        if message == "" then
            message = string.format("git exited with status %s", result.code)
        end

        return nil, message
    end

    return result.stdout or "", nil
end

--- Repository root that contains `path`.
---
---@param git_cmd string
---@param path string
---@return string? root
---@return string? error
function M.root(git_cmd, path)
    return run(git_cmd, path, { "rev-parse", "--show-toplevel" })
end

--- Load commits for the history view.
---
---@param git_cmd string
---@param cwd string
---@param log_args string[]
---@param max_count integer
---@return dagit.Commit[]?
---@return string? error
function M.log(git_cmd, cwd, log_args, max_count)
    local root, root_error = M.root(git_cmd, cwd)

    if not root then
        return nil, root_error
    end

    root = vim.trim(root)

    local args = {
        "log",
        "--decorate=full",
        "--pretty=format:%H%x1f%P%x1f%an%x1f%aI%x1f%s%x1f%D%x1e",
        "-n",
        tostring(max_count),
    }

    -- The graph walks children before parents. Plain `git log` can list a
    -- parent first when timestamps tie. `--date-order` keeps date order
    -- without that inversion. An explicit order flag in `log_args` wins.
    local has_order = false

    for _, argument in ipairs(log_args) do
        if argument == "--date-order" or argument == "--topo-order" or argument == "--author-date-order" then
            has_order = true
            break
        end
    end

    if not has_order then
        args[#args + 1] = "--date-order"
    end

    vim.list_extend(args, log_args)

    local text, log_error = run(git_cmd, root, args)

    if not text then
        return nil, log_error
    end

    return M.parse(text), nil
end

--- Branch, remote, and tag names for command completion.
---
---@param git_cmd string
---@param cwd string
---@return string[]
function M.ref_names(git_cmd, cwd)
    local text, err = run(git_cmd, cwd, {
        "for-each-ref",
        "--format=%(refname:short)",
        "refs/heads",
        "refs/remotes",
        "refs/tags",
    })

    if not text or err then
        return {}
    end

    return vim.split(text, "\n", { trimempty = true })
end

return M
