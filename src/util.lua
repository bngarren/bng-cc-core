local util = {}

function util.round(number, digit_position)
    local precision = math.pow(10, digit_position)
    number = number + (precision / 2);
    return math.floor(number / precision) * precision
end

function util.coloredWrite(text, color)
    if term and term.isColor() then
        local defaultColor = term.getTextColor()
        term.setTextColor(color)
        print(text)
        term.setTextColor(defaultColor)
    else
        print(text)
    end
end

return util