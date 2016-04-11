package require struct::record
namespace import ::struct::record::*

#   name : name of group as it appears in xml file
#   dname : name of group internally (directory name)
#   level : level of group 
#   parent : parent group dname
#   exp_list : list of experiment that this group contains
#   grp_list : list of group that this group contains
#   max_y : display coord variable max y used
#   x :  is x coord variable used to know where to
#       display next exp
#   y : is y coord variable used to know where to
#       display next exp
record define DisplayGroup {
   name
   dname
   level {0}
   parent ""
   exp_list {}
   grp_list {}
   x {0}
   y {0}
   {max_x 0}
   {max_y 0}
}

proc DisplayGrp_createDefaultGroup { exp_path  } {
   global  DISPLAY_GROUPS
   set groupName [file tail ${exp_path}]
   set defaultGroupId [DisplayGroup ${groupName} -name ${groupName} -level 0 -exp_list [list ${exp_path}]]
   lappend DISPLAY_GROUPS $defaultGroupId
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

# set the maximum x value of the group
proc DisplayGrp_setMaxX { display_group } {
   set expCanvas [Overview_getCanvas]
   set groupCanvas [Overview_getGroupDisplayCanvas]
   # set groupTag [${groupCanvas} find withtag [DisplayGrp_getTagName ${display_group}]]
   set groupTag [DisplayGrp_getTagName ${display_group}]

   set groupBoundaries [${expCanvas} bbox ${groupTag}]
   if { ${groupBoundaries} == "" } {
      set groupBoundaries [${groupCanvas} bbox ${groupTag}]
   }
   # puts "DisplayGrp_setMaxX:$groupTag groupBoundaries:$groupBoundaries"

   catch {
      ${display_group} configure -x [lindex ${groupBoundaries} 0] 
      ${display_group} configure -max_x [lindex ${groupBoundaries} 2] 
   }
}

proc DisplayGrp_getAllGroupMaxX { canvas } {
   set maxX 0
   set coords [${canvas} bbox DisplayGroup]
   if { ${coords} != "" } {
      set maxX [lindex ${coords} 2]
   }

   # puts "DisplayGrp_getAllGroupMaxX maxX:$maxX"
   return ${maxX}
}

proc DisplayGrp_getTagName { display_group } {
   return displayGroup_${display_group}
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
   ${display_group} configure -y ${slotValue} -max_y ${slotValue}
   ::log::log debug "DisplayGrp_setSlotY currentMinY:[${display_group} cget -y] currentMaxY:[${display_group} cget -max_y]"
}

# will set the max value for the current group display
# if the value if greater than the current max...
# to force the current max value (when empty rows not needed),
# set force to be "true"
proc DisplayGrp_setMaxY { display_group y_value {force ""} } {
   global graphStartY expEntryHeight
   ::log::log debug "DisplayGrp_setMaxY ${display_group} y_value:${y_value}"

   set currentMaxY [${display_group} cget -max_y]
   set slotValue [DisplayGrp_getCurrentSlotY ${y_value}]
   if { ${force} == "true" || [expr ${slotValue} > ${currentMaxY}] } {
      ${display_group} configure -max_y ${slotValue}
   }

   if { [expr ${slotValue} < [${display_group} cget -y] ] } {
      ${display_group} configure -y ${slotValue}
   }
   ::log::log debug "DisplayGrp_setMaxY currentMaxY:[${display_group} cget -max_y]"
}


# calculates the max value of the y slot based on the exp boxes currently displayed
# on the overview canvas and set the new value
proc DisplayGrp_calcMaxY { display_group } {
   set canvas [Overview_getCanvas]
   set maxY [${display_group} cget -y]
   set expGroupBoxTag [DisplayGrp_getGroupExpBoxTagName ${display_group}]
   set expBoxTags [${canvas} find withtag ${expGroupBoxTag}]
   foreach expBoxTag ${expBoxTags} {
      set boxBoundaries [${canvas} coords ${expBoxTag}]
      if { [lindex ${boxBoundaries} 3] > ${maxY} } {
         set maxY  [lindex ${boxBoundaries} 3]
      }
   }

   # get the slot value corresponding to the y value
   set slotY [DisplayGrp_getCurrentSlotY ${maxY}]

   ${display_group} configure -max_y ${slotY}
   return ${slotY}
}

# this function will shift groups and exps up a notch if it detects empty rows
# it is useful after an exp has been moved up so the exp
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

   while { [expr ${yslot} <=  [${display_group} cget -max_y]] } {
      set y2 [expr ${yslot} + ${expEntryHeight}]
      # locate any exp items
      set itemsFound [${overviewCanvas} find enclosed ${x1} ${yslot} ${x2} ${y2}]
      if { ${itemsFound} == "" } {
         ::log::log debug "DisplayGrp_processEmptyRows ${display_group} found empty row at ${yslot}"
         # liberate the slot from the current group
         # any exp from the same group that is in the slots below must be moved up first
         
         if { ${yslot} !=  [${display_group} cget -max_y] } {
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
   set displayGroups [ExpXmlReader_getGroups]
   set canvas [Overview_getCanvas]
   set groupCanvas [Overview_getGroupDisplayCanvas]
   set groupIndex [lsearch ${displayGroups} ${display_group}]
   if { ${groupIndex} != -1 } {
      incr groupIndex
      if { ${groupIndex} != [llength ${displayGroups}] } {
         # only do something if not the last group, otherwise nothing to do
         set checkGroup [lindex ${displayGroups} ${groupIndex}]
         set checkGroupTag [DisplayGrp_getTagName ${checkGroup}] 
         if { [${groupCanvas} gettags ${checkGroupTag}] != "" } {
            set goodY [DisplayGrp_getGroupDisplayY ${checkGroup}]
            set currentY [${checkGroup} cget -y]
            ::log::log debug "DisplayGrp_processOverlap display_group:$display_group goodY:$goodY currentY:$currentY"
            if { ${currentY} != ${goodY} } {
               set deltaY [expr ${goodY} - ${currentY}]
               ::log::log debug "DisplayGrp_processOverlap Overview_moveGroups ${checkGroup} 0 ${deltaY}"
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

proc DisplayGrp_getGroupDisplayX { group_display } {
   global entryStartX
   set parentGroup [${group_display} cget -parent]
   set groupLevel [${group_display} cget -level]
   set displayX [expr $entryStartX + 4 + $groupLevel * 15]
   if { ${parentGroup} != "" } {
      set displayX [expr [${parentGroup} cget -max_x] + 5]
   }
   ::log::log debug "DisplayGrp_getGroupDisplayX group_display:${group_display} displayX:${displayX}" 
   return ${displayX}
}

# returns the y position that a group should be displayed based on the
# group already displayed prior to itself. This function should be useful
# at startup when we add the display groups one by one
proc DisplayGrp_getGroupDisplayY { group_display } {
   # puts "DisplayGrp_getGroupDisplayY ${group_display}"
   global entryStartY expEntryHeight
   set displayGroups [ExpXmlReader_getGroups]
   set myIndex [lsearch -exact ${displayGroups} ${group_display}]
   if { ${myIndex} == -1 || ${myIndex} == 0 } {
      # puts "DisplayGrp_getGroupDisplayY group_display;$group_display first group"
      # not found or first group, return the start y
      ::log::log debug "DisplayGrp_getGroupDisplayY group_display:${group_display} first group:  value:${entryStartY}" 
      return ${entryStartY}
   }

   # get the previous group from the list
   set prevGroup [lindex ${displayGroups} [expr ${myIndex} - 1]]
   set prevGroupLevel [${prevGroup} cget -level]
   set prevGroupBoundaries  [DisplayGrp_getOneGroupBoundaries [Overview_getCanvas] ${prevGroup}]
   set prevGroupY [lindex ${prevGroupBoundaries} 3]

   set thisGroupLevel [$group_display cget -level]

   if { ${prevGroupLevel} < ${thisGroupLevel} } {
      # we are changing group level
      # the current group will be located just next to the previous one, on the same line to optimize spacing
      # puts "DisplayGrp_getGroupDisplayY changing group_display;$group_display"
      set thisGroupY [${prevGroup} cget -y]
   } else {
      set thisGroupY [DisplayGrp_getNextSlotY ${prevGroup} ${prevGroupY}]
      # puts "DisplayGrp_getGroupDisplayY group_display;$group_display prevGroup:$prevGroup prevGroupY:$prevGroupY next slot:$thisGroupY"
   }

   #set thisGroupY [Overview_GroupNextY ${prevGroupY}]
   ::log::log debug "DisplayGrp_getGroupDisplayY group_display:${group_display} value: ${thisGroupY}"
   return ${thisGroupY}
}

#  the name tag that is associated with every exp box in the exp canvas
proc DisplayGrp_getGroupExpBoxTagName { display_group } {
   return exp_box.${display_group}
}

# returns the boundaries of a DisplayGroup record
# that covers the entire rows that are used by the display group
# the Display Group + every rows used by its exp boxes
proc DisplayGrp_getOneGroupBoundaries { canvas display_group } {
   global graphX graphStartX graphHourX
   set groupCanvas [Overview_getGroupDisplayCanvas]
   set groupTagName [DisplayGrp_getTagName ${display_group}]
   set groupExpTagName [DisplayGrp_getGroupExpBoxTagName ${display_group}]
   set startx ${graphStartX}
   set endX [expr ${startx} + 24 * ${graphHourX}]
   # get the boundaries from the exp canvas
   # it would only contain the box around the exp boxes
   set boundaries [${canvas} bbox ${groupExpTagName}]
   if { ${boundaries} == "" } {
      # not found try from the group canvas
      set groupCanvas [Overview_getGroupDisplayCanvas]
      set boundaries [${groupCanvas} bbox ${groupTagName}]
   }

   # the bbox adds a few pixels to the real boundary... It it sensitive for box collision check so
   # I'm removing a few pixels ... especially on the Y axis.
   if { ${boundaries} != "" } {
      set boundaries [list ${startx} [expr [lindex ${boundaries} 1] + 5] ${endX} [expr [lindex ${boundaries} 3] - 5]]
   }

   return ${boundaries}
}


proc DisplayGrp_getWindowsLabel { {exp_path ""} } {
   set myLabel ""
   set windowsLabel [SharedData_getMiscData WINDOWS_LABEL]
   # check if exp is part of monitored list.
   # For example, a remote dependant suite would not be part of the monitored list
   if { ${exp_path} == "" || (${exp_path} != "" && [SharedData_getExpGroupDisplay ${exp_path}] != "") } {
      set myLabel ${windowsLabel}
   }

   return ${myLabel}
}
