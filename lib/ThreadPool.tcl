proc ThreadPool_init { nof_thread } {
   global PoolId count
   set done false
   set count 0
   while { ${done} == false } {
      puts "ThreadPool_init creating thread no: ${count}"
      set threadId [MyThreadPool_createThread]
      # puts "ThreadPool_init thread no: ${count} creation done..."
      set PoolId(${threadId}) false
      incr count
      if { ${count} == ${nof_thread} } {
         set done true
      }
   }
}

proc MyThreadPool_createThread {} {
   set threadId [thread::create {
      global env
      set lib_dir $env(SEQ_XFLOW_BIN)/../lib
      set auto_path [linsert $auto_path 0 $lib_dir ]

      package require SuiteNode
      package require Tk
      wm withdraw .
      thread::wait
   }]
   return ${threadId}
}

proc ThreadPool_getThread {} {
   global PoolId
   puts "ThreadPool_getThread thread(ids)"
   set foundId ""
   # find the next available thread
   foreach {threadid busy} [array get PoolId] {
      puts "ThreadPool_getThread threadid:$threadid busy:$busy"
      if { ${busy} == false } {
         set PoolId($threadid) true
         set foundId ${threadid}
         break
      }
   }
   if { ${foundId} == "" } {
      # all threads are busy, create a new one
      set foundId [ThreadPool_createThread]
      set PoolId(${foundId}) true
   }
   return ${foundId}
}

proc ThreadPool_releaseThread { thread_id } {
   global PoolId
   set PoolId($thread_id) false
}

