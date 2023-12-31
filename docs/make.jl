using Documenter
using NATS

makedocs(
    sitename = "NATS",
    format = Documenter.HTML(),
    modules = [NATS],
    pages = [
        "index.md",
        "examples.md",
        "connect.md",
        "pubsub.md",
        "reqreply.md",
        "custom-data.md",
        "scoped_connection.md",
        "benchmarks.md",
        "Internals" => [
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
