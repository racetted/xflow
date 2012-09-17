# x  is x coord variable used to know where to
#    display next exp
# x  is y coord variable used to know where to
#    display next exp
record define DisplayGroup {
   name
   level {0}
   parent ""
   exp_list {}
   grp_list {}
   x {0}
   y {0}
   {maxy 0}
}

# adds the group to the DisplayGroup so it can be viewed
# in the order added in the xflow.suites.xml
proc DisplayGrp_insertGroup { display_group child_group } {
   set grpList [${display_group} cget -grp_list]
   lappend grpList ${child_group}
   ${display_group} configure -grp_list ${grpList}
}

# returns the group with the same level. Mainly used
# to get the first level of groups (i.e. level 0)
proc DisplayGrp_getGroupLevel { level } {
   set groups [ExpXmlReader_getGroups]
   set result {}
   foreach displayGrp ${groups} {
      if { [${displayGrp} cget -level] == ${level} } {
         lappend result ${displayGrp}
      }
   }
   return ${result}
}

# this function locates the y slot that based on a
# given y value...
proc DisplayGrp_getCurrentSlotY { y_value } {
   global graphStartY expEntryHeight
   set tmpValue [expr ${y_value} - ${graphStartY}]
   set tmpValue [::tcl::mathop::/ ${tmpValue} ${expEntryHeight}]
   set intValue [::tcl::mathfunc::entier ${tmpValue}]
   set slotValue [expr ${graphStartY} + ${intValue} * ${expEntryHeight}]
   return ${slotValue}
}

# returns the next y slot location... This is mainly called when an exp box is conflicting with
# another one so we need to shift the exp box down to the next slot until we
# find an empty slot
proc DisplayGrp_getNextSlotY { display_group {y_value ""} } {
   global graphStartY expEntryHeight
   if { ${y_value} == "" } {
      set value [${display_group} cget -y]
   } else {
      set slotValue [DisplayGrp_getCurrentSlotY ${y_value}]
      set value [expr ${slotValue} + ${expEntryHeight}]
   }
   return ${value}
}

# sets the current y timeslots value for an experiment grouping
# the y_value is converted to the beginning of the 
# timeslot y value
proc DisplayGrp_setSlotY { display_group y_value } {
   global graphStartY expEntryHeight

   set slotValue [DisplayGrp_getCurrentSlotY ${y_value}]
   ${display_group} configure -y ${slotValue} -maxy ${slotValue}
   ::log::log debug "DisplayGrp_setSlotY currentMinY:[${display_group} cget -y] currentMaxY:[${display_group} cget -maxy]"
}

# will set the max value for the current group display
# if the value if greater than the current max...
# to force the current max value (when empty rows not needed),
# set force to be "true"
proc DisplayGrp_setMaxY { display_group y_value {force ""} } {
   global graphStartY expEntryHeight
   ::log::log debug "DisplayGrp_setMaxY ${display_group} y_value:${y_value}"

   set currentMaxY [${display_group} cget -maxy]
   set slotValue [DisplayGrp_getCurrentSlotY ${y_value}]
   if { ${force} == "true" || [expr ${slotValue} > ${currentMaxY}] } {
      ${display_group} configure -maxy ${slotValue}
   }

   if { [expr ${slotValue} < [${display_group} cget -y] ] } {
      ${display_group} configure -y ${slotValue}
   }
   ::log::log debug "DisplayGrp_setMaxY currentMaxY:[${display_group} cget -maxy]"
}


# calculates the max value of the y slot based on the exp boxes currently displayed
# on the overview canvas and set the new value
proc DisplayGrp_calcMaxY { display_group } {
   global graphStartY expEntryHeight
   set expList [${display_group} cget -exp_list]
   set overviewCanvas [Overview_getCanvas]
   set maxY [${display_group} cget -y]
   foreach exp ${expList} {
      #set suiteRecord [::SuiteNode::getSuiteRecordFromPath ${exp} ]
       set suiteRecord [::SuiteNode::formatSuiteRecord ${exp}]
      set expBoxCoords [Overview_getExpBoundaries ${overviewCanvas} ${suiteRecord}]
      if { [lindex ${expBoxCoords} 3] > ${maxY} } {
         set maxY  [lindex ${expBoxCoords} 3]
      }
   }

   # get the slot value corresponding to the y value
   set slotY [DisplayGrp_getCurrentSlotY ${maxY}]

   ${display_group} configure -maxy ${slotY}
   return ${slotY}
}

# this function will shift groups and exps up a notch if it detects empty rows
# it is useful after an exp has been moved up so the exp or suite record 
# can be used as input
proc DisplayGrp_processEmptyRows { display_group } {
   global expEntryHeight graphStartX graphHourX

   set overviewCanvas [Overview_getCanvas]

   # start with the group's 2nd y slot if any, first is allowed to be empty   
   set yslot [expr [${display_group} cget -y] + ${expEntryHeight}]
   ::log::log debug "DisplayGrp_processEmptyRows ${display_group} initial yslot:$yslot"
   # start of grid minus buffer just to be sure it picks up the boxes on the line
   set x1 [expr ${graphStartX} - 10]
   # til the end of the x graph
   set x2 [expr ${graphStartX} + 25 * ${graphHourX}]

   while { [expr ${yslot} <=  [${display_group} cget -maxy]] } {
      set y2 [expr ${yslot} + ${expEntryHeight}]
      # locate any exp items
      set itemsFound [${overviewCanvas} find enclosed ${x1} ${yslot} ${x2} ${y2}]
      if { ${itemsFound} == "" } {
         ::log::log debug "DisplayGrp_processEmptyRows ${display_group} found empty row at ${yslot}"
         # liberate the slot from the current group
         # any exp from the same group that is in the slots below must be moved up first
         
         if { ${yslot} !=  [${display_group} cget -maxy] } {
            # we're dealing with an empty slot between used slots, need to shift
            # exps from the same group first
            Overview_ShiftExpRow ${display_group} ${yslot}
            # set the new group y slot value based on shifted exps
            DisplayGrp_calcMaxY ${display_group}
         } else {
            # last row is empty set the new y value
            DisplayGrp_setMaxY ${display_group} [expr ${yslot} - ${expEntryHeight}] true
         }

         # move the rest of the groups up one slot, the current group is used as starting point
         DisplayGrp_processOverlap ${display_group}
      }
      set yslot [expr ${yslot} + ${expEntryHeight}]
   }
   ::log::log debug "DisplayGrp_processEmptyRows done"

}

# this function is called to check that display group don't overlap each other
# if they do overlap, shift the groups around.
# the input argument is used as a starting point for the check but they are
# not shifted... This function is useful when you just created or updated a exp box
# and you want to make sure that it does not walk on someone else's ground
proc DisplayGrp_processOverlap { display_group } {
   ::log::log debug "DisplayGrp_processOverlap display_group:$display_group"
   # set groupOwner [${suite_record} cget -overview_group_record]
   set displayGroups [record show instances DisplayGroup]
   set canvas [Overview_getCanvas]
   set groupIndex [lsearch ${displayGroups} ${display_group}]
   if { ${groupIndex} != -1 } {
      incr groupIndex
      if { ${groupIndex} != [llength ${displayGroups}] } {
         # only do something if not the last group, otherwise nothing to do
         set checkGroup [lindex ${displayGroups} ${groupIndex}]
   
         if { [${canvas} gettags ${checkGroup}] != "" } {
            set goodY [Overview_getGroupDisplayY ${checkGroup}]
            set currentY [${checkGroup} cget -y]
            ::log::log debug "DisplayGrp_processOverlap display_group:$display_group goodY:$goodY currentY:$currentY"
            if { ${currentY} != ${goodY} } {
               set deltaY [expr ${goodY} - ${currentY}]
               Overview_moveGroups ${checkGroup} 0 ${deltaY}
      
               # process next group only if the current one has moved
               incr groupIndex
               set nextDisplayGroup [lindex ${displayGroups} ${groupIndex}]
               DisplayGrp_processOverlap ${nextDisplayGroup}
            }
         }
      }
   }
}
