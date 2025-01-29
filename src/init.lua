local lib = {}

-- Function to dynamically load a module
function lib.require(moduleName)
  if not lib[moduleName] then
    local moduleFile = "/lib/mylib/" .. moduleName .. ".lua"
    if fs.exists(moduleFile) then
      lib[moduleName] = dofile(moduleFile)
    else
      error("Module not found: " .. moduleName)
    end
  end
  return lib[moduleName]
end

-- Metatable to enable lazy loading
setmetatable(lib, {
  __index = function(self, key)
    return lib.require(key)
  end
})

return lib