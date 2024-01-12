
Extract all ENV variables from sources
```
grep -rni 'get(ENV, "NATS_[^"]*' src/* | sed -E 's/.*(NATS_[^"]*).*/\1/'
```
