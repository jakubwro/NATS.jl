
const Message = Union{Msg, HMsg}

payload(msg::Msg) = msg.payload
payload(hmsg::HMsg) = hmsg.payload

function argtype(handler)
    signature = first(methods(handler)).sig # TODO: handle multi methods.
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
        throw(MethodError(Base.convert, (T, Msg)))
    end
end

function from_kwargs(T::Type, defaults, kwargs)
    args = merge(defaults, kwargs)
    fields = fieldnames(T)
    missing_args = setdiff(fields, keys(args))
    if !isempty(missing_args)
        error("Missing keyword arguments: $missing_args.")
    end
    unknown_args = setdiff(keys(args), fields)
    if !isempty(unknown_args)
        error("Unknown keyword arguments: $unknown_args.")
    end
    args = args[fields]
    field_types = fieldtypes(T)
    for ((key, val), t) in zip(pairs(args), field_types)
        if !(val isa t)
            error("Keyword argument `$key` expected to be `$t` but `$val` of type `$(typeof(val))` encountered.")
        end
    end
    T(args...)
end
