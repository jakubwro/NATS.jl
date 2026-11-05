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
# against `options.tls_ca_path`, or system roots if not provided, and must be issued for `options.tls_server_name`, or
# `host` if not provided, unless `tls_verify_peer` or `tls_verify_hostname` turns that off.
function upgrade_to_tls(sock::TCP.Conn, host::AbstractString, options::ConnectOptions)
    config = TLS.Config(;
        server_name = something(options.tls_server_name, host),
        verify_peer = options.tls_verify_peer,
        verify_hostname = something(options.tls_verify_hostname, options.tls_verify_peer),
        ca_file = options.tls_ca_path,
        cert_file = options.tls_cert_path,
        key_file = options.tls_key_path)
    conn = TLS.client(sock, config)
    try
        TLS.handshake!(conn)
    catch
        try
            close(conn)
        catch err
            @debug err
        end
        rethrow()
    end
    conn
end
