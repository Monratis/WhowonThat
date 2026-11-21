-- Scenario runner: lua tools/sim/run.lua [name-filter]   (run from the addon folder)
-- Every file tools/scenarios/*.lua returns a list of { name, fn }. A scenario fails on an assertion, a Lua error, or
-- any error the addon sent to the game's error handler (the simulator records them).
package.path = "tools/sim/?.lua;" .. package.path
local World = require("world")

local filter = arg and arg[1]
local passed, failed = 0, 0
local missing = {}

local T = {}
T.__index = T
function T.fail(msg) error({ assertion = msg }, 0) end
function T.ok(v, msg) if not v then T.fail(msg or "expected a true value") end end
function T.eq(a, b, msg)
    if a ~= b then T.fail((msg and msg .. ": " or "") .. "expected " .. tostring(b) .. ", got " .. tostring(a)) end
end
function T.has(text, needle, msg)
    if not tostring(text):find(needle, 1, true) then
        T.fail((msg or "text does not contain") .. " '" .. needle .. "' in:\n" .. tostring(text))
    end
end
function T.lacks(text, needle, msg)
    if tostring(text):find(needle, 1, true) then
        T.fail((msg or "text must not contain") .. " '" .. needle .. "' in:\n" .. tostring(text))
    end
end
function T.count(list, n, msg) T.eq(#list, n, msg or "number of entries") end

local dir = "tools/scenarios"
local p = io.popen('dir /b "' .. dir:gsub("/", "\\") .. '\\*.lua" 2>nul')
local files = {}
for line in p:lines() do files[#files + 1] = line end
p:close()
table.sort(files)

for _, file in ipairs(files) do
    local suite = dofile(dir .. "/" .. file)
    for _, test in ipairs(suite) do
        local label = file:gsub("%.lua$", "") .. ": " .. test[1]
        if not filter or label:find(filter, 1, true) then
            local world = World.new({ root = "." })
            local ok, err = pcall(test[2], world, T)
            for _, c in ipairs(world.clients) do
                if ok and #c.errors > 0 then
                    ok, err = false, { assertion = "addon error on " .. c.name .. ": " .. c.errors[1] }
                end
                for k in pairs(c.missing) do missing[k] = true end
            end
            if ok then
                passed = passed + 1
                print("PASS  " .. label)
            else
                failed = failed + 1
                print("FAIL  " .. label)
                print("      " .. (type(err) == "table" and err.assertion or tostring(err)):gsub("\n", "\n      "))
            end
        end
    end
end

local names = {}
for k in pairs(missing) do names[#names + 1] = k end
table.sort(names)
if #names > 0 and os.getenv("SIM_MISSING") then
    print("\nAPI the addon touched that the simulator does not model:\n  " .. table.concat(names, "\n  "))
end
print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
