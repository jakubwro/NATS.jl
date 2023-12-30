### hints.jl
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
# This file contains logic for registering hints for known exceptions.
#
### Code:

function register_hints()
    Base.Experimental.register_error_hint(MethodError) do io, exc, argtypes, kwargs
        if exc.f == convert && length(argtypes) > 1 && argtypes[2] == Type{Msg}
            print(io, """
                    
                    To use `$(argtypes[1])` as parameter of subscription handler apropriate conversion from `$(argtypes[2])` must be provided.
                    ```
                    import Base: convert

                    function convert(::$(argtypes[1]), msg::NATS.Msg)
                        # Implement conversion logic here.
                    end

                    ```
                    """)
        elseif exc.f == show && length(argtypes) > 1 && argtypes[2] == MIME_PAYLOAD
            print(io, """
                    
                    Object of type `$(argtypes[3])` cannot be serialized into payload.
                    ```
                    import Base: show

                    function Base.show(io::IO, NATS.MIME_PROTOCOL, x::$(argtypes[3]))
                            # Write content to `io` here.
                        end

                    ```
                    """)
        end
    end
end