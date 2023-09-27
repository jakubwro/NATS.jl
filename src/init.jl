function __init__()
    Base.Experimental.register_error_hint(MethodError) do io, exc, argtypes, kwargs
        if exc.f == convert && length(argtypes) > 1
             # TODO: check if 2nd arg is Msg of Hmsg
             print(io, """
                       
                       To use `$(argtypes[1])` as parameter of subscription handler apropriate conversion from `$(argtypes[2])` must be provided.
                       ```
                       import Base: convert

                       function convert(::Type{$(argtypes[1])}, msg::Union{NATS.Msg, NATS.HMsg})
                           # Implement conversion logic here.
                       end

                       ```
                       """)
        elseif exc.f == show
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
