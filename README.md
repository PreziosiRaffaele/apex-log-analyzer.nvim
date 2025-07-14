# Apex Log Analyzer for Neovim

This plugin was created to provide an Apex debug log analyzer in Neovim for Salesforce developers. It takes inspiration from a well-known extension that analyzes logs in VSCode: https://github.com/certinia/debug-log-analyzer

## Feature

-   Generate an execution tree from an Apex log file (`:ApexLogTree`).

<img width="1514" height="678" alt="image" src="https://github.com/user-attachments/assets/ce5d9507-3602-4c8a-82b3-a0a49334964b" />

## Prerequisites

-   [Neovim](https://neovim.io/) (v0.8+)
-   [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
-   `apex-log-parser` executable in your `PATH`. This is the engine of the plugin, it can be installed via npm:
    ```bash
    npm install -g apex-log-parser
    ```
-   `jq` executable in your `PATH`.

## Installation

### [lazy.nvim](https://github.com/folke/lazy.nvim)

Add the following to your `lazy.nvim` configuration:

```lua
{
    'PreziosiRaffaele/apex-log-analyzer.nvim',
    -- Dependencies required by the plugin
    dependencies = { 'nvim-lua/plenary.nvim' },

    -- Lazy-load the plugin when the ApexLogTree command is executed
    cmd = 'ApexLogTree',
    keys = {
        { '<leader>lt', '<cmd>ApexLogTree<cr>', desc = 'Apex Log Tree' },
    },

    -- This function runs after the plugin is loaded
    config = function()
        -- This calls the setup function in your plugin, which creates the command
        require('apex-log-analyzer').setup()
    end,
}
```

## Usage

1.  Open an Apex log file in Neovim.
2.  Run the command `:ApexLogTree`.
3.  A new split will open with the execution tree.
