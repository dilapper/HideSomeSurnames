-- Run from the repo root:  lua tests/strip_spec.lua
local HSS = {}
assert(loadfile("HideSomeSurnames/Core.lua"))("HideSomeSurnames", HSS)

local set = HSS.BuildSurnameSet({ "Mhmm", "Other" })
local failures = 0

local function check(name, input, expected)
    local got = HSS.StripSurname(input, set)
    if got ~= expected then
        failures = failures + 1
        print(("FAIL %s: %s -> %s (expected %s)"):format(name, tostring(input), tostring(got), tostring(expected)))
    else
        print("ok   " .. name)
    end
end

check("matching surname",        "Dave Mhmm",        "Dave")
check("case-insensitive",        "Dave mHMM",        "Dave")
check("second listed surname",   "Matt Other",       "Matt")
check("non-matching kept",       "Dave Smith",       "Dave Smith")
check("no surname",              "Dave",             "Dave")
check("extra spaces",            "Dave   Mhmm  ",    "Dave")
check("realm suffix kept",       "Dave Mhmm-Realm",  "Dave-Realm")
check("realm, other surname",    "Dave Smith-Realm", "Dave Smith-Realm")
check("no surname, realm only",  "Dave-Realm",       "Dave-Realm")
check("partial surname no match","Dave Mhmmm",       "Dave Mhmmm")
check("empty string",            "",                 "")
check("nil",                     nil,                nil)
check("non-string",              42,                 42)

local empty = HSS.StripSurname("Dave Mhmm", HSS.BuildSurnameSet({}))
if empty ~= "Dave Mhmm" then failures = failures + 1; print("FAIL empty set") else print("ok   empty set") end

if failures > 0 then os.exit(1) end
print("all passed")
