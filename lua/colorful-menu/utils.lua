local Kind = require("colorful-menu").Kind
local config = require("colorful-menu").config

local M = {}

local query_cache = {}

---@param str string
---@param ls string
---@return CMHighlights
local function compute_highlights(str, ls)
    local highlights = {}

    local lang = vim.treesitter.language.get_lang(vim.bo.filetype)
    if not lang then
        return {}
    end

    local query, ok
    if query_cache[ls] == nil then
        ok, query = pcall(vim.treesitter.query.get, lang, "highlights")
        if not ok then
            return {}
        end
        query_cache[ls] = query
    else
        query = query_cache[ls]
    end

    ---@diagnostic disable-next-line: redefined-local
    local ok, parser = pcall(vim.treesitter.get_string_parser, str, lang)
    if not ok then
        return {}
    end

    if not parser then
        vim.notify(string.format("No Tree-sitter parser found for filetype: %s", lang), vim.log.levels.WARN)
        return highlights
    end

    -- Parse the string
    local tree = parser:parse(true)[1]
    if not tree then
        vim.notify("Failed to parse the string with Tree-sitter.", vim.log.levels.ERROR)
        return {}
    end

    local root = tree:root()

    if not query then
        return {}
    end

    -- Iterate over all captures in the query
    for id, node in query:iter_captures(root, str, 0, -1) do
        local name = "@" .. query.captures[id] .. "." .. lang
        local range = { node:range() }
        local _, nscol, _, necol = range[1], range[2], range[3], range[4]
        table.insert(highlights, {
            hl_group = name,
            range = { nscol, necol },
        })
    end

    return highlights
end

-- `left` is inclusive and `right` is exclusive (also zero indexed), to better fit
-- `nvim_buf_set_extmark` semantic, so `M.highlight_range(text, ft, 0, #text)` is the entire range.
--
---@param text string
---@param ls string
---@param left integer
---@param right integer
---@return CMHighlights
function M.highlight_range(text, ls, left, right)
    local highlights = {}
    local full_hl = compute_highlights(text, ls)

    for _, hl in ipairs(full_hl) do
        local s, e = hl.range[1], hl.range[2]
        if e < left then
            goto continue
        end
        if s > right or e > right + 1 then
            break
        end

        table.insert(highlights, {
            hl.hl_group,
            range = { hl.range[1] - left, hl.range[2] - left },
            text = text:sub(s + 1, e),
        })
        ::continue::
    end

    return {
        text = text:sub(left + 1, right),
        highlights = highlights,
    }
end

-- Shift a highlight range right by name_offset,
-- insert a color with fallback_hl for label with range (0, name_offset).
---@param item CMHighlights
---@param name_offset integer
---@param label string
---@param fallback_hl string?
---@return CMHighlights
function M.adjust_range(item, name_offset, label, fallback_hl)
    if name_offset == 0 then
        return item
    end
    name_offset = name_offset - 1
    for _, highlight in ipairs(item.highlights) do
        highlight.range[1] = highlight.range[1] + name_offset
        highlight.range[2] = highlight.range[2] + name_offset
    end
    item.text = label:sub(1, name_offset) .. item.text
    table.insert(item.highlights, {
        fallback_hl or "@variable",
        range = { 0, name_offset },
    })
    return item
end

---@param hl_group string
---@param fallback string
function M.hl_exist_or(hl_group, fallback)
    local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = hl_group })
    if ok and hl ~= nil and not vim.tbl_isempty(hl) then
        return hl_group
    else
        return fallback
    end
end

function M.hl_by_kind(kind)
    local highlight_name
    if kind == Kind.Method then
        highlight_name = M.hl_exist_or("@lsp.type.method", "@function")
    elseif kind == Kind.Function then
        highlight_name = M.hl_exist_or("@lsp.type.function", "@function")
    elseif kind == Kind.Constructor then
        highlight_name = "@constructor"
    elseif kind == Kind.Variable then
        highlight_name = M.hl_exist_or("@lsp.type.variable", "@variable")
    elseif kind == Kind.Field then
        highlight_name = M.hl_exist_or("@lsp.type.field", "@field")
    elseif kind == Kind.Keyword then
        highlight_name = "@keyword"
    elseif kind == Kind.Property then
        highlight_name = M.hl_exist_or("@lsp.type.property", "@property")
    elseif kind == Kind.Module then
        highlight_name = M.hl_exist_or("@lsp.type.namespace", "@namespace")
    elseif kind == Kind.Class then
        highlight_name = M.hl_exist_or("@lsp.type.class", "@type")
    elseif kind == Kind.Struct then
        highlight_name = M.hl_exist_or("@lsp.type.struct", "@type")
    elseif kind == Kind.Constant then
        highlight_name = "@constant"
    else
        highlight_name = config.fallback_highlight
    end

    return highlight_name
end

function M.align_spaces(abbr, detail)
    local blank = M.max_width() - vim.fn.strdisplaywidth(abbr) - vim.fn.strdisplaywidth(detail)
    if blank <= 1 then
        return "  "
    end
    return string.rep(" ", blank)
end

function M.max_width()
    local max_width = config.max_width
    if max_width < 1 and max_width > 0 then
        max_width = math.floor(max_width * vim.api.nvim_win_get_width(0))
    end
    return max_width
end

return M
