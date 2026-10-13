local git = require("dagit._core.git")

describe("git.parse_refs", function()
    it("reads full decorations and skips remote HEAD", function()
        local refs = git.parse_refs(
            "HEAD -> refs/heads/main, refs/remotes/origin/main, refs/remotes/origin/HEAD, refs/tags/v1.0.0"
        )

        assert.same({
            { name = "main", kind = "head" },
            { name = "origin/main", kind = "remote" },
            { name = "v1.0.0", kind = "tag" },
        }, refs)
    end)

    it("reads a plain local branch", function()
        assert.same({ { name = "feature", kind = "branch" } }, git.parse_refs("refs/heads/feature"))
    end)
end)

describe("git.parse", function()
    it("parses record-separated log output", function()
        local unit = "\x1f"
        local record = "\x1e"
        local text = table.concat({
            "abc",
            "parent1 parent2",
            "Ada",
            "2026-10-08T10:00:00+02:00",
            "Switch the build",
            "HEAD -> refs/heads/main",
        }, unit) .. record

        local commits = git.parse(text)

        assert.equal(1, #commits)
        assert.equal("abc", commits[1].hash)
        assert.same({ "parent1", "parent2" }, commits[1].parents)
        assert.equal("Ada", commits[1].author)
        assert.equal("Switch the build", commits[1].subject)
        assert.equal("head", commits[1].refs[1].kind)
    end)

    it("ignores the newline git inserts after each record", function()
        local text = "aaa\x1fparent\x1fAda\x1f2026-01-01T00:00:00Z\x1ffirst\x1f\x1e\n"
            .. "bbb\x1f\x1fAda\x1f2026-01-02T00:00:00Z\x1fsecond\x1f\x1e\n"

        local commits = git.parse(text)

        assert.equal(2, #commits)
        assert.equal("aaa", commits[1].hash)
        assert.equal("bbb", commits[2].hash)
        assert.equal("second", commits[2].subject)
    end)

    it("parses a root commit with no parents", function()
        local text = "abc\x1f\x1fAda\x1f2026-01-01T00:00:00Z\x1ffirst\x1f\x1e"
        local commits = git.parse(text)

        assert.same({}, commits[1].parents)
        assert.equal("first", commits[1].subject)
    end)
end)

describe("git.parse_body", function()
    it("drops blank edges and keeps a paragraph break", function()
        assert.same({ "Explain the rework.", "", "Second paragraph." }, git.parse_body("\nExplain the rework.\n\nSecond paragraph.\n"))
    end)

    it("returns nothing for a subject-only commit", function()
        assert.same({}, git.parse_body("\n"))
    end)

    it("drops a leading byte-order mark", function()
        assert.same({ "Show dates (not time) for expiration" }, git.parse_body("\239\187\191Show dates (not time) for expiration\n"))
    end)
end)

describe("git.parse_name_status", function()
    it("reads added, modified, deleted, and renamed paths", function()
        local text = table.concat({
            "M",
            "lua/a.lua",
            "A",
            "dir with space/file.txt",
            "D",
            "gone.txt",
            "R100",
            "old-name.txt",
            "new-name.txt",
            "C075",
            "source.txt",
            "copy.txt",
        }, "\0") .. "\0"

        assert.same({
            { status = "M", path = "lua/a.lua", old_path = nil },
            { status = "A", path = "dir with space/file.txt", old_path = nil },
            { status = "D", path = "gone.txt", old_path = nil },
            { status = "R", path = "new-name.txt", old_path = "old-name.txt" },
            { status = "C", path = "copy.txt", old_path = "source.txt" },
        }, git.parse_name_status(text))
    end)
end)

describe("git.apply_reachability", function()
    it("separates local-only commits from remote-only commits", function()
        local commits = {
            { hash = "aaa" },
            { hash = "bbb" },
            { hash = "ccc" },
        }

        git.apply_reachability(commits, "bbb\nccc\n", "aaa\nbbb\n")

        assert.equal(true, commits[1].local_only)
        assert.equal(false, commits[1].remote_only)
        assert.equal(true, commits[1].on_local)
        assert.equal(false, commits[1].on_remote)
        assert.equal(false, commits[2].local_only)
        assert.equal(false, commits[2].remote_only)
        assert.equal(true, commits[2].on_local)
        assert.equal(true, commits[2].on_remote)
        assert.equal(false, commits[3].local_only)
        assert.equal(true, commits[3].remote_only)
        assert.equal(false, commits[3].on_local)
        assert.equal(true, commits[3].on_remote)
    end)

    it("does not mark commits when the remote listing is missing", function()
        local commits = { { hash = "aaa" } }

        git.apply_reachability(commits, nil, "aaa\n")

        assert.equal(false, commits[1].local_only)
        assert.equal(false, commits[1].remote_only)
        assert.equal(true, commits[1].on_local)
        assert.equal(true, commits[1].on_remote)
    end)
end)

describe("git.apply_upstream_gone", function()
    it("marks a local branch whose upstream track is gone", function()
        local commits = {
            {
                hash = "aaa",
                refs = {
                    { name = "feature", kind = "branch" },
                    { name = "feature", kind = "head" },
                    { name = "origin/feature", kind = "remote" },
                    { name = "trunk", kind = "branch" },
                },
            },
        }

        git.apply_upstream_gone(commits, "feature\t[gone]\ntrunk\t[ahead 1]\nplain\t\n")

        assert.equal(true, commits[1].refs[1].upstream_gone)
        assert.equal(true, commits[1].refs[2].upstream_gone)
        assert.equal(false, commits[1].refs[3].upstream_gone)
        assert.equal(false, commits[1].refs[4].upstream_gone)

        git.apply_upstream_gone(commits, nil)

        assert.equal(false, commits[1].refs[1].upstream_gone)
    end)
end)

describe("git.log", function()
    local function run_git(dir, ...)
        local result = vim.system({ "git", "-C", dir, ... }, { text = true }):wait()
        assert.equal(0, result.code, result.stderr or result.stdout)
    end

    it("marks commits that only exist locally and branches that are not local", function()
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        run_git(dir, "init", "-q")
        run_git(dir, "config", "user.email", "a@b.c")
        run_git(dir, "config", "user.name", "Test")
        run_git(dir, "config", "commit.gpgsign", "false")

        local function commit(message, date)
            local file = assert(io.open(dir .. "/f", "a"))
            file:write(message .. "\n")
            file:close()
            run_git(dir, "add", "f")
            vim.env.GIT_AUTHOR_DATE = date
            vim.env.GIT_COMMITTER_DATE = date
            run_git(dir, "commit", "-qm", message)
        end

        commit("base", "2026-01-01T00:00:00")
        commit("pushed", "2026-01-02T00:00:00")
        run_git(dir, "branch", "-M", "main")
        run_git(dir, "update-ref", "refs/remotes/origin/main", "HEAD")
        commit("ahead", "2026-01-03T00:00:00")
        run_git(dir, "checkout", "-q", "-b", "topic", "HEAD~1")
        commit("remote-topic", "2026-01-04T00:00:00")
        run_git(dir, "update-ref", "refs/remotes/origin/topic", "HEAD")
        run_git(dir, "checkout", "-q", "main")
        run_git(dir, "branch", "-D", "topic")
        vim.env.GIT_AUTHOR_DATE = nil
        vim.env.GIT_COMMITTER_DATE = nil

        local commits, err = git.log("git", dir, { "--all" }, 20)
        assert.equal(nil, err)

        local by_subject = {}

        for _, item in ipairs(commits) do
            by_subject[item.subject] = item
        end

        assert.equal(true, by_subject.ahead.local_only)
        assert.equal(false, by_subject.ahead.remote_only)
        assert.equal(true, by_subject.ahead.on_local)
        assert.equal(false, by_subject.ahead.on_remote)
        assert.equal(false, by_subject["remote-topic"].local_only)
        assert.equal(true, by_subject["remote-topic"].remote_only)
        assert.equal(false, by_subject["remote-topic"].on_local)
        assert.equal(true, by_subject["remote-topic"].on_remote)
        assert.equal(false, by_subject.pushed.local_only)
        assert.equal(false, by_subject.pushed.remote_only)
        assert.equal(true, by_subject.pushed.on_local)
        assert.equal(true, by_subject.pushed.on_remote)
        assert.equal(false, by_subject.base.local_only)
        assert.equal(false, by_subject.base.remote_only)
        assert.equal(true, by_subject.base.on_local)
        assert.equal(true, by_subject.base.on_remote)
    end)

    it("omits stash commits unless refs/stash is requested", function()
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        run_git(dir, "init", "-q", "-b", "trunk")
        run_git(dir, "config", "user.email", "a@b.c")
        run_git(dir, "config", "user.name", "Test")
        run_git(dir, "config", "commit.gpgsign", "false")

        local file = assert(io.open(dir .. "/f", "w"))
        file:write("kept\n")
        file:close()
        run_git(dir, "add", "f")
        run_git(dir, "commit", "-qm", "kept")

        local dirty = assert(io.open(dir .. "/f", "a"))
        dirty:write("stashed\n")
        dirty:close()
        local extra = assert(io.open(dir .. "/extra", "w"))
        extra:write("untracked\n")
        extra:close()
        run_git(dir, "stash", "push", "-u", "-m", "hidden stash")

        local function subjects(log_args)
            local commits, err = git.log("git", dir, log_args, 20)
            assert.equal(nil, err)

            local found = {}

            for _, item in ipairs(commits) do
                found[#found + 1] = item.subject
            end

            return found
        end

        local function has_prefix(list, prefix)
            for _, subject in ipairs(list) do
                if subject:sub(1, #prefix) == prefix then
                    return true
                end
            end

            return false
        end

        local hidden = subjects({ "--all" })

        assert.equal(true, has_prefix(hidden, "kept"))
        assert.falsy(has_prefix(hidden, "On trunk: hidden stash"))
        assert.falsy(has_prefix(hidden, "index on trunk:"))
        assert.falsy(has_prefix(hidden, "untracked files on trunk:"))

        local shown = subjects({ "--all", "refs/stash" })

        assert.truthy(has_prefix(shown, "On trunk: hidden stash"))
        assert.truthy(has_prefix(shown, "index on trunk:"))
        assert.truthy(has_prefix(shown, "untracked files on trunk:"))
    end)

    it("marks a branch whose upstream ref was deleted", function()
        local dir = vim.fn.tempname()
        vim.fn.mkdir(dir, "p")
        run_git(dir, "init", "-q", "-b", "trunk")
        run_git(dir, "config", "user.email", "a@b.c")
        run_git(dir, "config", "user.name", "Test")
        run_git(dir, "config", "commit.gpgsign", "false")
        run_git(dir, "config", "remote.origin.url", dir)
        run_git(dir, "config", "remote.origin.fetch", "+refs/heads/*:refs/remotes/origin/*")

        local file = assert(io.open(dir .. "/f", "w"))
        file:write("base\n")
        file:close()
        run_git(dir, "add", "f")
        run_git(dir, "commit", "-qm", "base")
        run_git(dir, "update-ref", "refs/remotes/origin/trunk", "HEAD")
        run_git(dir, "checkout", "-q", "-b", "feature")

        local extra = assert(io.open(dir .. "/f", "a"))
        extra:write("feature\n")
        extra:close()
        run_git(dir, "add", "f")
        run_git(dir, "commit", "-qm", "feature only")
        run_git(dir, "config", "branch.feature.remote", "origin")
        run_git(dir, "config", "branch.feature.merge", "refs/heads/feature")

        local commits, err = git.log("git", dir, { "--all" }, 20)
        assert.equal(nil, err)

        local feature_ref = nil

        for _, item in ipairs(commits) do
            if item.subject == "feature only" then
                assert.equal(true, item.local_only)

                for _, ref in ipairs(item.refs) do
                    if ref.name == "feature" then
                        feature_ref = ref
                    end
                end
            end

            if item.subject == "base" then
                for _, ref in ipairs(item.refs) do
                    if ref.name == "trunk" then
                        assert.equal(false, ref.upstream_gone)
                    end
                end
            end
        end

        assert.truthy(feature_ref)
        assert.equal(true, feature_ref.upstream_gone)
    end)
end)
