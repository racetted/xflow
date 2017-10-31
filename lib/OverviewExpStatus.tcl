proc OverviewExpStatus_getStatusClockValue { exp_path datestamp status } {
   set value ""
   set statusInfo [OverviewExpStatus_getStatusInfo ${exp_path} ${datestamp} ${status}]
   set dateTime "[lindex ${statusInfo} 0] [lindex ${statusInfo} 1]"
   if { [string length ${dateTime}] > 1} {
      set value [clock scan "${dateTime}"]
   }
   return ${value}
}

# gives the date & time in seconds that should be
# used to compare with the overview grid limits
# if the start time is greater than current time && 
# end reference time (hh::mm) is prior to current time, 
# return previous day value for the start time
# else return today's value value
proc OverviewExpStatus_getStartRelativeClockValue { ref_start_time ref_end_time } {
   set currentDateTime [clock seconds]
   set currentTime [clock format ${currentDateTime} -format "%H:%M" -gmt 1]
   set startDateTime [clock scan ${ref_start_time}]
   set endDateTime [clock scan ${ref_end_time}]
   if { ${startDateTime} > ${currentDateTime} && ${endDateTime} < ${currentDateTime} } {
      set value [clock add ${startDateTime} -24 hours ]
   } else {
      set value ${startDateTime}
   }

   return ${value}
}


proc OverviewExpStatus_setLastStatusInfo { exp_path datestamp status date time } {
   # start synchronizing this block, get an exclusive lock

   # puts "OverviewExpStatus_setLastStatusInfo ${exp_path} ${datestamp} ${status} ${date} ${time}"
   # if the status is beginx and the suite already has a begin value... I don't
   # store the begin time.. this means that it is a ripple effect and I don't want
   # the overview box to be moved to the new time...
   if { ${status} == "beginx" } {
      if { [OverviewExpStatus_getStatusInfo ${exp_path} ${datestamp} begin ] == "" } {
         OverviewExpStatus_setStatusInfo ${exp_path} ${datestamp} begin "${date} ${time}"
      }
      OverviewExpStatus_setStatusInfo ${exp_path} ${datestamp} last begin
   } else {
      OverviewExpStatus_setStatusInfo ${exp_path} ${datestamp} ${status} "${date} ${time}"   
      OverviewExpStatus_setStatusInfo ${exp_path} ${datestamp} last ${status}
   }

}

proc OverviewExpStatus_getLastStatus { exp_path datestamp } {
   set value init
   if { ! [string match "default*" ${datestamp}] } {
      set value [OverviewExpStatus_getStatusInfo ${exp_path} ${datestamp} last]
      if { ${value} == "" } {
         set value init
      }
   }
   return  ${value}
}

proc OverviewExpStatus_getLastStatusTime { exp_path datestamp } {

   set lastStatus [OverviewExpStatus_getStatusInfo ${exp_path} ${datestamp} last]
   set statusInfo [OverviewExpStatus_getStatusInfo ${exp_path} ${datestamp} ${lastStatus}]
   set value [lindex ${statusInfo} 1]
   return  ${value}
}

proc OverviewExpStatus_getLastStatusDateTime { exp_path datestamp } {

   set lastStatus [OverviewExpStatus_getStatusInfo ${exp_path} ${datestamp} last]
   set statusInfo [OverviewExpStatus_getStatusInfo ${exp_path} ${datestamp} ${lastStatus}]
   set value [clock scan ${statusInfo}]
   return  ${value}
}

proc OverviewExpStatus_getStartTime { exp_path datestamp } {
   set statusInfo [OverviewExpStatus_getStatusInfo ${exp_path} ${datestamp} begin]
   set value [lindex ${statusInfo} 1]
   return ${value}
}

proc OverviewExpStatus_getEndTime { exp_path datestamp } {
   set statusInfo [OverviewExpStatus_getStatusInfo ${exp_path} ${datestamp} end]
   set value [lindex ${statusInfo} 1]
   return ${value}
}

# the following data are related to experiment datestamp status as a whole and it is only used
# by the overview... therefore do not need to put in a tsv shared structure
proc OverviewExpStatus_getDatestamps { _exp_path } {
   global datestamps_${_exp_path}
   set datestampList [array names datestamps_${_exp_path}]
   return ${datestampList}
}

proc OverviewExpMsgCenter_getactiveInfo { key } { 
   global msg_active_List

   set value 0
   if { [info exists msg_active_List($key)] } {
     set value $msg_active_List(${key})
   } 
   return ${value}
}

proc OverviewExpMsgCenter_gettotalInfo { key } { 
   global msg_tt_list

   set value 0
   if { [info exists msg_tt_list($key)] } {
     set value $msg_tt_list(${key})
   } 
   return ${value}
}
proc OverviewExpStatus_setStatusInfo { _exp_path _datestamp _status _status_info  } {
   global datestamps_${_exp_path}
   # puts "in OverviewExpStatus_setStatusInfo $_exp_path $_datestamp status:$_status statusinfo:$_status_info"
   if { ![info exists datestamps_${_exp_path}] } {
      array set datestamps_${_exp_path} {}
   }
   # array set datestamps [SharedData_getExpData ${_exp_path} datestamps]
   
   if { [info exists datestamps_${_exp_path}(${_datestamp})] } {
      set statusList [set datestamps_${_exp_path}(${_datestamp})]
      set index [lsearch ${statusList} ${_status}]
      #puts "OverviewExpStatus_setStatusInfo index:$index"
      if { ${_status} == "last" } {
         if { ${index} == -1 } {
            lappend statusList ${_status} "${_status_info}"
         } else {
            set valueIndex [incr index]
            set statusList [lreplace ${statusList} ${valueIndex} ${valueIndex} ${_status_info}]
         }
      } else {
         if { ${index} != -1 } {
            set valueIndex [incr index]
            set statusList [lreplace ${statusList} ${valueIndex}  ${valueIndex}  ${_status_info}]
         } else {
            set statusList [linsert ${statusList} 0 ${_status} "${_status_info}"]
         }
      }
   } else {
      set statusList [list ${_status} "${_status_info}"]
   }
   set datestamps_${_exp_path}(${_datestamp}) ${statusList}
   # SharedData_setExpData ${_exp_path} datestamps "[array get datestamps]"

}

proc OverviewExpStatus_getStatusInfo { _exp_path _datestamp _status } {
   global datestamps_${_exp_path}
   set value ""
   # array set datestamps [SharedData_getExpData ${_exp_path} datestamps]
   if { [info exists datestamps_${_exp_path}(${_datestamp})] } {
      set statusList [set datestamps_${_exp_path}(${_datestamp})]
      # set statusList $datestamps(${_datestamp})
      set index [lsearch ${statusList} ${_status}]
      if { ${index} != -1 } {
         set valueIndex [incr index]
         set value [lindex ${statusList} ${valueIndex}]
      }
   }

   return ${value}
}

proc OverviewExpStatus_removeStatusDatestamp { _exp_path _datestamp } {
   ::log::log notice "OverviewExpStatus_removeStatusDatestamp() exp_path:${_exp_path} datestamp:${_datestamp}"
   global datestamps_${_exp_path}
   if { [info exists datestamps_${_exp_path}(${_datestamp})] } {
      array unset datestamps_${_exp_path} ${_datestamp}
   }

   SharedFlowNode_removeDatestamp ${_exp_path} ${_datestamp}

   ::log::log notice "OverviewExpStatus_removeStatusDatestamp() exp_path:${_exp_path} datestamp:${_datestamp} DONE"
}

proc OverviewExpStatus_addStatusDatestamp { _exp_path _datestamp } {
   global datestamps_${_exp_path}
   if { ![info exists datestamps_${_exp_path}] } {
      array set datestamps_${_exp_path} {}
   }
   if { ! [info exists datestamps_${_exp_path}(${_datestamp})] } {
      set datestamps_${_exp_path}(${_datestamp}) ""
   }
}

proc OverviewExpStatus_printStatusDatestamp { _exp_path {_datestamp ""} } {
   global datestamps_${_exp_path}
   puts "-------------------------------------------"
   puts "${_exp_path}"
   puts "-------------------------------------------"
   #array set datestamps [SharedData_getExpData ${_exp_path} datestamps]
   set datestamps [OverviewExpStatus_getDatestamps ${_exp_path}]
   foreach datestamp ${datestamps} {
      # set statusList $datestamps(${datestamp})
      set statusList [set datestamps_${_exp_path}(${_datestamp})]
      puts "datestamp:${datestamp} statuses:${statusList}"
   }
}

proc OverviewExpStatus_reactivateDatestamp { _exp_path _datestamp } {
   global obsolete_datestamps
   if { [info exists obsolete_datestamps] } {
      set key ${_exp_path}_${_datestamp}
      if { [info exists datestamps_${_exp_path}(${_datestamp})] } {
         unset obsolete_datestamps($key)
         ::log::log notice "OverviewExpStatus_reactivateObseleteDatestamps() reactivating exp_path:${_exp_path} datestamp:${_datestamp}"
      }
   }
}

proc OverviewExpStatus_addObsoleteDatestamp {  _exp_path _datestamp } {
   global obsolete_datestamps
   ::log::log notice "OverviewExpStatus_addObseleteDatestamps() ${_exp_path} ${_datestamp} started..."
   if { ! [info exists obsolete_datestamps] } {
      array set obsolete_datestamps {}
   }
   set key ${_exp_path}_${_datestamp}
   set obsolete_datestamps(${key}) "${_exp_path} ${_datestamp}"
   ::log::log notice "OverviewExpStatus_addObseleteDatestamps() ${_exp_path} ${_datestamp} DONE"
}

proc OverviewExpStatus_checkObseleteDatestamps {} {
  global obsolete_datestamps
  ::log::log notice "OverviewExpStatus_checkObseleteDatestamps()  started..."
  foreach key [array names obsolete_datestamps] {
     set keyValue $obsolete_datestamps($key)
     set exp_path [lindex ${keyValue} 0 ]
     set datestamp [lindex ${keyValue} 1 ]
     if { ${exp_path} != "" && ${datestamp} != "" } {
        if { [Overview_isExpBoxObsolete ${exp_path} ${datestamp}] == true && [LogMonitor_isLogFileActive ${exp_path} ${datestamp}] == false && [xflow_isWindowActive ${exp_path} ${datestamp}] == false } {
	   # the end time happened prior to the x origin time,
           # clean any data kept for the datestamp

	   # I need to make sure the log file is not monitored first before releasing the data
	   # sometimes the log file has just been modified even though it does not affect the node (EVENT DELAYS for instance)
	   # so if the box is obsolete... force release of the log
           set expThreadId [SharedData_getExpThreadId ${exp_path} ${datestamp}]
           Overview_releaseLoggerThread ${expThreadId} ${exp_path} ${datestamp}

           ::log::log notice "OverviewExpStatus_checkObseleteDatestamps() OverviewExpStatus_removeStatusDatestamp exp_path:${exp_path} datestamp:${datestamp}"
           OverviewExpStatus_removeStatusDatestamp ${exp_path} ${datestamp}
           ::log::log notice "OverviewExpStatus_checkObseleteDatestamps() ShareData_removeExpDatestampData exp_path:${exp_path} datestamp:${datestamp}"
           SharedData_removeExpDatestampData ${exp_path} ${datestamp}
           ::log::log notice "OverviewExpStatus_checkObseleteDatestamps() OverviewExpStatus_removeStatusDatestamp exp_path:${exp_path} datestamp:${datestamp} DONE"
	   unset obsolete_datestamps($key)
           ::log::log notice "OverviewExpStatus_checkObseleteDatestamps() exp_path:${exp_path} datestamp:${datestamp} unset obsolete_datestamps DONE."

	   SharedData_removeExpDatestampMutex ${exp_path} ${datestamp}
	}
     }
  }
  ::log::log notice "OverviewExpStatus_checkObseleteDatestamps() DONE"
}




