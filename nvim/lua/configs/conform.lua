local options = {
  formatters_by_ft = {
    lua = { "stylua" },
    bash = { "shfmt" },
    go = { "gofmt" },
    java = { "google_java_format" },
    json = { "prettier" },
    jsonc = { "prettier" },
    sh = { "shfmt" },
    terraform = { "terraform_fmt" },
    yaml = { "prettier" },
    -- css = { "prettier" },
    -- html = { "prettier" },
  },

  formatters = {
    google_java_format = {
      command = "google-java-format",
      args = { "-" },
      stdin = true,
    },
  },

  format_on_save = {
    -- These options will be passed to conform.format()
    timeout_ms = 500,
    lsp_fallback = true,
  },
}

return options
