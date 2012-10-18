proc OverviewUtils_getStatusClockValue { exp_path datestamp status } {
   set value ""
   set statusInfo [SharedData_getStatusInfo ${exp_path} ${datestamp} ${status}]
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
proc OverviewUtils_getStartRelativeClockValue { ref_start_time ref_end_time } {
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


proc OverviewUtils_setLastStatusInfo { exp_path datestamp status date time } {
   # start synchronizing this block, get an exclusive lock

   # puts "OverviewUtils_setLastStatusInfo ${exp_path} ${datestamp} ${status} ${date} ${time}"
   # if the status is beginx and the suite already has a begin value... I don't
   # store the begin time.. this means that it is a ripple effect and I don't want
   # the overview box to be moved to the new time...
   if { ${status} == "beginx" } {
      if { [SharedData_getStatusInfo ${exp_path} ${datestamp} begin ] == "" } {
         SharedData_setStatusInfo ${exp_path} ${datestamp} begin "${date} ${time}"
      }
      SharedData_setStatusInfo ${exp_path} ${datestamp} last begin
   } else {
      SharedData_setStatusInfo ${exp_path} ${datestamp} ${status} "${date} ${time}"   
      SharedData_setStatusInfo ${exp_path} ${datestamp} last ${status}
   }

}

proc OverviewUtils_getLastStatus { exp_path datestamp } {
   set value init
   if { ! [string match "default*" ${datestamp}] } {
      set value [SharedData_getStatusInfo ${exp_path} ${datestamp} last]
      if { ${value} == "" } {
         set value init
      }
   }
   return  ${value}
}

proc OverviewUtils_getLastStatusTime { exp_path datestamp } {

   set lastStatus [SharedData_getStatusInfo ${exp_path} ${datestamp} last]
   set statusInfo [SharedData_getStatusInfo ${exp_path} ${datestamp} ${lastStatus}]
   set value [lindex ${statusInfo} 1]
   return  ${value}
}

proc OverviewUtils_getStartTime { exp_path datestamp } {
   set statusInfo [SharedData_getStatusInfo ${exp_path} ${datestamp} begin]
   set value [lindex ${statusInfo} 1]
   return ${value}
}

proc OverviewUtils_getEndTime { exp_path datestamp } {
   set statusInfo [SharedData_getStatusInfo ${exp_path} ${datestamp} end]
   set value [lindex ${statusInfo} 1]
   return ${value}
}