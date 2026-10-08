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
