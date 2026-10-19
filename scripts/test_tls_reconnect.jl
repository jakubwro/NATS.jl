# Run from the project root:
#   julia +1.10 --project=. -t 2,1 scripts/test_tls_reconnect.jl
# Requires nats-server on PATH and free client ports 44223/44226 and route ports 44233/44236.
# The certificate covers localhost; the cluster advertises IP addresses.
# Reconnect should preserve the TLS hostname. This test fails until that is fixed.

using NATS
using Test

function main()
    server = Sys.which("nats-server")
    isnothing(server) && error("nats-server must be on PATH")
    certs = normpath(joinpath(@__DIR__, "..", "test", "certs"))
    logs = mktempdir(; prefix = "nats_tls_reconnect_", cleanup = false)
    println("Server configs and logs: $logs")
    servers = Base.Process[]
    nc = nothing
    try
        for (port, route_port) in ((44223, 44233), (44226, 44236))
            config = joinpath(logs, "$port.conf")
            routes = port == 44223 ? "" : "routes: [\"nats://127.0.0.1:44233\"]"
            write(config, """
                host: "127.0.0.1"
                port: $port
                tls {
                    cert_file: $(repr(joinpath(certs, "nats.crt")))
                    key_file: $(repr(joinpath(certs, "nats.key")))
                }
                cluster { name: tls_reconnect_test, port: $route_port, $routes }
                """)
            log_path = joinpath(logs, "$port.log")
            open(log_path, "w") do log
                push!(servers, run(pipeline(`$server -c $config`; stdout = log, stderr = log); wait = false))
            end
            timedwait(() -> occursin("Server is ready", read(log_path, String)), 10.0) == :ok ||
                error("Server did not start; see $log_path")
        end

        nc = NATS.connect("nats://localhost:44223";
            tls_ca_path = joinpath(certs, "nats.crt"),
            reconnect_delays = (0.05, 0.1), drain_timeout = 2.0)
        # Wait for discovery, otherwise reconnect might reuse the original localhost URL.
        discovered = timedwait(10.0) do
            urls = NATS.info(nc).connect_urls
            !isnothing(urls) && all(url -> url in urls, ("127.0.0.1:44223", "127.0.0.1:44226"))
        end
        discovered == :ok || error("Cluster discovery timed out; see $logs")
        println("Advertised servers: ", NATS.info(nc).connect_urls)

        @testset "TLS reconnect through advertised IPs" begin
            NATS.ping(nc; timeout = 5.0, measure = false)
            @test NATS.status(nc) == NATS.CONNECTED
            previous = @atomic nc.reconnect_count
            NATS.reconnect(nc; should_wait = false)
            @test timedwait(10.0) do
                (@atomic nc.reconnect_count) > previous || NATS.status(nc) == NATS.DISCONNECTED
            end == :ok
            @test NATS.status(nc) == NATS.CONNECTED
            if NATS.status(nc) == NATS.CONNECTED
                NATS.ping(nc; timeout = 5.0, measure = false)
                @test (@atomic nc.reconnect_count) > previous
            end
        end
    finally
        try
            isnothing(nc) || NATS.drain(nc)
        finally
            for server in servers
                process_running(server) && kill(server)
                wait(server)
            end
        end
    end
end

main()
