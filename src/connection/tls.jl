### tls.jl
#
# Copyright (C) 2023 Jakub Wronowski.
#
# Maintainer: Jakub Wronowski <jakubwro@users.noreply.github.com>
# Keywords: nats, nats-client, julia
#
# This file is a part of NATS.jl.
#
# License is MIT.
#
### Commentary:
#
# This file contains utilities for handling the TLS handshake.
#
### Code:

# Wraps an established TCP connection in TLS and performs the handshake. The server certificate is verified
# against `ca_cert_path`, or system roots if not provided, and must be issued for `server_name`, or `host` if
# not provided, unless `verify_peer` or `verify_hostname` turns that off.
function upgrade_to_tls(sock::TCP.Conn, host::AbstractString, ca_cert_path::Union{String, Nothing}, client_cert_path::Union{String, Nothing}, client_key_path::Union{String, Nothing},
                        server_name::Union{AbstractString, Nothing} = nothing, verify_peer::Bool = true, verify_hostname::Union{Bool, Nothing} = nothing)
    config = TLS.Config(;
        server_name = something(server_name, host),
        verify_peer,
        verify_hostname = something(verify_hostname, verify_peer),
        ca_file = ca_cert_path,
        cert_file = client_cert_path,
        key_file = client_key_path)
    conn = TLS.client(sock, config)
    try
        TLS.handshake!(conn)
    catch
        close(conn)
        rethrow()
    end
    conn
end
