# should be called at application startup time to create
# the desired number of threads to process exp datestamps.
# The number of threads is configurable through the maestrorc file (overview_num_threads)
# Defaults to 4 threads.
# Each experiment active log datestamp is assigned a thread from the thread pool.
# Each thread can monitor multiple log datestamps.
# An active log file is one that has been modified within the last hour.
proc ThreadPool_init { nof_thread } {
   set done false
   set count 0
   ::log::log notice "ThreadPool_init(): creating ${nof_thread} threads..."
   while { ${done} == false } {
      set threadId [ThreadPool_addNewThread]
      incr count
      if { ${count} == ${nof_thread} } {
         set done true
      }
   }
   ::log::log notice "ThreadPool_init(): creating ${nof_thread} threads done"
}

# create new thread and add to pool
proc ThreadPool_addNewThread {} {
   global PoolId
   set threadId [ThreadPool_createThread]
   set PoolId(${threadId}) false
   ::log::log notice "ThreadPool_addNewThread(): adding thread:${threadId} to pool"
}

proc ThreadPool_createThread { {is_init false} } {
   if { ${is_init} == false } {
      ::log::log notice "ThreadPool_createThread(): creating new thread"
   }

   set threadId [thread::create {
      global env
      source $env(SEQ_XFLOW_BIN)/../lib/utils.tcl
      source $env(SEQ_XFLOW_BIN)/../lib/FileLogger.tcl
      source $env(SEQ_XFLOW_BIN)/../lib/FlowXml.tcl
      source $env(SEQ_XFLOW_BIN)/../lib/LogReader.tcl
      # source $env(SEQ_XFLOW_BIN)/../lib/LogMonitor.tcl
      source $env(SEQ_XFLOW_BIN)/../lib/TsvInfo.tcl
      source $env(SEQ_XFLOW_BIN)/../lib/SharedData.tcl
      source $env(SEQ_XFLOW_BIN)/../lib/SharedFlowNode.tcl
      source $env(SEQ_XFLOW_BIN)/../lib/ThreadPool.tcl

      Utils_logInit
      thread::wait
   }]

   return ${threadId}
}

# retrieve a thread from the thread pool
# If all threads are busy,
# the client as the option of waiting until a thread is available
# or not..in such case an empty string is returned
#
# The wait true is mainly used at startup where we do not want
# to overload with thread creation... instead we wait for the threads
# to be released i.e. small log files will be processed very fast so the
# thread will be re-used
#
proc ThreadPool_getThread { {wait false} } {
   global PoolId THREAD_RELEASE_EVENT

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
         if { ${wait} == true } {
            ::log::log notice "ThreadPool_getThread(): all threads are busy.. waiting for one"
            ::log::log debug "ThreadPool_getThread(): all threads are busy.. waiting for one"
            vwait THREAD_RELEASE_EVENT
            ::log::log notice "ThreadPool_getThread(): got new thread"
         } else {
            ::log::log debug "ThreadPool_getThread(): all threads are busy.. creating new one"
            ::log::log notice "ThreadPool_getThread(): all threads are busy.. creating new one"
            set threadId [ThreadPool_createThread]
         }
         set PoolId(${threadId}) true
         set foundId ${threadId}
      }
      set done true
   }


   return ${foundId}
}

# assign a thread from the list of available pool
proc ThreadPool_getNextThread {} {
   global PoolId ThreadPool_Counter

   if { ! [info exists ThreadPool_Counter] } {
      set ThreadPool_Counter 0
   }
   set threadList [array names PoolId]
   set threadId [lindex ${threadList} ${ThreadPool_Counter}]
   incr ThreadPool_Counter
   if { ${ThreadPool_Counter} == [array size PoolId] } {
      set ThreadPool_Counter 0
   }
   return ${threadId}
}

# release the thread and make it available again in the pool
# A release thread event is issued to notify potential clients waiting
# for a thread release
proc ThreadPool_releaseThread { thread_id args } {
   global PoolId THREAD_RELEASE_EVENT
   set maxThreads [SharedData_getMiscData OVERVIEW_NUM_THREADS]
   if { [array size PoolId] > ${maxThreads} } {
      array unset PoolId ${thread_id}
      ::log::log notice "ThreadPool_releaseThread(): nof threads over maximum: ${maxThreads}... releasing thread: ${thread_id} ${args}"
      thread::release ${thread_id}
   } else {
      set PoolId($thread_id) false
      set THREAD_RELEASE_EVENT true
   }
}

# destroys the thread and remove from pool
proc ThreadPool_dropThread { thread_id } {
   global PoolId
   array unset PoolId ${thread_id}
   if { [thread::exists ${thread_id}] } {
      thread::release ${thread_id}
   }
   ::log::log notice "ThreadPool_dropThread(): thread::release ${thread_id}"
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

proc ThreadPool_quit {} {
   global PoolId
   foreach {threadid busy} [array get PoolId] {
      thread::release ${threadid}
   }
}
