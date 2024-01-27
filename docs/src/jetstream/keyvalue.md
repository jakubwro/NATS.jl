# Key Value streams

Low level APIs for manipulating KV buckets. See `JetDict` for interface conforming to `Base.AbstractDict`.

## Management

```@docs
keyvalue_stream_create
keyvalue_stream_purge
keyvalue_stream_delete
```

## Manipulating items
```@docs
keyvalue_get
keyvalue_put
keyvalue_delete
```

## Watching changes

```@docs
keyvalue_watch
```