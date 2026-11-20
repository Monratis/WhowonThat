-- Load test: runs every file of the .toc in order with a stub of the game API, the way the game would.
-- Catches load-time errors and imports that are nil (a name imported before the file that exports it).
-- Run from the addon folder: lua tools/loadtest.lua
local stub
stub = setmetatable({}, {
  __index = function() return stub end,
  __call = function() return stub end,
  __concat = function() return "" end,
  __len = function() return 0 end,
  __lt = function() return false end, __le = function() return false end,
})
setmetatable(_G, { __index = function(_, k)
  if k == "C_LootHistory" or k == "Enum" then return nil end
  return stub
end })

local ns, files, failed = {}, {}, 0
for line in io.lines("WhoWonThat.toc") do
  local f = line:match("^(%S+%.lua)%s*$")
  if f then files[#files + 1] = f end
end
for _, f in ipairs(files) do
  local chunk, err = loadfile(f)
  local ok, e = false, err
  if chunk then ok, e = pcall(chunk, "WhoWonThat", ns) end
  if not ok then failed = failed + 1; print("FAIL " .. f .. "  " .. tostring(e)) end
end
for _, f in ipairs(files) do
  for line in io.lines(f) do
    local rhs = line:match("^local [%w_, ]+ = (ns%.[%w_, .]+)$")
    if rhs then
      for name in rhs:gmatch("ns%.([%w_]+)") do
        if ns[name] == nil then failed = failed + 1; print("NIL IMPORT " .. name .. " in " .. f) end
      end
    end
  end
end
print(failed == 0 and ("load test OK (" .. #files .. " files)") or (failed .. " problem(s)"))
os.exit(failed == 0 and 0 or 1)
