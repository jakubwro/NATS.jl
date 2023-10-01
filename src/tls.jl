
# Returns read and write streams.
function upgrade_to_tls(socket::Sockets.TCPSocket)
    ssl = SSLStream(socket)
    # OpenSSL.hostname!(ssl, "localhost")
    OpenSSL.connect(ssl; require_ssl_verification = false) # TODO: fix. 
    get_tls_input_buffered(ssl), ssl
end

function get_tls_input_buffered(ssl::SSLStream)
    io = Base.BufferStream()
    t = Threads.@spawn :default begin # TODO: make it sticky.
        while !eof(ssl)
            av = readavailable(ssl)
            write(io, av)
        end
        @info "TLS connection EOF."
    end
    errormonitor(t)
    BufferedInputStream(io, 1)
end
