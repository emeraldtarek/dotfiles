return {
	"iamcco/markdown-preview.nvim",
	cmd = { "MarkdownPreviewToggle", "MarkdownPreview", "MarkdownPreviewStop" },
	ft = { "markdown" },
	-- Downloads the prebuilt preview server, so it doesn't depend on node/yarn being on PATH
	build = function()
		require("lazy").load({ plugins = { "markdown-preview.nvim" } })
		vim.fn["mkdp#util#install"]()
	end,
	init = function()
		vim.g.mkdp_filetypes = { "markdown" }
		-- Keep each preview tab open when switching buffers, so several docs can be previewed at once
		vim.g.mkdp_auto_close = 0
	end,
	keys = {
		{ "<leader>md", "<cmd>MarkdownPreviewToggle<cr>", ft = "markdown", desc = "Toggle markdown preview" },
	},
}
