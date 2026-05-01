DOTFILES_DIR := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
STOW_PKGS := nvim tmux zsh git claude duckdb

.PHONY: help stow restow unstow install env mcp
.DEFAULT_GOAL := help

help:
	@echo "Usage: dotfiles <command>"
	@echo ""
	@echo "Commands:"
	@echo "  stow      Symlink packages into ~"
	@echo "  restow    Re-symlink packages (use after adding skills, etc.)"
	@echo "  unstow    Remove all symlinks"
	@echo "  env       Scaffold missing env vars into ~/.zshrc.local"
	@echo "  mcp       Merge MCP servers into ~/.claude.json"
	@echo "  install   Full machine bootstrap"

stow:
	@mkdir -p $(HOME)/.claude
	@for pkg in $(STOW_PKGS); do \
		stow --target="$(HOME)" -d "$(DOTFILES_DIR)" $$pkg; \
		echo "  stowed $$pkg"; \
	done

restow:
	@mkdir -p $(HOME)/.claude
	@for pkg in $(STOW_PKGS); do \
		stow --restow --target="$(HOME)" -d "$(DOTFILES_DIR)" $$pkg; \
		echo "  restowed $$pkg"; \
	done

unstow:
	@for pkg in $(STOW_PKGS); do \
		stow --delete --target="$(HOME)" -d "$(DOTFILES_DIR)" $$pkg; \
		echo "  unstowed $$pkg"; \
	done

mcp:
	@if [ ! -f $(HOME)/.claude.json ]; then echo '{}' > $(HOME)/.claude.json; fi
	@jq -s '.[0].mcpServers = ((.[0].mcpServers // {}) * .[1]) | .[0]' \
		$(HOME)/.claude.json \
		$(DOTFILES_DIR)/claude/mcp-servers.json > $(HOME)/.claude.json.tmp \
		&& mv $(HOME)/.claude.json.tmp $(HOME)/.claude.json
	@echo "Merged MCP servers into ~/.claude.json"

env:
	@touch $(HOME)/.zshrc.local
	@added=0; \
	while IFS='=' read -r key value; do \
		case "$$key" in \
			\#*|"") continue ;; \
		esac; \
		if ! grep -q "^export $$key=" $(HOME)/.zshrc.local; then \
			echo "export $$key=" >> $(HOME)/.zshrc.local; \
			echo "  added $$key (needs value)"; \
			added=$$((added + 1)); \
		fi; \
	done < $(DOTFILES_DIR)/env.example; \
	if [ $$added -eq 0 ]; then \
		echo "All env vars already present in ~/.zshrc.local"; \
	else \
		echo "Edit ~/.zshrc.local to fill in values, then: source ~/.zshrc.local"; \
	fi

install:
	@bash "$(DOTFILES_DIR)/install.sh"
