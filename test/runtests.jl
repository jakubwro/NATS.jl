using NATS
using Sockets
using Test
using TestItems
using TestItemRunner

@show Threads.nthreads()
@show Threads.nthreads(:interactive)
@show Threads.nthreads(:default)

function is_nats_available()
    try
        url = get(ENV, "NATS_CONNECT_URL", NATS.DEFAULT_CONNECT_URL)
        host, port = NATS.host_port(url)
        Sockets.getaddrinfo(host)
        nc = NATS.connect()
        sleep(5)
        @assert nc.status == NATS.CONNECTED
        @info "NATS avaliable, running connected tests."
        true
    catch err
        @info "NATS unavailable, skipping connected tests."  err
        false
    end
end

have_nats = is_nats_available()

if have_nats
    @run_package_tests verbose=true
    
    @testset "All subs should be closed" begin
        sleep(5)
        for nc in NATS.state.connections
            @test isempty(nc.sub_data)
            @test isempty(nc.unsubs)
            if nc.send_buffer.size > 0
                @info "Buffer content" String(nc.send_buffer.data[begin:nc.send_buffer.size])
            end
            @test nc.send_buffer.size == 0
        end
    end

    NATS.status()
else
    @run_package_tests verbose=true filter=ti->basename(ti.filename)=="protocol.jl"

    @test have_nats
end
