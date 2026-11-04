function interactive_status(cond = nothing)
    try
        while true
            NATS.status()
            sleep(0.05)
            if !isnothing(cond) && !isopen(cond)
                return
            end
            write(stdout, "\u1b[A\u1b[A\u1b[A\u1b[A\u1b[A\u1b[A\u1b[A\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K\u1b[K")
        end
    catch e
        if !(e isa InterruptException)
            throw(e)
        end
    end
end

uint8_vec(s::String) = convert.(UInt8, collect(s))

# Number of active libuv handles, every started `Timer` that did not fire and was not closed yet is one of them.
active_handles() = Int(unsafe_load(Ptr{Cuint}(Base.eventloop() + sizeof(Ptr{Cvoid}))))

# Tells by how much the number of active libuv handles grew when `f` was called. The GC is disabled meanwhile,
# otherwise the finalizer would close a `Timer` that is not referenced anymore, what hides that it was left behind.
function active_handles_growth(f)
    GC.gc()
    GC.enable(false)
    try
        before = active_handles()
        f()
        active_handles() - before
    finally
        GC.enable(true)
    end
end

# Replies to `msg` with a message that has only a status, like the server does with 503 when there are no responders.
function reply_with_status(connection, msg, code)
    status = Vector{UInt8}("NATS/1.0 $code\r\n\r\n")
    NATS.send(connection, NATS.Pub(msg.reply_to, nothing, length(status), status))
end
