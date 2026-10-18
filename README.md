# fram.nvim

Basic fram language support for Neovim. Includes a `filetype`, LSP config, and a tree-sitter grammar.

## Requirements

- Neovim 0.11 or newer
- `lazy.nvim` or another plugin manager
- `nvim-treesitter` on its `master` branch, with the `highlight` module enabled for syntax highlighting


## Installation

Add the following to your plugin spec:

```lua
{
  'Brychlikov/fram.nvim',
  name = 'vimplugin-fram.nvim',
  dependencies = { { 'nvim-treesitter/nvim-treesitter', branch = 'master' } },
  config = function()
    require('fram').setup()
    vim.lsp.enable('framls')
  end,
},
```

The parser is installed from `fram-lang/tree-sitter-fram`'s `main` branch.
After publishing or updating the grammar and this plugin, run `:TSUpdate fram`
and reopen your Fram buffers to use the repaired parser and matching highlights.
Publish the grammar first: the queries require its current node types.
