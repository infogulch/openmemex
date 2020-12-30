install-tools:
	stack install ormolu ghcid

server-watcher:
	~/.local/bin/ghcid -c "stack ghci note2self:exe:server" -Tmain

prettier-watcher:
	rg *.vue *.js *.html --files | entr -s "npx prettier --write *.vue"

crawler-run:
	~/.local/bin/ghcid -c "stack ghci note2self:exe:crawler" -Tmain

crawler-build:
	~/.local/bin/ghcid -c "stack ghci note2self:exe:crawler"