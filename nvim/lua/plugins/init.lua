return {
  {
    "stevearc/conform.nvim",
    -- event = 'BufWritePre', -- uncomment for format on save
    opts = require "configs.conform",
  },

  -- These are some examples, uncomment them if you want to see them work!
  {
    "neovim/nvim-lspconfig",
    config = function()
      require "configs.lspconfig"
    end,
  },

  {
    "mason-org/mason-lspconfig.nvim",
    lazy = false,
    opts = {
      ensure_installed = {
        "bashls",
        "dockerls",
        "gopls",
        "helm_ls",
        "jdtls",
        "jsonls",
        "terraformls",
        "yamlls",
      },
    },
    dependencies = {
      { "mason-org/mason.nvim", opts = {} },
      "neovim/nvim-lspconfig",
    },
  },

  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    lazy = false,
    opts = {
      ensure_installed = { "google-java-format", "prettier", "shfmt", "stylua" },
    },
    dependencies = { "mason-org/mason.nvim" },
  },

  {
    "nvim-treesitter/nvim-treesitter",
    lazy = false,
    build = ":TSUpdate",
    config = function()
      local parsers = {
        "bash",
        "dockerfile",
        "go",
        "hcl",
        "java",
        "json",
        "lua",
        "make",
        "terraform",
        "yaml",
      }

      require("nvim-treesitter").install(parsers)
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "sh", "dockerfile", "go", "hcl", "java", "json", "lua", "make", "terraform", "yaml" },
        callback = function(args)
          pcall(vim.treesitter.start, args.buf)
        end,
      })
    end,
  },

  -- test new blink
  -- { import = "nvchad.blink.lazyspec" },

  -- {
  -- 	"nvim-treesitter/nvim-treesitter",
  -- 	opts = {
  -- 		ensure_installed = {
  -- 			"vim", "lua", "vimdoc",
  --      "html", "css"
  -- 		},
  -- 	},
  -- },
}
