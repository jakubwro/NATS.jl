### utils.jl
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
# This file contains utilities for managing a NATS connection that do not fit anywhere else.
#
### Code:

function argtype(handler)
    handler_methods = methods(handler)
    if length(handler_methods) > 1
        error("Multimethod functions not supported as a subscription handler.")
    end
    signature = first(methods(handler)).sig
    if length(signature.parameters) == 1
        Nothing
    elseif length(signature.parameters) == 2
        signature.parameters[2]
    else
        Tuple{signature.parameters[2:end]...}
    end
end

function find_msg_conversion_or_throw(T::Type)
    if T != Any && !hasmethod(Base.convert, (Type{T}, Msg))
        error("""Conversion of a NATS message into type $T is not defined.
            
        An example how to define it:
        ```
        import Base: convert

        function convert(::Type{$T}, msg::NATS.Msg)
            # Implement conversion logic here.
            # For example:
            field1, field2 = split(payload(msg), ",")
            $T(field1, field2)
        end
        ```
        """)
    end
end

function find_data_conversion_or_throw(T::Type)
    if T != Any && !hasmethod(Base.show, (IO, NATS.MIME_PAYLOAD, T))
        error("""Conversion of type $T to NATS payload is not defined.
            
            An example how to define it:
            ```
            import Base: show

            function Base.show(io::IO, ::NATS.MIME_PAYLOAD, x::$T)
                # Write content to `io` here, it can be a UTF-8 string or a byte array.
            end

            ```

            Optionally you might want to attach headers to a message:
            ```
            function Base.show(io::IO, ::NATS.MIME_HEADERS, x::$T)
                # Create a vector of pairs of strings
                hdrs = ["header_key" => "header_value"]
                # Write them to the buffer
                show(io, ::NATS.MIME_HEADERS, hdrs)
            end
            ```
            """)
    end
end

# """
# Return a lambda that avoids type conversions for certain types.
# Also allows for use of parameterless handlers for subs that do not need to look into the msg payload.
# """
function wrap_handler(f::Function)
    arg_t = argtype(f)
    if arg_t === Any || arg_t == NATS.Msg
        f
    elseif arg_t == Nothing
        _ -> f()
    else
        find_msg_conversion_or_throw(arg_t)
        if arg_t <: Tuple
            msg -> f(invokelatest(convert, arg_t, msg)...)
        else
            msg -> f(invokelatest(convert, arg_t, msg))
        end
    end
end
