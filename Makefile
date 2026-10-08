.PHONY: test check-stylua stylua luacheck helptags

test:
	XDG_STATE_HOME="$${TMPDIR:-/tmp}" nvim -u NONE -U NONE -N -i NONE -l scripts/test.lua

helptags:
	nvim -u NONE -U NONE -N -i NONE --headless -c "helptags doc" -c "quit"

check-stylua:
	stylua lua plugin scripts spec --color always --check

stylua:
	stylua lua plugin scripts spec

luacheck:
	luacheck lua plugin scripts spec
