rockspec_format = "3.0"
package = "dagit.nvim"
version = "scm-1"

source = {
    url = "git://github.com/skarchr/dagit.nvim",
}

description = {
    homepage = "https://github.com/skarchr/dagit.nvim",
    license = "MIT",
    labels = { "neovim", "neovim-plugin" },
    summary = "Git history in a horizontal split",
}

dependencies = {
    "lua >= 5.1",
}

test_dependencies = {
    "busted >= 2.0, < 3.0",
}

test = { type = "busted" }

build = {
    type = "builtin",
    copy_directories = {
        "doc",
        "plugin",
    },
}
