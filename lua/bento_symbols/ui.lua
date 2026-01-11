local symbols = require("bento_symbols")

local M = {}

local config = symbols.get_config()
local win_id = nil
local bufh = nil
local is_expanded = false
local minimal_menu_active = nil
local current_page = 1
local selection_mode_keymaps = {}
local saved_keymaps = {}

local state = {
    items = {},
    visible_items = {},
    path = {},
    last_bufnr = nil,
    pending = false,
    last_seen_id = nil,
    by_id = {},
}

local line_keys = {
    "a",
    "b",
    "c",
    "d",
    "e",
    "f",
    "g",
    "h",
    "i",
    "j",
    "k",
    "l",
    "m",
    "n",
    "o",
    "p",
    "q",
    "r",
    "s",
    "t",
    "u",
    "v",
    "w",
    "x",
    "y",
    "z",
    "A",
    "B",
    "C",
    "D",
    "E",
    "F",
    "G",
    "H",
    "I",
    "J",
    "K",
    "L",
    "M",
    "N",
    "O",
    "P",
    "Q",
    "R",
    "S",
    "T",
    "U",
    "V",
    "W",
    "X",
    "Y",
    "Z",
    "0",
    "1",
    "2",
    "3",
    "4",
    "5",
    "6",
    "7",
    "8",
    "9",
}

local symbol_kind_names = {
    [1] = "File",
    [2] = "Module",
    [3] = "Namespace",
    [4] = "Package",
    [5] = "Class",
    [6] = "Method",
    [7] = "Property",
    [8] = "Field",
    [9] = "Constructor",
    [10] = "Enum",
    [11] = "Interface",
    [12] = "Function",
    [13] = "Variable",
    [14] = "Constant",
    [15] = "String",
    [16] = "Number",
    [17] = "Boolean",
    [18] = "Array",
    [19] = "Object",
    [20] = "Key",
    [21] = "Null",
    [22] = "EnumMember",
    [23] = "Struct",
    [24] = "Event",
    [25] = "Operator",
    [26] = "TypeParameter",
}

local symbol_kind_highlights = {
    [5] = "@lsp.type.class",
    [6] = "@lsp.type.method",
    [7] = "@lsp.type.property",
    [8] = "@lsp.type.field",
    [9] = "@lsp.type.constructor",
    [10] = "@lsp.type.enum",
    [11] = "@lsp.type.interface",
    [12] = "@lsp.type.function",
    [13] = "@lsp.type.variable",
    [14] = "@lsp.type.constant",
    [15] = "@lsp.type.string",
    [16] = "@lsp.type.number",
    [17] = "@lsp.type.boolean",
    [18] = "@lsp.type.array",
    [19] = "@lsp.type.struct",
    [20] = "@lsp.type.key",
    [22] = "@lsp.type.enumMember",
    [23] = "@lsp.type.struct",
    [24] = "@lsp.type.event",
    [25] = "@lsp.type.operator",
    [26] = "@lsp.type.typeParameter",
}

local function get_item_match_range(item)
    return item.range or item.selection_range
end

local function range_contains(range, cursor)
    if not range or not range.start or not range["end"] then
        return false
    end
    local line = cursor[1]
    local col = cursor[2]
    local start_line = range.start.line or 0
    local start_col = range.start.character or 0
    local end_line = range["end"].line or 0
    local end_col = range["end"].character or 0

    if line < start_line or line > end_line then
        return false
    end
    if line == start_line and col < start_col then
        return false
    end
    if line == end_line and col > end_col then
        return false
    end
    return true
end

local function range_touches_line(range, line)
    if not range or not range.start or not range["end"] then
        return false
    end
    local start_line = range.start.line or 0
    local end_line = range["end"].line or 0
    return line >= start_line and line <= end_line
end

local function line_distance_to_range(range, cursor)
    if not range or not range.start or not range["end"] then
        return math.huge
    end
    local line = cursor[1]
    local col = cursor[2]
    local start_line = range.start.line or 0
    local start_col = range.start.character or 0
    local end_line = range["end"].line or 0
    local end_col = range["end"].character or 0

    if line < start_line or line > end_line then
        return math.huge
    end

    if start_line == end_line then
        if col < start_col then
            return start_col - col
        elseif col > end_col then
            return col - end_col
        end
        return 0
    end

    if line == start_line then
        if col < start_col then
            return start_col - col
        end
        return 0
    end

    if line == end_line then
        if col > end_col then
            return col - end_col
        end
        return 0
    end

    return 0
end

local function distance_for_item(item, cursor)
    local selection = item.selection_range
    if selection and selection.start and selection["end"] then
        return line_distance_to_range(selection, cursor)
    end
    local range = item.range
    if range then
        return line_distance_to_range(range, cursor)
    end
    return math.huge
end

local function range_size(range)
    if not range or not range.start or not range["end"] then
        return math.huge
    end
    local start_line = range.start.line or 0
    local start_col = range.start.character or 0
    local end_line = range["end"].line or 0
    local end_col = range["end"].character or 0
    return (end_line - start_line) * 100000 + (end_col - start_col)
end

local function find_best_visible_symbol_id(visible_items, cursor, fuzzy)
    local best_id = nil
    local best_size = math.huge
    local best_dist = math.huge
    local best_depth = -1
    for _, entry in ipairs(visible_items) do
        local item = entry.item
        local range = get_item_match_range(item)
        local matches = false
        if fuzzy then
            matches = range and range_touches_line(range, cursor[1]) or false
        else
            matches = range and range_contains(range, cursor) or false
        end
        if matches then
            local size = range_size(range)
            local dist = fuzzy and distance_for_item(item, cursor) or 0
            local depth = entry.depth or 0
            if dist < best_dist
                or (dist == best_dist and size < best_size)
                or (dist == best_dist and size == best_size and depth > best_depth)
            then
                best_dist = dist
                best_size = size
                best_depth = depth
                best_id = item.id
            end
        end
    end
    return best_id
end

local function get_current_symbol_id_for_visible(visible_items)
    local bufnr = vim.api.nvim_get_current_buf()
    if state.last_bufnr and state.last_bufnr ~= bufnr then
        return nil
    end
    local cursor = vim.api.nvim_win_get_cursor(0)
    local cursor_pos = { cursor[1] - 1, cursor[2] }
    if config.symbols.view == "drilldown" then
        if #state.path > 0 then
            local scope_range = get_item_match_range(state.path[#state.path])
            if not range_contains(scope_range, cursor_pos) then
                return nil
            end
        else
            local in_any_top = false
            for _, item in ipairs(state.items) do
                local range = get_item_match_range(item)
                if range_contains(range, cursor_pos) then
                    in_any_top = true
                    break
                end
            end
            if not in_any_top then
                return nil
            end
        end
    end
    local fuzzy = config.symbols.fuzzy_seen ~= false
    local current = find_best_visible_symbol_id(visible_items, {
        cursor[1] - 1,
        cursor[2],
    }, fuzzy)

    if current then
        if
            config.symbols.view == "flat"
            and state.last_seen_id
            and current ~= state.last_seen_id
        then
            local ancestor = state.by_id[state.last_seen_id]
            while ancestor and ancestor.parent_id do
                if ancestor.parent_id == current then
                    for _, entry in ipairs(visible_items) do
                        if entry.item.id == state.last_seen_id then
                            return state.last_seen_id
                        end
                    end
                    break
                end
                ancestor = state.by_id[ancestor.parent_id]
            end
        end
        state.last_seen_id = current
        return current
    end

    if config.symbols.sticky_highlight and state.last_seen_id then
        for _, entry in ipairs(visible_items) do
            if entry.item.id == state.last_seen_id then
                return state.last_seen_id
            end
        end
    end

    return nil
end

local function get_parent_ids(current_id)
    local parents = {}
    local item = current_id and state.by_id[current_id] or nil
    while item and item.parent_id do
        parents[item.parent_id] = true
        item = state.by_id[item.parent_id]
    end
    return parents
end


local function get_current_highlight()
    return config.highlights.current or "Visual"
end

local function get_kind_highlight(item)
    local custom = config.symbols.kind_highlights or {}
    return custom[item.kind] or symbol_kind_highlights[item.kind] or config.highlights.symbol
end

local function setup_state()
    config = symbols.get_config()
    if minimal_menu_active == nil then
        minimal_menu_active = config.ui.floating.minimal_menu
    end
end

vim.api.nvim_set_hl(0, "BentoSymbolsNormal", { bg = "NONE", fg = "NONE" })

local function get_symbol_id(name, range, kind)
    if not range or not range.start or not range["end"] then
        return name .. ":" .. tostring(kind or "")
    end
    return string.format(
        "%s:%d:%d:%d:%d:%s",
        name or "",
        range.start.line or 0,
        range.start.character or 0,
        range["end"].line or 0,
        range["end"].character or 0,
        tostring(kind or "")
    )
end

local function normalize_document_symbol(symbol, bufnr, parent_id)
    local selection = symbol.selectionRange or symbol.range
    local id = get_symbol_id(symbol.name, selection, symbol.kind)
    local item = {
        id = id,
        name = symbol.name or "",
        kind = symbol.kind,
        kind_name = symbol_kind_names[symbol.kind] or "Symbol",
        range = symbol.range,
        selection_range = selection,
        bufnr = bufnr,
        parent_id = parent_id,
        children = {},
    }
    if symbol.children and #symbol.children > 0 then
        for _, child in ipairs(symbol.children) do
            table.insert(item.children, normalize_document_symbol(child, bufnr, id))
        end
    end
    return item
end

local function normalize_symbol_information(symbol)
    local location = symbol.location or {}
    local range = location.range or {}
    local bufnr = location.uri and vim.uri_to_bufnr(location.uri) or nil
    local id = get_symbol_id(symbol.name, range, symbol.kind)
    return {
        id = id,
        name = symbol.name or "",
        kind = symbol.kind,
        kind_name = symbol_kind_names[symbol.kind] or "Symbol",
        range = range,
        selection_range = range,
        bufnr = bufnr,
        parent_id = nil,
        children = {},
    }
end

local function normalize_symbols(result, bufnr)
    if not result or vim.tbl_isempty(result) then
        return {}
    end
    if result[1] and result[1].range then
        local out = {}
        for _, symbol in ipairs(result) do
            table.insert(out, normalize_document_symbol(symbol, bufnr, nil))
        end
        return out
    end

    local out = {}
    for _, symbol in ipairs(result) do
        table.insert(out, normalize_symbol_information(symbol))
    end
    return out
end

local function get_current_items()
    if #state.path == 0 then
        return state.items
    end
    local node = state.path[#state.path]
    return node.children or {}
end

local function build_flat_items(items, depth, out)
    for _, item in ipairs(items) do
        table.insert(out, { item = item, depth = depth })
        if item.children and #item.children > 0 then
            build_flat_items(item.children, depth + 1, out)
        end
    end
end

local function refresh_visible_items()
    local visible = {}
    if config.symbols.view == "flat" then
        build_flat_items(state.items, 0, visible)
    else
        local items = get_current_items()
        local depth = #state.path
        for _, item in ipairs(items) do
            table.insert(visible, { item = item, depth = depth })
        end
    end
    state.visible_items = visible
end

local function index_items(items)
    for _, item in ipairs(items) do
        state.by_id[item.id] = item
        if item.children and #item.children > 0 then
            index_items(item.children)
        end
    end
end

local function get_pagination_info()
    local max_rendered = config.ui.floating.max_rendered_items

    local ui = vim.api.nvim_list_uis()[1]
    local screen_height = ui and ui.height or 24
    local available_height = screen_height - 3

    local effective_max
    if max_rendered and max_rendered > 0 then
        effective_max = math.min(max_rendered, available_height)
    else
        effective_max = available_height
    end

    if effective_max < 1 then
        effective_max = 1
    end

    if #state.visible_items <= effective_max then
        return #state.visible_items, 1, false
    end

    local total_pages = math.ceil(#state.visible_items / effective_max)
    return effective_max, total_pages, true
end

local function ensure_current_symbol_page_flat()
    if config.symbols.view ~= "flat" then
        return
    end
    if config.symbols.auto_page_flat == false then
        return
    end
    local max_per_page, _, needs_pagination = get_pagination_info()
    if not needs_pagination then
        return
    end
    local bufnr = vim.api.nvim_get_current_buf()
    if state.last_bufnr and state.last_bufnr ~= bufnr then
        return
    end
    local cursor = vim.api.nvim_win_get_cursor(0)
    local fuzzy = config.symbols.fuzzy_seen ~= false
    local current_id = find_best_visible_symbol_id(state.visible_items, {
        cursor[1] - 1,
        cursor[2],
    }, fuzzy)
    if not current_id then
        return
    end
    for idx, entry in ipairs(state.visible_items) do
        if entry.item.id == current_id then
            local target_page = math.ceil(idx / max_per_page)
            if current_page ~= target_page then
                current_page = target_page
            end
            return
        end
    end
end

local function get_page_items()
    local max_per_page, total_pages, needs_pagination = get_pagination_info()
    if not needs_pagination then
        return state.visible_items, 1
    end
    if current_page < 1 then
        current_page = 1
    elseif current_page > total_pages then
        current_page = total_pages
    end
    local start_idx = (current_page - 1) * max_per_page + 1
    local end_idx = math.min(start_idx + max_per_page - 1, #state.visible_items)
    local visible = {}
    for i = start_idx, end_idx do
        table.insert(visible, state.visible_items[i])
    end
    return visible, start_idx
end

local function generate_pagination_indicator(width)
    local _, total_pages, needs_pagination = get_pagination_info()
    local indicator_mode = config.ui.floating.page_indicator or "auto"
    local show =
        (indicator_mode == "always" and config.symbols.view == "flat")
        or (indicator_mode == "auto" and needs_pagination and config.symbols.view == "flat")
    if indicator_mode == "never" or not show then
        return nil
    end
    local indicator_style = config.ui.floating.page_indicator_style or "dots"
    local indicator
    if indicator_style == "counter" then
        indicator = string.format("%d/%d", current_page, total_pages)
    else
        local dots = {}
        for i = 1, total_pages do
            if i == current_page then
                table.insert(dots, "*")
            else
                table.insert(dots, ".")
            end
        end
        indicator = table.concat(dots, " ")
    end
    local indicator_width = vim.fn.strwidth(indicator)
    local padding = width - indicator_width
    if padding < 0 then
        padding = 0
    end
    return string.rep(" ", padding) .. indicator
end

local function assign_smart_labels(items, available_keys)
    local label_assignment = {}
    local used_labels = {}

    local char_to_items = {}
    for i, entry in ipairs(items) do
        local name = entry.item.name or ""
        local first_alnum = name:match("[%w]")
        if first_alnum then
            local char_lower = string.lower(first_alnum)
            if not char_to_items[char_lower] then
                char_to_items[char_lower] = {}
            end
            table.insert(char_to_items[char_lower], i)
        end
    end

    for char, indices in pairs(char_to_items) do
        if #indices == 1 then
            local idx = indices[1]
            local key_lower = string.lower(char)
            local key_upper = string.upper(char)
            if vim.tbl_contains(available_keys, key_lower) and not used_labels[key_lower] then
                label_assignment[idx] = key_lower
                used_labels[key_lower] = true
            elseif vim.tbl_contains(available_keys, key_upper) and not used_labels[key_upper] then
                label_assignment[idx] = key_upper
                used_labels[key_upper] = true
            end
        end
    end

    for _, indices in pairs(char_to_items) do
        if #indices > 1 then
            for _, idx in ipairs(indices) do
                local name = items[idx].item.name or ""
                local first = name:match("[%w]")
                if first then
                    local key_lower = string.lower(first)
                    local key_upper = string.upper(first)
                    if vim.tbl_contains(available_keys, key_lower) and not used_labels[key_lower] then
                        label_assignment[idx] = key_lower
                        used_labels[key_lower] = true
                    elseif vim.tbl_contains(available_keys, key_upper) and not used_labels[key_upper] then
                        label_assignment[idx] = key_upper
                        used_labels[key_upper] = true
                    end
                end
            end
        end
    end

    local key_idx = 1
    for i = 1, #items do
        if not label_assignment[i] then
            while key_idx <= #available_keys and used_labels[available_keys[key_idx]] do
                key_idx = key_idx + 1
            end
            if key_idx <= #available_keys then
                label_assignment[i] = available_keys[key_idx]
                used_labels[available_keys[key_idx]] = true
                key_idx = key_idx + 1
            else
                break
            end
        end
    end

    if #items > #available_keys then
        local multi_char_idx = 1
        for i = 1, #items do
            if not label_assignment[i] then
                local label
                repeat
                    local first_idx = math.floor((multi_char_idx - 1) / #available_keys) + 1
                    local second_idx = ((multi_char_idx - 1) % #available_keys) + 1
                    label = available_keys[first_idx] .. available_keys[second_idx]
                    multi_char_idx = multi_char_idx + 1
                until not used_labels[label]

                label_assignment[i] = label
                used_labels[label] = true
            end
        end
    end

    return label_assignment
end

local function calculate_position(height, width)
    local ui = vim.api.nvim_list_uis()[1]
    local floating = config.ui.floating
    local position = floating.position or "middle-right"
    local offset_x = floating.offset_x or 0
    local offset_y = floating.offset_y or 0

    local row, col

    if position:match("^top") then
        row = 0
    elseif position:match("^bottom") then
        row = ui.height - height
    else
        row = math.floor((ui.height - height) / 2)
    end

    if position:match("left$") then
        col = 0
    else
        col = ui.width - width + 1
    end

    return row + offset_y, col + offset_x
end

local function create_window(height, width)
    local row, col = calculate_position(height, width)

    local new_buf = vim.api.nvim_create_buf(false, true)
    local new_win = vim.api.nvim_open_win(new_buf, false, {
        relative = "editor",
        style = "minimal",
        width = width,
        height = height,
        row = row,
        col = col,
        border = "none",
        focusable = false,
    })

    vim.api.nvim_buf_set_option(new_buf, "modifiable", false)
    vim.api.nvim_buf_set_option(new_buf, "buftype", "nofile")
    vim.api.nvim_buf_set_option(new_buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(new_buf, "swapfile", false)
    vim.api.nvim_win_set_option(new_win, "wrap", false)
    vim.api.nvim_win_set_option(new_win, "winblend", 0)
    vim.api.nvim_win_set_option(
        new_win,
        "winhighlight",
        "Normal:" .. config.highlights.window_bg
    )

    return { bufnr = new_buf, win_id = new_win }
end

local function update_window_size(width, height)
    if not win_id or not vim.api.nvim_win_is_valid(win_id) then
        return
    end

    local row, col = calculate_position(height, width)

    pcall(vim.api.nvim_win_set_config, win_id, {
        relative = "editor",
        width = width,
        height = height,
        row = row,
        col = col,
    })
end

local function save_keymap(mode, key)
    local normalized_key = vim.api.nvim_replace_termcodes(key, true, true, true)

    local keymaps = vim.api.nvim_get_keymap(mode)
    for _, map in ipairs(keymaps) do
        local map_lhs = vim.api.nvim_replace_termcodes(map.lhs, true, true, true)
        if map_lhs == normalized_key then
            saved_keymaps[key] = {
                lhs = map.lhs,
                rhs = map.rhs,
                callback = map.callback,
                expr = map.expr == 1,
                noremap = map.noremap == 1,
                silent = map.silent == 1,
                nowait = map.nowait == 1,
                script = map.script == 1,
                buffer = map.buffer,
                desc = map.desc,
            }
            return
        end
    end
    saved_keymaps[key] = nil
end

local function restore_keymap(mode, key)
    local original = saved_keymaps[key]

    pcall(vim.keymap.del, mode, key)

    if original then
        local opts = {
            noremap = original.noremap,
            silent = original.silent,
            expr = original.expr,
            nowait = original.nowait,
            script = original.script,
            desc = original.desc,
        }

        if original.callback then
            vim.keymap.set(mode, key, original.callback, opts)
        elseif original.rhs then
            if original.noremap then
                vim.api.nvim_set_keymap(mode, original.lhs, original.rhs, opts)
            else
                opts.remap = true
                vim.keymap.set(mode, original.lhs, original.rhs, opts)
            end
        end
    end

    saved_keymaps[key] = nil
end

local function clear_selection_keymaps()
    for _, key in ipairs(selection_mode_keymaps) do
        restore_keymap("n", key)
    end
    selection_mode_keymaps = {}
end

local function set_navigation_keybindings(bind_paging)
    local keys = config.ui and config.ui.keys or {}
    local page_prev = keys.page_prev or "<C-h>"
    local page_next = keys.page_next or "<C-l>"
    local collapse = keys.collapse or "<ESC>"
    local go_back = keys.go_back or "\""

    if bind_paging then
        save_keymap("n", page_next)
        vim.keymap.set("n", page_next, function()
            require("bento_symbols.ui").next_page()
        end, { silent = true, desc = "Bento Symbols: Next page" })
        table.insert(selection_mode_keymaps, page_next)

        save_keymap("n", page_prev)
        vim.keymap.set("n", page_prev, function()
            require("bento_symbols.ui").prev_page()
        end, { silent = true, desc = "Bento Symbols: Previous page" })
        table.insert(selection_mode_keymaps, page_prev)
    end

    save_keymap("n", go_back)
    vim.keymap.set("n", go_back, function()
        require("bento_symbols.ui").go_back()
    end, { silent = true, desc = "Bento Symbols: Go back" })
    table.insert(selection_mode_keymaps, go_back)

    save_keymap("n", collapse)
    vim.keymap.set("n", collapse, function()
        require("bento_symbols.ui").collapse_menu()
    end, { silent = true, desc = "Bento Symbols: Collapse menu" })
    table.insert(selection_mode_keymaps, collapse)
end

local function set_selection_keybindings(smart_labels, base_index)
    clear_selection_keymaps()

    for i, label in pairs(smart_labels) do
        if label and label ~= " " then
            save_keymap("n", label)
            local absolute_index = (base_index or 1) + i - 1
            vim.keymap.set("n", label, function()
                require("bento_symbols.ui").select_item(absolute_index)
            end, {
                silent = true,
                desc = "Bento Symbols: Select item " .. absolute_index,
            })
            table.insert(selection_mode_keymaps, label)
        end
    end

    set_navigation_keybindings(true)
end

local function render_dashed()
    if not bufh or not vim.api.nvim_buf_is_valid(bufh) then
        return
    end

    setup_state()
    local visible_items = get_page_items()
    local contents = {}
    local padding = config.ui.floating.label_padding or 1
    local padding_str = string.rep(" ", padding)
    local dash = "──"
    local marker = "▸"
    local parent_marker = config.symbols.parent_marker or "·"
    local current_id = get_current_symbol_id_for_visible(visible_items)
    local parent_ids = current_id and get_parent_ids(current_id) or {}

    if #visible_items == 0 then
        contents[1] = padding_str .. dash .. padding_str
        local total_width = vim.fn.strwidth(dash) + 2 * padding
        vim.api.nvim_buf_set_option(bufh, "modifiable", true)
        vim.api.nvim_buf_set_lines(bufh, 0, -1, false, contents)
        vim.api.nvim_buf_set_option(bufh, "modifiable", false)
        update_window_size(total_width, 1)
        clear_selection_keymaps()
        set_navigation_keybindings(false)
        return
    end

    for i = 1, #visible_items do
        local entry = visible_items[i]
        local has_children = entry.item.children and #entry.item.children > 0
        local indicator = (entry.depth == 0 and has_children) and "──" or "─"
        local mark = " "
        if current_id and entry.item.id == current_id then
            mark = marker
        elseif parent_ids[entry.item.id] then
            mark = parent_marker
        end
        contents[i] = padding_str .. mark .. indicator .. padding_str
    end

    local dash_width = vim.fn.strwidth(dash)
    local total_width = dash_width + 1 + 2 * padding
    local total_height = #visible_items

    local indicator = generate_pagination_indicator(total_width)
    if indicator then
        local indicator_width = vim.fn.strwidth(indicator)
        if indicator_width > total_width then
            total_width = indicator_width
            indicator = generate_pagination_indicator(total_width)
        end
        table.insert(contents, indicator)
        total_height = total_height + 1
    end

    vim.api.nvim_buf_set_option(bufh, "modifiable", true)
    vim.api.nvim_buf_set_lines(bufh, 0, -1, false, contents)
    vim.api.nvim_buf_set_option(bufh, "modifiable", false)

    update_window_size(total_width, total_height)
    clear_selection_keymaps()
    set_navigation_keybindings(false)

    local ns_id = vim.api.nvim_create_namespace("BentoSymbolsDash")
    vim.api.nvim_buf_clear_namespace(bufh, ns_id, 0, -1)

    for i, entry in ipairs(visible_items) do
        vim.api.nvim_buf_add_highlight(
            bufh,
            ns_id,
            get_kind_highlight(entry.item),
            i - 1,
            0,
            -1
        )
    end
end

local function render_expanded(is_minimal_full)
    if not bufh or not vim.api.nvim_buf_is_valid(bufh) then
        return
    end

    setup_state()
    local visible_items, start_idx = get_page_items()
    local _, _, needs_pagination = get_pagination_info()
    local smart_labels = assign_smart_labels(visible_items, line_keys)
    local current_id = get_current_symbol_id_for_visible(visible_items)
    local current_hl = current_id and get_current_highlight() or nil
    local parent_ids = current_id and get_parent_ids(current_id) or {}
    local parent_marker = config.symbols.parent_marker or "·"
    local contents = {}
    local padding = config.ui.floating.label_padding or 1
    local padding_str = string.rep(" ", padding)
    local indent_unit = config.symbols.indent or "  "
    local title_line = nil
    local title_offset = 0

    if config.symbols.view == "drilldown" and #state.path > 0 then
        local title
        if #state.path >= 2 then
            title = state.path[#state.path - 1].name
                .. "."
                .. state.path[#state.path].name
        else
            title = state.path[#state.path].name
        end
        title_line = padding_str .. title .. padding_str
        title_offset = 1
    end

    local max_content_width = 0
    local all_line_data = {}
    if #visible_items == 0 then
        local message = state.pending and "Loading symbols..." or "No symbols"
        local line = padding_str .. message .. padding_str
        contents[1] = line
        local total_width = vim.fn.strwidth(line)
        vim.api.nvim_buf_set_option(bufh, "modifiable", true)
        vim.api.nvim_buf_set_lines(bufh, 0, -1, false, contents)
        vim.api.nvim_buf_set_option(bufh, "modifiable", false)
        update_window_size(total_width, 1)
        clear_selection_keymaps()
        set_navigation_keybindings(false)
        return
    end
    for i, entry in ipairs(visible_items) do
        local item = entry.item
        local label = smart_labels[i] or " "
        local indent = string.rep(indent_unit, entry.depth)
        local indicator = ""
        local parent_mark = parent_ids[item.id] and (parent_marker .. " ") or ""
        local kind_suffix = ""
        if config.symbols.show_kind and item.kind_name then
            kind_suffix = " [" .. item.kind_name .. "]"
        end
        local spacer = indicator ~= "" and (indicator .. " ") or ""
        local display_name = indent
            .. parent_mark
            .. spacer
            .. item.name
            .. kind_suffix
        local content_width = vim.fn.strwidth(display_name)
            + 1
            + padding
            + #label
            + padding
        max_content_width = math.max(max_content_width, content_width)
        table.insert(all_line_data, {
            label = label,
            display_name = display_name,
            content_width = content_width,
            name_prefix_len = #indent + #parent_mark + #spacer,
        })
    end

    local total_width = padding + max_content_width
    local total_height = #visible_items + title_offset

    for i, data in ipairs(all_line_data) do
        local left_space = max_content_width - data.content_width
        local line = padding_str
            .. string.rep(" ", left_space)
            .. data.display_name
            .. " "
            .. padding_str
            .. data.label
            .. padding_str
        contents[i] = line
    end

    if needs_pagination then
        local indicator = generate_pagination_indicator(total_width)
        if indicator then
            local indicator_width = vim.fn.strwidth(indicator)
            if indicator_width > total_width then
                total_width = indicator_width
                indicator = generate_pagination_indicator(total_width)
            end
            table.insert(contents, indicator)
            total_height = total_height + 1
        end
    end

    if title_line then
        local title_width = vim.fn.strwidth(title_line)
        if title_width > total_width then
            total_width = title_width
        end
        table.insert(contents, 1, title_line)
    end

    vim.api.nvim_buf_set_option(bufh, "modifiable", true)
    vim.api.nvim_buf_set_lines(bufh, 0, -1, false, contents)
    vim.api.nvim_buf_set_option(bufh, "modifiable", false)

    update_window_size(total_width, total_height)

    local ns_id = vim.api.nvim_create_namespace("BentoSymbols")
    vim.api.nvim_buf_clear_namespace(bufh, ns_id, 0, -1)

    for i, data in ipairs(all_line_data) do
        local label = data.label
        if label and label ~= " " then
            local left_space = max_content_width - data.content_width
            local display_name_bytes = #data.display_name
            local display_name_start = padding + left_space
            local display_name_end = display_name_start + display_name_bytes
            local label_start = display_name_end + 1 + padding
            local label_end = label_start + #label + padding

            local label_hl = config.highlights.label_jump
            if is_minimal_full then
                label_hl = config.highlights.label_minimal
            end

            local row = (i - 1) + title_offset
            vim.api.nvim_buf_add_highlight(
                bufh,
                ns_id,
                get_kind_highlight(visible_items[i].item),
                row,
                display_name_start,
                display_name_end
            )
            if current_id and visible_items[i].item.id == current_id then
                local item = visible_items[i].item
                local name_prefix_len = all_line_data[i].name_prefix_len
                local name_start = display_name_start + name_prefix_len
                local name_end = name_start + #item.name
                vim.api.nvim_buf_add_highlight(
                    bufh,
                    ns_id,
                    current_hl,
                    row,
                    name_start,
                    name_end
                )
            end
            vim.api.nvim_buf_add_highlight(
                bufh,
                ns_id,
                label_hl,
                row,
                label_start - padding,
                label_end
            )
        end
    end

    if needs_pagination then
        vim.api.nvim_buf_add_highlight(
            bufh,
            ns_id,
            config.highlights.page_indicator,
            #visible_items + title_offset,
            0,
            -1
        )
    end

    if title_line then
        vim.api.nvim_buf_add_highlight(
            bufh,
            ns_id,
            config.highlights.context,
            0,
            0,
            -1
        )
    end

    if is_minimal_full then
        clear_selection_keymaps()
    else
        set_selection_keybindings(smart_labels, start_idx)
    end
end

local function render_collapsed()
    if minimal_menu_active == "dashed" then
        render_dashed()
    elseif minimal_menu_active == "full" then
        render_expanded(true)
    end
end

local function close_menu()
    if win_id and vim.api.nvim_win_is_valid(win_id) then
        vim.api.nvim_win_close(win_id, true)
    end
    win_id = nil
    bufh = nil
    is_expanded = false
    current_page = 1
    state.path = {}
    clear_selection_keymaps()
end

local function open_menu(expand)
    local padding = config.ui.floating.label_padding or 1
    local initial_width = 2 + 2 * padding
    local initial_height = math.max(1, #state.visible_items)
    local win_info = create_window(initial_height, initial_width)
    win_id = win_info.win_id
    bufh = win_info.bufnr

    is_expanded = expand
    current_page = 1

    if is_expanded then
        render_expanded()
    else
        render_collapsed()
    end
end

local function apply_symbols(result, bufnr)
    local items = normalize_symbols(result, bufnr)
    state.items = items
    state.path = {}
    state.last_seen_id = nil
    state.by_id = {}
    index_items(items)
    refresh_visible_items()

    if #state.visible_items == 0 then
        vim.notify(
            "No symbols found",
            vim.log.levels.INFO,
            { title = "Bento Symbols" }
        )
        if win_id and vim.api.nvim_win_is_valid(win_id) then
            if is_expanded then
                render_expanded()
            else
                render_collapsed()
            end
        end
        return
    end

    if win_id and vim.api.nvim_win_is_valid(win_id) then
        if is_expanded then
            render_expanded()
        else
            render_dashed()
        end
    end
end

local function refresh_symbols()
    local bufnr = vim.api.nvim_get_current_buf()
    state.last_bufnr = bufnr
    state.pending = true
    local params = vim.lsp.util.make_text_document_params(bufnr)
    if not params or not params.textDocument then
        params = { textDocument = { uri = vim.uri_from_bufnr(bufnr) } }
    end

    vim.lsp.buf_request_all(
        bufnr,
        "textDocument/documentSymbol",
        params,
        function(results)
            state.pending = false
            local picked = nil
            local last_error = nil
            for _, res in pairs(results or {}) do
                if res.error then
                    last_error = res.error.message or res.error
                end
                if res.result and not vim.tbl_isempty(res.result) then
                    picked = res.result
                    break
                end
            end

            if not picked then
                if last_error then
                    vim.notify(
                        "LSP symbols error: " .. tostring(last_error),
                        vim.log.levels.WARN,
                        { title = "Bento Symbols" }
                    )
                end
                apply_symbols({}, bufnr)
                return
            end

            apply_symbols(picked, bufnr)
        end
    )
end

local function jump_to_item(item)
    if not item or not item.selection_range then
        return
    end
    local target_buf = item.bufnr or state.last_bufnr
    if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
        vim.api.nvim_set_current_buf(target_buf)
    end
    local range = item.selection_range
    if not range or not range.start then
        return
    end
    vim.api.nvim_win_set_cursor(0, {
        (range.start.line or 0) + 1,
        range.start.character or 0,
    })
end

local function enter_item(item)
    if not item or not item.children or #item.children == 0 then
        return false
    end
    if config.symbols.view == "flat" then
        return false
    end
    table.insert(state.path, item)
    refresh_visible_items()
    return true
end

local function go_back()
    if #state.path > 0 then
        table.remove(state.path)
        refresh_visible_items()
        if is_expanded then
            render_expanded()
        else
            render_collapsed()
        end
        return
    end
    M.collapse_menu()
end

function M.toggle_menu()
    setup_state()

    if win_id and vim.api.nvim_win_is_valid(win_id) then
        if not is_expanded then
            M.expand_menu()
        else
            refresh_symbols()
        end
        return
    end

    refresh_symbols()

    open_menu(true)
end

function M.refresh_menu()
    if not win_id or not vim.api.nvim_win_is_valid(win_id) then
        return
    end

    refresh_symbols()
end

function M.expand_menu()
    if not win_id or not vim.api.nvim_win_is_valid(win_id) then
        return
    end
    is_expanded = true
    render_expanded()
end

function M.collapse_menu()
    setup_state()

    if not win_id or not vim.api.nvim_win_is_valid(win_id) then
        return
    end

    is_expanded = false
    current_page = 1
    render_dashed()
end

function M.handle_main_keymap()
    setup_state()

    if win_id and vim.api.nvim_win_is_valid(win_id) then
        if is_expanded then
            M.collapse_menu()
        else
            M.expand_menu()
        end
        return
    end

    refresh_symbols()
    open_menu(true)
end

function M.select_item(idx)
    local entry = state.visible_items[idx]
    if not entry then
        return
    end

    local item = entry.item
    if config.symbols.view ~= "flat" and item.children and #item.children > 0 then
        jump_to_item(item)
        if enter_item(item) then
            current_page = 1
            if is_expanded then
                render_expanded()
            else
                render_collapsed()
            end
            return
        end
    end
    jump_to_item(item)
    if config.symbols.view == "flat" then
        M.collapse_menu()
        return
    end
    if not item.children or #item.children == 0 then
        M.collapse_menu()
    end
end

function M.set_action_mode(_)
    return
end

function M.next_page()
    local _, total_pages, needs_pagination = get_pagination_info()
    if not needs_pagination then
        return
    end
    if current_page < total_pages then
        current_page = current_page + 1
        if is_expanded then
            render_expanded()
        else
            render_collapsed()
        end
    end
end

function M.prev_page()
    local _, _, needs_pagination = get_pagination_info()
    if not needs_pagination then
        if #state.path == 0 then
            M.collapse_menu()
        end
        return
    end
    if current_page > 1 then
        current_page = current_page - 1
        if is_expanded then
            render_expanded()
        else
            render_collapsed()
        end
    elseif #state.path == 0 then
        M.collapse_menu()
    end
end

function M.toggle_view()
    config = symbols.get_config()
    if config.symbols.view == "flat" then
        config.symbols.view = "drilldown"
    else
        config.symbols.view = "flat"
    end
    state.path = {}
    state.last_seen_id = nil
    refresh_symbols()
    refresh_visible_items()
    if win_id and vim.api.nvim_win_is_valid(win_id) then
        if is_expanded then
            render_expanded()
        else
            render_dashed()
        end
    end
end

function M.update_cursor_highlight()
    if not win_id or not vim.api.nvim_win_is_valid(win_id) then
        return
    end
    ensure_current_symbol_page_flat()
    if is_expanded then
        render_expanded()
    else
        render_dashed()
    end
end

function M.go_back()
    go_back()
end

return M
