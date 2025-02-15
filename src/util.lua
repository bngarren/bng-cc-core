---@class util
local M = {}

local function init(deps)
    function M.round(number, digit_position)
        local precision = math.pow(10, digit_position)
        number = number + (precision / 2);
        return math.floor(number / precision) * precision
    end

    ---Get a deep copy of the original. Handles recursive references to avoid a stack overflow.
    ---@generic T
    ---@param original T
    ---@param copy_metatables? boolean If true, will copy metatables of any tables in the original
    ---@return T
    function M.deep_copy(original, copy_metatables)
        if original == nil then return nil end
        if type(original) ~= 'table' then return original end

        -- Default copy_metatables to true if not specified
        if copy_metatables == nil then
            copy_metatables = true
        end

        -- Handle recursive references to avoid stack overflow
        local seen = {}

        local function copy_table(tbl)
            -- Check if we've seen this table before
            if seen[tbl] then return seen[tbl] end

            local tbl_copy = {}

            -- Copy metatable if it exists
            local mt = getmetatable(tbl)
            if copy_metatables and mt then
                setmetatable(tbl_copy, M.deep_copy(mt))
            end

            -- Copy all key/value pairs
            for k, v in pairs(tbl) do
                if type(k) == 'table' then
                    k = copy_table(k)
                end
                if type(v) == 'table' then
                    v = copy_table(v)
                end
                tbl_copy[k] = v
            end

            seen[tbl] = tbl_copy
            return tbl_copy
        end

        return copy_table(original)
    end

    --- Recursively merges two tables, handling both arrays and associative tables.
    --- Arrays are appended, while associative tables are merged by key.
    ---
    --- ### Example
    --- ```lua
    --- local target = {
    ---     arr = {1, 2},           -- Array
    ---     dict = {                -- Associative table
    ---         name = "test",
    ---         config = {
    ---             x = 1,
    ---             y = 2
    ---         }
    ---     }
    --- }
    ---
    --- local source = {
    ---     arr = {3, 4},           -- Array to append
    ---     dict = {                -- Associative table to merge
    ---         config = {
    ---             y = 3,          -- Overwrites y
    ---             z = 4           -- Adds new key
    ---         }
    ---     }
    --- }
    ---
    --- local result = deep_merge(target, source)
    --- -- Result will be:
    --- -- {
    --- --     arr = {1, 2, 3, 4},       -- Arrays are appended
    --- --     dict = {                   -- Tables are merged recursively
    --- --         name = "test",         -- Untouched
    --- --         config = {
    --- --             x = 1,             -- Untouched
    --- --             y = 3,             -- Updated
    --- --             z = 4              -- Added
    --- --         }
    --- --     }
    --- -- }
    --- ```
    --- @param target table: The target table to merge into
    --- @param source table: The source table to merge from. Keys in the source table will **overwrite** keys in the target table.
    --- @return table: The merged table (modified target)
    function M.deep_merge(target, source)
        -- Handle nil cases
        if source == nil then return target end
        if target == nil then return M.deep_copy(source) end

        -- Type check for tables
        if type(target) ~= "table" then error("Target must be a table") end
        if type(source) ~= "table" then error("Source must be a table") end

        -- Handle arrays/sequences differently from associative tables
        -- i.e. checks if there are any keys after the last numeric index
        local is_array = #source > 0 and next(source, #source) == nil

        for k, v in pairs(source) do
            if is_array then
                -- For arrays, append values
                table.insert(target, M.deep_copy(v))
            else
                -- For associative tables, merge recursively
                if type(v) == "table" and type(target[k]) == "table"
                    and not (getmetatable(v) or getmetatable(target[k])) then
                    target[k] = M.deep_merge(target[k], v)
                else
                    -- Handle non-table values and tables with metatables
                    target[k] = M.deep_copy(v)
                end
            end
        end

        return target
    end

    function M.stringify_table(o)
        if type(o) == 'table' then
            local s = '{ '
            for k, v in pairs(o) do
                if type(k) ~= 'number' then k = '"' .. k .. '"' end
                s = s .. '[' .. k .. '] = ' .. M.stringify_table(v) .. ','
            end
            return s .. '} '
        else
            return tostring(o)
        end
    end

    return M
end

return init
