if Fakas == nil then
    Fakas = {}
end
if Fakas.Lib == nil then
    Fakas.Lib = {}
end

Fakas.Lib.Setup = {}

function Fakas.Lib.Setup.add_lib(name, func)
    if Fakas.Lib[name] == null then
        Fakas.Lib[name] = func()
    end
end

function Fakas.Lib.Setup.add_mod(name, func)
    if Fakas[name] == null then
        Fakas[name] = func()
    end
end
