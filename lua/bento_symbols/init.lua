local M = {}

BentoSymbolsConfig = BentoSymbolsConfig or {}

local function setup_command_and_keymap()
    local config = M.get_config()

    vim.api.nvim_create_user_command("BentoSymbols", function()
        require("bento_symbols.ui").handle_main_keymap()
    end, { desc = "Open bento symbols menu" })

    vim.api.nvim_create_user_command("BentoSymbolsToggleView", function()
        require("bento_symbols.ui").toggle_view()
    end, { desc = "Toggle bento symbols view (drilldown/flat)" })

    if config.main_keymap and config.main_keymap ~= "" then
        vim.keymap.set(
            "n",
            config.main_keymap,
            "<Cmd>lua require('bento_symbols.ui').handle_main_keymap()<CR>",
            { silent = true, desc = "Bento Symbols" }
        )
    end

    if config.ui and config.ui.keys and config.ui.keys.toggle_view then
        vim.keymap.set(
            "n",
            config.ui.keys.toggle_view,
            "<Cmd>BentoSymbolsToggleView<CR>",
            { silent = true, desc = "Toggle Bento Symbols view" }
        )
    end
end

local function setup_autocmds()
    local augroup =
        vim.api.nvim_create_augroup("BentoSymbolsRefresh", { clear = true })

    vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter" }, {
        group = augroup,
        callback = function()
            require("bento_symbols.ui").refresh_menu()
        end,
        desc = "Refresh bento symbols on buffer change",
    })

    vim.api.nvim_create_autocmd("CursorMoved", {
        group = augroup,
        callback = function()
            require("bento_symbols.ui").update_cursor_highlight()
        end,
        desc = "Update current symbol highlight",
    })
end

function M.get_config()
    return BentoSymbolsConfig or {}
end

function M.setup(config)
    config = config or {}

    local default_config = {
        main_keymap = nil,
        default_action = "enter",
        ui = {
            mode = "floating",
            floating = {
                position = "middle-right",
                offset_x = 0,
                offset_y = 0,
                dash_char = "-",
                label_padding = 1,
                minimal_menu = "dashed",
                max_rendered_items = nil,
                page_indicator = "auto", -- "auto" | "always" | "never"
                page_indicator_style = "counter", -- "dots" | "counter"
                border = "none",
                top_margin = 0,
                bottom_margin = 0,
            },
            keys = {
                page_prev = "<C-h>",
                page_next = "<C-l>",
                collapse = "<ESC>",
                toggle_view = nil,
                go_back = "<C-j>",
                go_forward = "<C-k>",
                lock_toggle = "*",
            },
        },
        symbols = {
            show_kind = true,
            indent = "  ",
            view = "drilldown", -- "drilldown" | "flat"
            kind_highlights = {},
            fuzzy_seen = true,
            auto_page_flat = true,
            auto_page_drilldown = true,
            auto_page_drilldown_on_refresh = true,
            auto_context_drilldown_on_refresh = true,
            parent_marker = "·",
            flat_keep_expanded_on_select = false,
            flat_auto_lock_on_select = false,
            drilldown_keep_expanded_on_leaf_select = false,
            drilldown_auto_lock_on_leaf_select = false,
            name_truncate_ratio = 0.25,
        },
        highlights = {
            symbol = "Normal",
            label_jump = "@variable",
            label_minimal = "Visual",
            window_bg = "BentoSymbolsNormal",
            page_indicator = "Comment",
            current = "Visual",
            context = "Comment",
        },
        actions = {
            jump = {
                key = "<CR>",
            },
            enter = {
                key = "<Tab>",
            },
        },
    }

    BentoSymbolsConfig = vim.tbl_deep_extend("force", default_config, config)

    setup_command_and_keymap()
    setup_autocmds()
end

return M
