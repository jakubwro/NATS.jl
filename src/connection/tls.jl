# Returns read and write streams.

function upgrade_to_tls(sock::Sockets.TCPSocket, ca_cert_path::Union{String, Nothing}, client_cert_path::Union{String, Nothing}, client_key_path::Union{String, Nothing})
    entropy = MbedTLS.Entropy()
    rng = MbedTLS.CtrDrbg()
    MbedTLS.seed!(rng, entropy)
    ctx = MbedTLS.SSLContext()
    conf = MbedTLS.SSLConfig()
    MbedTLS.config_defaults!(conf)
    # MbedTLS.authmode!(conf, MbedTLS.MBEDTLS_SSL_VERIFY_REQUIRED)
    MbedTLS.rng!(conf, rng)

    # function show_debug(level, filename, number, msg)
    #     @show level, filename, number, msg
    # end
    
    # MbedTLS.dbg!(conf, show_debug)
    
    if !isnothing(ca_cert_path)
        MbedTLS.ca_chain!(conf, MbedTLS.crt_parse_file(ca_cert_path))
    end

    MbedTLS.setup!(ctx, conf)
    MbedTLS.set_bio!(ctx, sock)
    if !isnothing(client_key_path) && !isnothing(client_key_path)
        cert = MbedTLS.crt_parse_file(client_cert_path)
        key = MbedTLS.parse_keyfile(client_key_path)
        MbedTLS.own_cert!(conf, cert, key)
    end
    
    MbedTLS.handshake(ctx)

    get_tls_input_buffered(ctx), ctx
end

function get_tls_input_buffered(ssl)
    io = Base.BufferStream()
    t = Threads.@spawn :interactive begin # TODO: make it sticky.
        try
            while !eof(ssl)
                av = readavailable(ssl)
                write(io, av)
            end
        finally
            close(io)
        end
    end
    errormonitor(t)
    BufferedInputStream(io, 1)
end
