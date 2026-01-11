<div align="center">

# 🧭 bento-symbols.nvim

Floating LSP document symbols menu for Neovim, inspired by bento.nvim.

</div>

## Status

Ready for use. Floating symbols list with drilldown/flat views and kind-based
highlighting.

## Installation

Neovim 0.9.0+ required. Works with any plugin manager:

```lua
-- lazy.nvim
{ "AbinZorto/bento-symbols.nvim", opts = {} }

-- packer.nvim
use({ "AbinZorto/bento-symbols.nvim", config = function()
    require("bento_symbols").setup()
end })
```

## Installation (local dev)

```lua
-- lazy.nvim
{ dir = "/Users/abin/bento-symbols.nvim", opts = {} }

-- packer.nvim
use({ "/Users/abin/bento-symbols.nvim", config = function()
    require("bento_symbols").setup()
end })
```

## Usage

```vim
:BentoSymbols
:BentoSymbolsToggleView
```

Example mapping:

```lua
vim.keymap.set("n", "<leader>cs", ":BentoSymbols<CR>", { desc = "Bento Symbols" })
```

## Behavior

- Uses LSP `textDocument/documentSymbol` results when available.
- Drilldown view shows one level at a time; flat view shows the full tree with
  indentation.
- Indicator: top-level parents use a double dash, everything else uses a
  single dash.
- In drilldown mode, selecting a parent jumps to it and enters its children.
  Selecting a leaf jumps and collapses to dashed lines.
- In flat mode, selecting a symbol jumps and collapses to dashed lines.

If your server returns `SymbolInformation` instead of hierarchical
`DocumentSymbol`, the list is flat (no tree).

## Keybindings (default)

- `:BentoSymbols` opens or refreshes the menu (expanded)
- `ESC` collapses to dashed lines
- `<C-h>` / `<C-l>` moves between pages when pagination is active
- Label keys jump or drill down depending on view and symbol type

## Configuration

```lua
require("bento_symbols").setup({
    main_keymap = nil, -- Optional global keymap
    symbols = {
        show_kind = true, -- Append kind name (e.g. [Function])
        indent = "  ", -- Indentation per tree depth
        view = "drilldown", -- "drilldown" | "flat"
        kind_highlights = {}, -- Override kind highlight groups by symbol kind id
        sticky_highlight = false, -- Keep last seen symbol highlighted
        fuzzy_seen = true, -- Use cursor line proximity to pick current symbol
        auto_page_flat = true, -- Auto-switch page to show current symbol in flat view
        auto_page_drilldown = true, -- Auto-switch context/page in drilldown on cursor move
        auto_page_drilldown_on_refresh = true, -- Auto-switch page on refresh in drilldown
        auto_context_drilldown_on_refresh = true, -- Auto-switch context on refresh in drilldown
        parent_marker = "·", -- Marker shown for parent symbols
        flat_keep_expanded_on_select = false, -- Keep expanded after select in flat view
        flat_auto_lock_on_select = false, -- Auto-lock after select in flat view
        drilldown_keep_expanded_on_leaf_select = false, -- Keep expanded after leaf select
        drilldown_auto_lock_on_leaf_select = false, -- Auto-lock after leaf select
        name_truncate_ratio = 0.25, -- Max name width as ratio of window width
    },
    ui = {
        mode = "floating",
        floating = {
            position = "middle-right",
            offset_x = 0,
            offset_y = 0,
            dash_char = "-",
            label_padding = 1,
            minimal_menu = "dashed", -- nil | "dashed" | "full"
            max_rendered_items = nil, -- nil (no limit) or number for pagination
            page_indicator = "auto", -- "auto" | "always" | "never"
            page_indicator_style = "counter", -- "dots" | "counter"
            border = "none", -- "none" | "single" | "double" | "rounded" | "solid" | "shadow"
            top_margin = 0,
            bottom_margin = 0,
        },
        keys = {
            page_prev = "<C-h>",
            page_next = "<C-l>",
            collapse = "<ESC>",
            toggle_view = nil, -- map to :BentoSymbolsToggleView
            go_back = "<C-j>", -- drilldown back
            go_forward = "<C-k>", -- drilldown forward
            lock_toggle = "*", -- toggle read-only mode
        },
    },
})
```

## Highlights

```lua
require("bento_symbols").setup({
    highlights = {
        symbol = "Normal",
        current = "Visual",
        context = "Comment",
    },
})
```
