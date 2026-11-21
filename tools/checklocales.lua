-- Checks the translation files: every language has exactly the ids of the English base, plural tables keep their
-- shape, and each text keeps the same format specifiers (%s / %d) as the English one, so string.format never fails.
local ns = { locales = {} }
local function Load(path)
    assert(loadfile(path))("WhoWonThat", ns)
end

Load("src/Locale.lua")
Load("src/locales/enUS.lua")
local base = ns.locales.enUS

local function Specifiers(text)
    local list = {}
    for spec in text:gmatch("%%[%a%d%$]") do
        list[#list + 1] = spec
    end
    return table.concat(list, " ")
end

local problems = 0
local function Problem(locale, id, message)
    problems = problems + 1
    print(string.format("  %s.%s: %s", locale, id, message))
end

local toc = io.open("WhoWonThat.toc"):read("a")
local found = 0
for file in toc:gmatch("src/locales/(%a+)%.lua") do
    if file ~= "enUS" then
        found = found + 1
        Load("src/locales/" .. file .. ".lua")
        local texts = ns.locales[file]
        if not texts then
            Problem(file, "-", "the file does not define ns.locales." .. file)
        else
            for id, english in pairs(base) do
                local text = texts[id]
                if text == nil then
                    Problem(file, id, "missing")
                elseif type(english) ~= type(text) then
                    Problem(file, id, "type differs from English")
                elseif type(english) == "string" then
                    if Specifiers(english) ~= Specifiers(text) then
                        Problem(file, id, "format specifiers differ from English")
                    end
                else
                    for form, value in pairs(text) do
                        if type(value) ~= "string" or Specifiers(value) ~= "%d" then
                            Problem(file, id .. "." .. form, "a plural form must be a string with one %d")
                        end
                    end
                    if not text.other then
                        Problem(file, id, "plural table needs an 'other' form")
                    end
                end
            end
            for id in pairs(texts) do
                if base[id] == nil then
                    Problem(file, id, "unknown id (not in enUS)")
                end
            end
        end
    end
end

if found == 0 then
    print("  no translation files listed in the .toc")
    problems = problems + 1
end
print(string.format("locale check: %d languages, %d problem(s)", found, problems))
os.exit(problems == 0 and 0 or 1)
