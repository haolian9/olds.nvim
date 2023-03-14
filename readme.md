## status
proved workable, v0 phase

## prerequisites
* redis >= 6.* (okredis)
* nvim 0.8.*
* zig 0.10.* (compile time)

## features
v0
* [x] global MRU files
* [x] long-lived redis connection
* [x] storing data in redis
* [x] batch insertion
* [ ] history size
* [x] programming apis: for fond.nvim
* [ ] filling from shada.oldfiles

v1
* per-project-user MRU files
* long-lived redis connection based on luv tcp/socket
* RESP3 parser from okredis

## installation
* `zig build -Drelease-safe`

## usage
* `require'olds'.setup('/run/user/1000/redis.sock')` # tcp address (ip:port) is not exposed yet.
