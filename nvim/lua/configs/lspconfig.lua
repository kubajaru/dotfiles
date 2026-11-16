require("nvchad.configs.lspconfig").defaults()

local servers = {
	"bashls",
	"cssls",
	"dockerls",
	"gopls",
	"helm_ls",
	"html",
	"jdtls",
	"jsonls",
	"terraformls",
	"yamlls",
}
vim.lsp.enable(servers)

-- read :h vim.lsp.config for changing options of lsp servers 
