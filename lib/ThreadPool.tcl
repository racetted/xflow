# should be called at application startup time to create
# the desired number of threads to process exp datestamps.
# The number of threads is configuration thourgh the maestrorc file (max_xflow_instance)
# Defaults to 25 threads.
# Each opened xflow window is assigned a thread and each active log file gets assigned a thread
# An active log file is one that has been modified within the last hour.
proc ThreadPool_init { nof_thread } {
   global PoolId count
   set done false
   set count 0
   ::log::log notice "ThreadPool_init(): creating ${nof_thread} threads..."
   while { ${done} == false } {
      set threadId [ThreadPool_createThread]
      # puts "ThreadPool_init thread no: ${count} creation done..."
      set PoolId(${threadId}) false
      incr count
      if { ${count} == ${nof_thread} } {
         set done true
      }
   }
}

proc ThreadPool_createThread {} {
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

# retrieve a thread from the thread pool
# If all threads are busy,
# the client as the option of waiting until a thread is available
# or not..in such case an empty string is returned
proc ThreadPool_getThread { {wait false} } {
   global PoolId THREAD_RELEASE_EVENT
   # puts "ThreadPool_getThread thread(ids)"
   set foundId ""
   set done false
   while { ${done} == false } {
      # find the next available thread
      foreach {threadid busy} [array get PoolId] {
         # puts "ThreadPool_getThread threadid:$threadid busy:$busy"
         if { ${busy} == false } {
            set PoolId($threadid) true
            set foundId ${threadid}
            break
         }
      }
      if { ${foundId} == "" } { ::log::log debug "ThreadPool_getThread(): all threads are busy" }
      if { ${foundId} == "" && ${wait} == true } {
         ::log::log debug "ThreadPool_getThread(): waiting for available thread"
         # wait for another thread to be released
         vwait THREAD_RELEASE_EVENT
         ::log::log debug "ThreadPool_getThread(): got new thread"
      } else {
         set done true
      }
   }

   return ${foundId}
}

# release the thread and make it available again in the pool
# A release thread event is issued to notify potential clients waiting
# for a thread release
proc ThreadPool_releaseThread { thread_id } {
   global PoolId THREAD_RELEASE_EVENT
   set PoolId($thread_id) false
   set THREAD_RELEASE_EVENT true
}