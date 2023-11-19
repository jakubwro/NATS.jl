using Documenter
using NATS

makedocs(
    sitename = "NATS",
    format = Documenter.HTML(),
    modules = [NATS],
    pages = [
        "index.md",
        "examples.md",
        "benchmarks.md",
        "Functions" => [
            "connect.md",
            "pubsub.md",
            "reqreply.md",
        ],
        "Internals" => [
            "design.md",
            "protocol.md",
            "interrupt_handling.md"
        ]
    ]
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
deploydocs(
    repo = "github.com/jakubwro/NATS.jl"
)
