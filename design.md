

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
        * zrange namespace 0 n-1 rev
* senario b:
    * saving:
        * const namespace = "$uid:nvim:olds" 
        * zadd namespace absolute-path access-time
    * reading:
        * key.startswith($project)
