--- Run the spec files with Neovim as the Lua runtime.
---
--- Specs use a small busted-shaped `describe` / `it` / `assert` surface so
--- `make test` works without a luarocks install. `busted .` runs the same
--- files when busted is installed (see `.busted`).

local source = debug.getinfo(1, "S").source:sub(2)
local root = vim.fn.fnamemodify(source, ":h:h")

vim.opt.rtp:prepend(root)
package.path = root .. "/lua/?.lua;" .. root .. "/lua/?/init.lua;" .. root .. "/spec/?.lua;" .. package.path

local builtin_assert = assert

assert = setmetatable({}, {
    __call = function(_, ...)
        return builtin_assert(...)
    end,
})

---@param expected any
---@param actual any
function assert.same(expected, actual)
    if vim.deep_equal(expected, actual) then
        return
    end

    error(
        "expected "
            .. vim.inspect(expected)
            .. "\ngot      "
            .. vim.inspect(actual),
        2
    )
end

---@param expected any
---@param actual any
function assert.equal(expected, actual)
    if expected == actual then
        return
    end

    error("expected " .. vim.inspect(expected) .. "\ngot      " .. vim.inspect(actual), 2)
end

---@param value any
function assert.truthy(value)
    if not value then
        error("expected truthy, got " .. vim.inspect(value), 2)
    end
end

---@param value any
function assert.falsy(value)
    if value then
        error("expected falsy, got " .. vim.inspect(value), 2)
    end
end

local stack = {}
local passed = 0
local failed = 0
local failures = {}

---@param name string
---@param fn fun()
function describe(name, fn)
    stack[#stack + 1] = name
    fn()
    stack[#stack] = nil
end

---@param name string
---@param fn fun()
function it(name, fn)
    local title = table.concat(stack, " ") .. " " .. name
    local ok, err = xpcall(fn, debug.traceback)

    if ok then
        passed = passed + 1
        io.write(".")
    else
        failed = failed + 1
        io.write("F")
        failures[#failures + 1] = title .. "\n" .. tostring(err)
    end
end

local specs = vim.fs.find(function(name)
    return name:find("_spec%.lua$") ~= nil
end, { path = root .. "/spec", type = "file", limit = math.huge })

table.sort(specs)

for _, spec in ipairs(specs) do
    dofile(spec)
end

io.write("\n")

for _, failure in ipairs(failures) do
    io.write("\nFAIL: " .. failure .. "\n")
end

io.write(string.format("\n%d passed, %d failed\n", passed, failed))

if failed > 0 then
    os.exit(1)
end
