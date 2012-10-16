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
      source $env(SEQ_XFLOW_BIN)/../lib/utils.tcl
      source $env(SEQ_XFLOW_BIN)/../lib/FlowXml.tcl
      source $env(SEQ_XFLOW_BIN)/../lib/LogReader.tcl
      source $env(SEQ_XFLOW_BIN)/../lib/LogMonitor.tcl
      source $env(SEQ_XFLOW_BIN)/../lib/SharedData.tcl
      source $env(SEQ_XFLOW_BIN)/../lib/SharedFlowNode.tcl
      source $env(SEQ_XFLOW_BIN)/../lib/OverviewUtils.tcl

      thread::wait
   }]
   return ${threadId}
}

# retrieve a thread from the thread pool
# If all threads are busy,
# the client as the option of waiting until a thread is available
# or not..in such case an empty string is returned
proc ThreadPool_getThread { {wait false} } {
   global PoolId
   set foundId ""
   set done false
   while { ${done} == false } {
      # find the next available thread
      foreach {threadId busy} [array get PoolId] {
         if { ${busy} == false } {
            set PoolId(${threadId}) true
            set foundId ${threadId}
            break
         }
      }
      if { ${foundId} == "" } { 
         ::log::log notice "ThreadPool_getThread(): all threads are busy.. creating new one"
         set threadId [ThreadPool_createThread]
         set PoolId(${threadId}) true
         set foundId ${threadId}
      }
      set done true
   }

   return ${foundId}
}

# release the thread and make it available again in the pool
# A release thread event is issued to notify potential clients waiting
# for a thread release
proc ThreadPool_releaseThread { thread_id } {
   global PoolId
   set maxThreads [SharedData_getMiscData MAX_XFLOW_INSTANCE]
   if { [array size PoolId] > ${maxThreads} } {
      array unset PoolId $thread_id
      thread::release ${thread_id}
   } else {
      set PoolId($thread_id) false
   }
}

proc ThreadPool_showThreadStatus {} {
   global PoolId
   foreach {threadid busy} [array get PoolId] {
      puts "ThreadPool_showThreadStatus threadid:$threadid busy:$busy"
      if { ${busy} == true } {
         catch {
            # set activeSuite [thread::send ${threadid} xflow_getActiveSuite]
            puts "threadid:$threadid"
         }
      }
   }
}
