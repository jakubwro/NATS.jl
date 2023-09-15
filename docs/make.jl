using Documenter
using NATS

makedocs(
    sitename = "NATS",
    format = Documenter.HTML(),
    modules = [NATS],
    pages = [
        "protocol.md",
    ]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
#=deploydocs(
    repo = "<repository url>"
)=#
