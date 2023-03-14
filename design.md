
## features
* per-project-user MRU files
* long-lived redis connection based on luv tcp/socket
* RESP3 parser from okredis
* storing data in redis

## todo
* maybe async support
* maybe luv socket + okredis.RESP3.parser


## data manipulation

powered by redis
* senario a:
    * saving a:
        * const namespace = "$uid:nvim:olds:$project" 
        * zad namespace relative-path access-timestamp
    * saving b:
        * const namespace = "$uid:nvim:olds:global" 
        * zadd namespace absolute-path access-timestamp
    * reading:
        * zrevrange namespace 0 n-1 
* senario c:
    * saving:
        * const namespace = "$uid:nvim:olds" 
        * zadd namespace absolute-path access-time
    * reading:
        * key.startswith($project)

powered by sqlite
* senario a & b:
    * "stdpath('state')/olds/$project.db"
    * saving a
        * const table = "nvim_olds_$project"
        * upsert table relative-path access-timestamp
    * saving b
        * const table = "nvim_olds_global"
        * upsert table absolute-path access-timestamp
    * reading
        * select from table order by access_time
* senario c:
    * "stdpath('state')/olds.db"
    * saving
        * upsert table absolute-path access-timestamp
    * reading
        * select from table order by access_time
        * select from table where path like '$prefix/%' order by access_time


