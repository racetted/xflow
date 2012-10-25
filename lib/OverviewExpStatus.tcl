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

proc OverviewExpStatus_removeStatusDatestamp { _exp_path _datestamp _canvas } {
   global datestamps_${_exp_path}
   if { [info exists datestamps_${_exp_path}(${_datestamp})] } {
      array unset datestamps_${_exp_path} ${_datestamp}
   }
   SharedData_removeExpDisplayData ${_exp_path} ${_datestamp} ${_canvas}

   foreach key { offset update_afterid rootnode startup modules node_mappings updated_nodes } {
      SharedData_unsetExpDatestampData ${_exp_path} ${_datestamp} ${key}
   }
}
