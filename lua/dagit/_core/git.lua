--- Read commit history from Git.
---
--- Parsing is separate from the process call so tests can feed fixture text.

local M = {}

local RECORD = "\x1e"
local FIELD = "\x1f"
-- A copied commit message sometimes starts with a byte-order mark. It is
-- not spacing, and a terminal draws it as a stray glyph.
local BOM = "\239\187\191"

--- Drop a leading UTF-8 byte-order mark.
---
---@param text string
---@return string
local function strip_bom(text)
    return (text:gsub("^" .. BOM, ""))
end

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
                    subject = strip_bom((fields[5] or ""):gsub("\r", "")),
                    refs = M.parse_refs(fields[6] or ""),
                }
            end
        end
    end

    return commits
end

--- Commit description, without the subject and without blank edges.
---
---@param text string?
---@return string[]
function M.parse_body(text)
    local normalized = (text or ""):gsub("\r\n", "\n"):gsub("\r", "\n")
    local lines = vim.split(normalized, "\n", { plain = true })
    local first = 1
    local last = #lines

    while first <= last and lines[first] == "" do
        first = first + 1
    end

    while last >= first and lines[last] == "" do
        last = last - 1
    end

    local body = {}

    for index = first, last do
        body[#body + 1] = strip_bom(lines[index])
    end

    return body
end

--- Parse `git diff-tree -z --name-status` output.
---
--- A rename or a copy is `R100`, the old path, then the new path. Each field
--- ends with NUL, so a path may contain spaces.
---
---@param text string?
---@return dagit.CommitFile[]
function M.parse_name_status(text)
    local files = {}

    if text == nil or text == "" then
        return files
    end

    local parts = vim.split(text, "\0", { plain = true })
    local index = 1

    while index <= #parts do
        local raw = parts[index]

        if raw == nil or raw == "" then
            break
        end

        local status = raw:sub(1, 1)
        index = index + 1

        local path = parts[index]

        if path == nil or path == "" then
            break
        end

        index = index + 1
        local old_path = nil

        if status == "R" or status == "C" then
            old_path = path
            path = parts[index]

            if path == nil or path == "" then
                break
            end

            index = index + 1
        end

        files[#files + 1] = {
            status = status,
            path = path,
            old_path = old_path,
        }
    end

    return files
end

---@param text string?
---@return table<string, boolean>?
local function hash_set(text)
    if text == nil then
        return nil
    end

    local set = {}

    for line in text:gmatch("[^\r\n]+") do
        local hash = vim.trim(line)

        if hash ~= "" then
            set[hash] = true
        end
    end

    return set
end

--- Mark commits that are only local, and commits that are only on a remote.
---
--- `remote_text` and `local_text` are `git rev-list` output. A missing
--- remote listing leaves the colors unchanged. A missing local listing does
--- not mute the graph.
---
---@param commits dagit.Commit[]
---@param remote_text string?
---@param local_text string?
function M.apply_reachability(commits, remote_text, local_text)
    local remote = hash_set(remote_text)
    local local_set = hash_set(local_text)

    for _, commit in ipairs(commits) do
        if not remote then
            commit.local_only = false
            commit.remote_only = false
        else
            local on_remote = remote[commit.hash] == true
            local on_local = local_set == nil or local_set[commit.hash] == true

            commit.local_only = not on_remote
            commit.remote_only = on_remote and not on_local
        end
    end
end

--- Mark local branches whose configured upstream ref has been deleted.
---
--- `text` is `git for-each-ref` output: a branch name, a tab, then
--- `%(upstream:track)`. `[gone]` means the upstream is configured and the
--- remote-tracking ref is missing. A failed listing leaves every ref clear.
---
---@param commits dagit.Commit[]
---@param text string?
function M.apply_upstream_gone(commits, text)
    local gone = {}

    if text then
        for line in text:gmatch("[^\r\n]+") do
            local name, track = line:match("^(.-)\t(.*)$")

            if name and vim.trim(track) == "[gone]" then
                gone[name] = true
            end
        end
    end

    for _, commit in ipairs(commits) do
        for _, ref in ipairs(commit.refs or {}) do
            local local_branch = ref.kind == "branch" or ref.kind == "head"
            ref.upstream_gone = local_branch and gone[ref.name] == true
        end
    end
end

--- `git rev-list` limited to commits in the history window.
---
--- Parents that are not in `commits` are excluded, so the walk stops at the
--- edge of the loaded log instead of reading the whole repository.
---
---@param commits dagit.Commit[]
---@param tips string[]
---@return string[]
local function rev_list_window(commits, tips)
    local known = {}

    for _, commit in ipairs(commits) do
        known[commit.hash] = true
    end

    local args = { "rev-list" }
    vim.list_extend(args, tips)

    local excluded = {}

    for _, commit in ipairs(commits) do
        for _, parent in ipairs(commit.parents) do
            if not known[parent] and not excluded[parent] then
                excluded[parent] = true
                args[#args + 1] = "^" .. parent
            end
        end
    end

    return args
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

--- `--all` includes `refs/stash`. Drop that ref unless the caller named it.
---
---@param log_args string[]
---@return string[]
local function without_stashes(log_args)
    local args = {}

    for _, argument in ipairs(log_args) do
        if argument == "--all" then
            args[#args + 1] = "--exclude=refs/stash"
        end

        args[#args + 1] = argument
    end

    return args
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

    vim.list_extend(args, without_stashes(log_args))

    local text, log_error = run(git_cmd, root, args)

    if not text then
        return nil, log_error
    end

    local commits = M.parse(text)
    local remote_text = run(git_cmd, root, rev_list_window(commits, { "--remotes" }))
    local local_text = run(git_cmd, root, rev_list_window(commits, { "--branches", "HEAD" }))

    M.apply_reachability(commits, remote_text, local_text)

    local upstream_text = run(git_cmd, root, {
        "for-each-ref",
        "--format=%(refname:short)%09%(upstream:track)",
        "refs/heads",
    })

    M.apply_upstream_gone(commits, upstream_text)

    return commits, nil
end

--- Description and changed files for one commit.
---
--- The description is the commit body. Files come from the first-parent diff,
--- so a merge lists what it brought in. Rename detection is on.
---
---@param git_cmd string
---@param cwd string
---@param hash string
---@return dagit.CommitDetail?
---@return string? error
function M.changes(git_cmd, cwd, hash)
    local root, root_error = M.root(git_cmd, cwd)

    if not root then
        return nil, root_error
    end

    root = vim.trim(root)

    local body_text, body_error = run(git_cmd, root, { "log", "-1", "--format=%b", hash })

    if not body_text then
        return nil, body_error
    end

    local status_text, status_error = run(git_cmd, root, {
        "diff-tree",
        "--no-commit-id",
        "--root",
        "-r",
        "-m",
        "--first-parent",
        "-M",
        "--name-status",
        "-z",
        hash,
    })

    if not status_text then
        return nil, status_error
    end

    return {
        body = M.parse_body(body_text),
        files = M.parse_name_status(status_text),
    }, nil
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
