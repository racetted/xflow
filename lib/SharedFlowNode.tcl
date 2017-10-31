package require Thread

# This file contains the info of FlowNodes, the nodes that appears in the flow
# The info is mainly stored in two shared structures. It uses tsv shared structures so that
# the information can be shared between the overview main thread, the msg center main thread and
# the experiment datestamp thread that monitors the nodelogger log files.
#
# The firs data structure SharedFlowNode_${exp_path}_${datestamp}  stores the static information of a flow with respect to
# a datestamp: the flow information (submits relation, node types, loop data, etc)
# The second one ${exp_path}_${datestamp}_runtim stores the dynamic information for each node 
# i.e. current status, begin time, abort time, etc.
#
# generic argument:
# exp_path: full path of the experiment i.e. SEQ_EXP_HOME
# node: the flow node as seen in xflow i.e. the submit path and not the container path
# datestamp: the full datestamp in format yyyymmddhh0000

# creates a new node. Mainly called by FlowXml when parsing the flow.xml file.
# submitter: flow node path of the node that submits the new node
# type: one of task, family, module, npass_task, loop
proc SharedFlowNode_createNode { exp_path node datestamp submitter type } {
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp} ${node} name [file tail ${node}] type ${type} submitter ${submitter} loops {} submits {} work_unit 0

   if { {$type} == "module" } {
      SharedData_addExpModule ${exp_path} ${node} ${datestamp}
   }

   SharedFlowNode_initNodeDatestampDisplay $exp_path $node $datestamp
}

# remove the datestamp completely... This is called to cleanup data for a datestamp that is not viewed anymore
#
proc SharedFlowNode_removeDatestamp { exp_path datestamp } {
   ::log::log notice "SharedFlowNode_removeDatestamp ${exp_path} ${datestamp}"

   ::log::log notice "SharedFlowNode_removeDatestamp tsv::unset SharedFlowNode_${exp_path}_${datestamp}_runtime"
   catch { tsv::unset SharedFlowNode_${exp_path}_${datestamp}_runtime }
   ::log::log notice "SharedFlowNode_removeDatestamp tsv::unset SharedFlowNode_${exp_path}_${datestamp}_runtime DONE"

   catch { tsv::unset SharedFlowNode_${exp_path}_${datestamp}_gui_runtime }
   catch { tsv::unset SharedFlowNode_${exp_path}_${datestamp}_stats }

   ::log::log notice "SharedFlowNode_removeDatestamp tsv::unset SharedFlowNode_${exp_path}_${datestamp}"
   catch { tsv::unset SharedFlowNode_${exp_path}_${datestamp} }

   ::log::log notice "SharedFlowNode_removeDatestamp tsv::unset SharedFlowNode_${exp_path}_${datestamp} DONE"
   ::log::log notice "SharedFlowNode_removeDatestamp ${exp_path} ${datestamp} DONE"

   catch { tsv::unset TsvNodeResourceVar_${exp_path}_${datestamp} }
}

# this is a generic attribute accessor for the SharedFlowNode_${exp_path}_${datestamp} data structure
# resource file attributes cpu, wallclock, memory... are now retrieved from tsvinfo
# and not directly from xml resource file
# So not available anymore from SharedFlowNode_ structure
proc SharedFlowNode_getGenericAttribute { exp_path node datestamp attr_name } {
   set value ""
   catch {
      set value [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} ${attr_name}]
   }
   return ${value}
}

# this is a generic attribute setter for the SharedFlowNode_${exp_path}_${datestamp} data structure
proc SharedFlowNode_setGenericAttribute { exp_path node datestamp attr_name attr_value } {
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp} ${node} ${attr_name} ${attr_value}
}

proc SharedFlowNode_isNodeExist { exp_path node datestamp } {
   set isExist false
   if { [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} ] != "" } {
      set isExist true
   }

   return ${isExist}
}

proc SharedFlowNode_getNodeType { exp_path node datestamp } {
   set value ""
   set result [ catch { set value [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} type] } errmsg ] 
   if { ${result} != 0  } {

      set einfo $::errorInfo
      set ecode $::errorCode
      set message "Problem retrieving node=${node} : possible flow.xml error : ${errmsg}"
      puts stderr "ERROR: ${message}"
      error ${message} ${einfo} ${ecode}
   }
  
   return ${value}
}

proc SharedFlowNode_getSubmitter { exp_path node datestamp } {
   tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} submitter
}

proc SharedFlowNode_getName { exp_path node datestamp } {
   tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} name
}

proc SharedFlowNode_getNodeSubmits { exp_path node datestamp } {
   tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} submits
}

proc SharedFlowNode_getWorkUnit { exp_path node datestamp } {
   tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} work_unit
}

# adds a loop to the current container
# it is an ordered list of full loop nodes path
proc SharedFlowNode_addLoop { exp_path node datestamp new_loop } {

   set currentList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} loops]
   if { ${currentList} != "" && [lsearch ${currentList} ${new_loop}] != -1 } {
      return
   }

   tsv::keylset SharedFlowNode_${exp_path}_${datestamp} ${node} loops [linsert ${currentList} 0 ${new_loop}]
}

proc SharedFlowNode_getLoops { exp_path node datestamp } {
   # puts "SharedFlowNode_getLoops exp_path:${exp_path} node:${node} datestamp:${datestamp}"
   tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} loops
}

proc SharedFlowNode_hasLoops { exp_path node datestamp } {
   set loopList [SharedFlowNode_getLoops ${exp_path} ${node} ${datestamp}]
   if { [llength $loopList] > 0 } {
      return 1
   }
   return 0
}

proc SharedFlowNode_getSubmits { exp_path node datestamp } {
   tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} submits
}

proc SharedFlowNode_getSubmitPosition { exp_path node datestamp } {
   set submitter [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} submitter]
   set returnValue 0
   if { ${submitter} != "" } {
      set submits [SharedFlowNode_getSubmits ${exp_path} ${submitter} ${datestamp}]
      if { [expr [llength ${submits}] > 1] } {
         set nodeName [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} name]
         set returnValue [lsearch ${submits} ${nodeName}]
         if { [expr ${returnValue} == -1] } {
            set returnValue 0
         }
      }
   }

   return ${returnValue}
}

# get the submit node at position x, the first submission is at position 0
proc SharedFlowNode_getSubmitAtPosition { exp_path node datestamp {position end} } {

   set child ""
   catch {
      set currentList [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} submits]
      set child [lindex ${currentList} ${position}]
   }
   return ${child}
}

# takes the flow node as input and returns the sequencer node as output
proc SharedFlowNode_getSequencerNode { exp_path node datestamp } {
   set containerNode [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} container]
   set nodeLeaf [file tail ${node}]
   if {  $containerNode != "" } {
      set realNode $containerNode/$nodeLeaf
   } else {
      set realNode /$nodeLeaf
   }
   return $realNode
}

# search the _node tree down to find which node submits the given node
# If the submitter node is not the _node itself, it will only
# go down nodes that are of type task_node or npt nodes... because you cannot
# submit a node that belongs to another container than your own.
# _node is full path of the node to begin search on i.e. /exp_root/my_container
# _submitted_node is the xml node name of the submitted node
proc SharedFlowNode_searchSubmitNode { exp_path node datestamp submitted_node } {
   set currentList [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} submits]
   set value ""
   if { ${currentList} != "" } {
      if { [lsearch ${currentList} ${submitted_node}] != -1 } {
         set value ${node}
         set foundNode ${node}
      } else {
         foreach childName ${currentList} {
            set childSubmitNode ${node}/${childName}
	    ::log::log debug "SharedFlowNode_searchSubmitNode submitted_node:${submitted_node} childSubmitNode:${childSubmitNode}"
	    if { [SharedFlowNode_isNodeExist ${exp_path} ${childSubmitNode} ${datestamp}] == true } {
               set childeSubmitNodeType [SharedFlowNode_getNodeType ${exp_path} ${childSubmitNode} ${datestamp}]
               if { ${childeSubmitNodeType} == "task" || ${childeSubmitNodeType} == "npass_task" } {
                  set value [SharedFlowNode_searchSubmitNode ${exp_path} ${node}/${childName} ${datestamp} ${submitted_node}]
                  if { ${value} != "" } {
                     set foundNode ${node}/${childName}
                     break
                  }
               }
            } else {
	       # the node does not exists if we have not parsed the definition of the node yet 
	       # (the parsing of the submit might have been done though)
	       ::log::log debug "SharedFlowNode_searchSubmitNode submitted_node:${submitted_node} bypassing childSubmitNode:${childSubmitNode}"
	    }
         }
      }
   }
   return ${value}
}

# search the node uptree & returns the path of the node that
# is of type task
# returns empty string if not found
proc SharedFlowNode_searchForTask { exp_path flow_node datestamp } {
   set value ""
   if { $flow_node != "" } {
      if { [SharedFlowNode_getGenericAttribute ${exp_path} ${flow_node} ${datestamp} type] == "task" } {
         set value $flow_node
      } else {
         set value [SharedFlowNode_searchForTask ${exp_path} [SharedFlowNode_getGenericAttribute ${exp_path} ${flow_node} ${datestamp} submitter] ${datestamp}]
      }
   }

   return $value
}

# search uptree for submitter indexed containers (loop and switching nodes) and add it to the
# current node
proc SharedFlowNode_searchSubmitLoops { exp_path node datestamp src_node } {
   if { $node != "" } {
      set nodeType [SharedFlowNode_getNodeType  ${exp_path} ${node} ${datestamp}]
      if { ${nodeType} == "loop" || ${nodeType} == "switch_case" } {
         SharedFlowNode_addLoop ${exp_path} ${src_node} ${datestamp} ${node}
      }
      SharedFlowNode_searchSubmitLoops ${exp_path} [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} submitter] ${datestamp} $src_node
   }
}

proc SharedFlowNode_findNodes { exp_path node datestamp search_value match_case results_output } {
   upvar #0 ${results_output} myOutput

   set matchCaseFlag "-nocase"

   if { ${match_case} == 1 } { set matchCaseFlag "" }
   if { [eval string match ${matchCaseFlag} \"*${search_value}*\" [file tail ${node}]] == 1 } {
      lappend myOutput ${node}
   }

   foreach submitName [SharedFlowNode_getSubmits ${exp_path} ${node} ${datestamp}] {
      SharedFlowNode_findNodes ${exp_path} ${node}/${submitName} ${datestamp} ${search_value} ${match_case} ${results_output}
   }
}

# returns a list of all extensions belonging to the
# current loop node
proc SharedFlowNode_getLoopExtensions { exp_path node datestamp } {
   # puts SharedFlowNode_getLoopExtensions ${exp_path} ${node} ${datestamp}
   set extensions {}
   switch [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} loop_type]] {
      loopset -
      default {
         set seq_node [SharedFlowNode_getSequencerNode $exp_path $node $datestamp]
         # set tmpExpression [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} expression]
         if { [TsvInfo_haskey ${exp_path} $seq_node ${datestamp} loop.expression] } {
            set tmpExpression [TsvInfo_getNodeInfo ${exp_path} ${seq_node} ${datestamp} loop.expression]
            set slowArray [split $tmpExpression ","]
            set firstFlag 1
            set lastCount -1
            foreach slowEl $slowArray {
               set fastArray [split $slowEl ":"]
               set count [lindex $fastArray 0]
               if { $firstFlag == 0 && $count == $lastCount } {
                  set count [expr $count + [lindex $fastArray 2]]
               }
               while { $count <= [lindex $fastArray 1] } {
                  lappend extensions $count
                  set lastCount $count
                  set count [expr $count + [lindex $fastArray 2]]
               }
               set firstFlag 0
            }
         } else {
            # set start [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} start]
            # set step [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} step]
            # set setValue [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} setValue]
            # set end [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} end]
            set start [TsvInfo_getNodeInfo ${exp_path} ${seq_node} ${datestamp} loop.start]
            set step [TsvInfo_getNodeInfo ${exp_path} ${seq_node} ${datestamp} loop.step]
            set setValue [TsvInfo_getNodeInfo ${exp_path} ${seq_node} ${datestamp} loop.set]
            set end [TsvInfo_getNodeInfo ${exp_path} ${seq_node} ${datestamp} loop.end]
            set count $start
            while { [expr $count <= $end] } {
               lappend extensions $count
               set count [expr $count + $step]
            }
         }
      }
   }

   return $extensions
}

# get parent loop extension
proc SharedFlowNode_getParentLoopExt { exp_path node datestamp } {
   set parentExt ""
   set count 0
   set isLatest 0
   set loopList [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} loops]

   foreach loopNode $loopList {
      set currentExt [SharedFlowNode_getCurrentExt ${exp_path} ${node} ${datestamp}]
      
      if { ${loopNode} == ${node} } {
         break
      }
      if { $currentExt == "latest" } {
         set parentExt latest
      } else {
         if { $count == 0 } {
            set parentExt "${currentExt}"
         } else {
            set parentExt "${parentExt}${currentExt}"
         }
      }
      incr count
   }
   return ${parentExt}
}

# verifies if the flow.xml of each module has changed compared to the last time
# the module was loaded. Returns true if the flow has been modified,
# otherwise returns false
proc SharedFlowNode_isFlowModified { exp_path datestamp } {
   set modules [SharedData_getExpModules ${exp_path} ${datestamp}]
   set isModified false
   foreach module ${modules} {
      set moduleName [SharedFlowNode_getName ${exp_path} ${module} ${datestamp}]
      set loadTime [SharedFlowNode_getGenericAttribute ${exp_path} ${module} ${datestamp} load_time]
      set flowFile ${exp_path}/modules/${moduleName}/flow.xml
      set flowModTime [file mtime ${flowFile}]
      if { ${loadTime} != "" && ${flowModTime} > ${loadTime} } {
         set isModified true
         ::log::log notice "SharedFlowNode_isFlowModified ${exp_path} ${module} ${datestamp} ${flowFile} has been modified"
         break
      }
   }
   return ${isModified}
}

# loop_args = "outer_Loop=2,inner_Loop=3"
# returns +2+3 if node exists
#
# returns "" on errors
proc SharedFlowNode_getLoopExtFromLoopArgs { exp_path node datestamp loop_args } {
   if { [SharedFlowNode_isNodeExist ${exp_path} ${node} ${datestamp}] == false } {
      puts stderr "ERROR: retrieving loop... node ${node} does not exists!"
      return ""
   }

   set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]

   # get parent loop containers
   set loops [SharedFlowNode_getLoops ${exp_path} ${node} ${datestamp}]

   # remove = sign and comma from arg values.. out of this
   # I get a list of [loop_one value_one loop_two value_two]
   set splittedLoopArgs [join [split [split ${loop_args} = ] , ]]

   # validate loop arg values
   set count 0
   foreach splittedLoopArg ${splittedLoopArgs} {
      # the loop names is at odd indexes
      if { [expr ${count} % 2] == 1 } {
         # even position, go to next
         incr count
      } else {
         set found false
	 # validate the argument loop is found in the list of parent loops
         foreach loopNode ${loops} {
            if { [file tail ${loopNode}] == ${splittedLoopArg} } {
	       set found true
	    }
         }

         # check if argument belongs to nptask
         if { ${found} == false && ${nodeType} == "npass_task" && [file tail ${node}] == ${splittedLoopArg} } {
	    set found true
	 }

         # if not found, outputs an error and return
         if { ${found} == false } {
            puts stderr "ERROR: Invalid loop argument: ${splittedLoopArg}"
	    return ""
         }

         incr count
      }
   }

   # get the iterations in order in case the loop arguments are in the wrong loop order
   set loopExt ""
   foreach loopNode ${loops} {
      set foundIndex [lsearch ${splittedLoopArgs} [file tail ${loopNode}]]
      if { ${foundIndex} != -1 } {
         set loopExt ${loopExt}+[lindex ${splittedLoopArgs} [expr $foundIndex + 1]]
      }
   }
   if { ${nodeType} == "npass_task" } {
      set foundIndex [lsearch ${splittedLoopArgs} [file tail ${node}]]
      if { ${foundIndex} != -1 } {
         set loopExt ${loopExt}+[lindex ${splittedLoopArgs} [expr $foundIndex + 1]]
      }
   }

   return ${loopExt}
}

################################################################################################3
#
# The part here relates to runtime status for nodes running within a datestamp value
# The info stored includes whether the node is collapsed or not, the display coordinates,
# the current status of the node, the time for each status, etc
#
################################################################################################3

# clears all the runtime data and display infos for all nodes
# NOT USED NOW TO BE CLEANED 
proc SharedFlowNode_clearAllNodes { exp_path datestamp } {
   catch { tsv::unset SharedFlowNode_${exp_path}_${datestamp}_runtime }
}

# tsv gui_runtime array is used to store display attributes needed by xflow
#
# display_infos: this is a list that contains the following for each node
#    element 0: collapse values: 0=user uncollapsed, 1=user collapsed, 2=default
#    element 1: is root node flag: 1=node is exp root node
#    element 2-7: node display coords (3 x,y points) x1 y1 x2 y2 x3 y3
#    element 8: display Y value
# 
# current: for node with iterations, this holds the value of the current iteration selected by the user; it defaults to latest
# latest:  for node with iterations, this holds the value of the latest iteration that was updated; used to display when user selects latest as iteration
#
# ext_max_value: holds the value of the largest iteration (in terms of nof characters) for a node; used to set the field length of the widget
#
proc SharedFlowNode_initNodeDatestampDisplay {  exp_path node datestamp } {
   if { [tsv::names SharedFlowNode_${exp_path}_${datestamp}_gui_runtime] == "" || [tsv::keylget  SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node}] == ""} {
      tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} display_infos [list 2 0 0 0 0 0 0 0 40]

      SharedFlowNode_setLatestExt ${exp_path} ${node} ${datestamp} ""
      SharedFlowNode_setCurrentExt ${exp_path} ${node} ${datestamp} latest

      set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]
      if { ${nodeType} == "npass_task" || ${nodeType} == "loop" } {
         SharedFlowNode_setMaxExtValue  ${exp_path} ${node} ${datestamp} 5
      }

      if { ${nodeType} == "switch_case" && 
        [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} switching_type] == "datestamp_hour" && ${datestamp} != "" } {
         SharedFlowNode_setCurrentExt ${exp_path} ${node} ${datestamp} +[Utils_getHourFromDatestamp ${datestamp}]
      }
   
      if { ${nodeType} == "switch_case" && 
        [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} switching_type] == "day_of_week" && ${datestamp} != "" } {
         SharedFlowNode_setCurrentExt ${exp_path} ${node} ${datestamp} +[Utils_getDayOfWeekFromDatestamp ${datestamp}]
      }
   }
}

proc SharedFlowNode_initNodeDatestamp { exp_path node datestamp {force false} } {

    SharedFlowNode_initNodeDatestampDisplay ${exp_path} ${node} ${datestamp} 

   # delete all member keys
   if { [tsv::exists SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == 1 } {
      foreach key [tsv::keylkeys SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] {
         tsv::keyldel SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} ${key}
      }
   }

   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses {}

   # puts "SharedFlowNode_initNodeDatestamp done" 
}

proc SharedFlowNode_resetAllStatus { exp_path node datestamp {is_recursive 0} } {
   SharedFlowNode_initNodeDatestamp ${exp_path} ${node} ${datestamp}
   if { ${is_recursive} } {
      set submits [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} submits]
      if { ${submits} != "" } {
         foreach submitName ${submits} {
            set submitNode ${node}/${submitName}
            SharedFlowNode_resetAllStatus  ${exp_path} ${submitNode} ${datestamp} 1
         }
      }
   }
}

# returns the current iteration/index/extension selected by the user
# for a loop or npass_task node
proc SharedFlowNode_getCurrentExt { exp_path node datestamp } {
   set value ""
   if { [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node}] != "" } {
      if { [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} current dummy_var] != 0 } {
         set value [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} current]
      }
   }
   return ${value}
}

# sets the current iteration for the loop or npass_task node
# the value must be in the format +${iteration_value} i.e. +1 or +1+000000018
proc SharedFlowNode_setCurrentExt { exp_path node datestamp value } {
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} current ${value}
}

# returns the latest iteration that was modified
# The return value is in the form of the setCurrentExt format
# The is mainly used to know what iteration value to display when the user
# has selected the "latest" iteration i.e. view the latest modified iteration
proc SharedFlowNode_getLatestExt { exp_path node datestamp } {
   set value ""
   if { [tsv::keylget  SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node}] != "" } {
      set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]

      if { ${nodeType} == "npass_task" } {
         set parentExt [SharedFlowNode_getParentLoopExt ${exp_path} ${node} ${datestamp}]
	 if { ${parentExt} != "" && ${parentExt} != "latest" } {
	      set latestMemberKey latest_member_${parentExt}
              if { [SharedFlowNode_isGuiRuntimeKeyExist ${exp_path} ${node} ${datestamp} ${latestMemberKey}] == true }  {
	         set value [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} ${latestMemberKey}]
	      }
	 } else {
            if { [ catch { set value [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} latest_member] } ] } {
	       SharedFlowNode_setLatestExt ${exp_path} ${node} ${datestamp} ""
               # tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} latest_member "" 
            } 
	 }
      } else {
         if { [ catch { set value [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} latest_member] } ] } { 
	    SharedFlowNode_setLatestExt ${exp_path} ${node} ${datestamp} ""
            # tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} latest_member "" 
         }

      }
   }
   return ${value}
}

proc SharedFlowNode_setLatestExt { exp_path node datestamp value {latest_member_key latest_member} } {
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} ${latest_member_key} ${value}
}

proc SharedFlowNode_isRuntimeKeyExist {  exp_path node datestamp key } {
   set found false
   catch {
      if { [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} ${key} dummy_var] != 0 } {
         set found true
      }
   }
   return ${found}
}

proc SharedFlowNode_isGuiRuntimeKeyExist {  exp_path node datestamp key } {
   set found false
   catch {
      if { [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} ${key} dummy_var] != 0 } {
         set found true
      }
   }
   return ${found}
}

# returns the max extension value for a node that contains extensions or indexes
# such as a loop node or an npass_task node. This is mainly used for display purpose
# in xflow
proc SharedFlowNode_getMaxExtValue { exp_path node datestamp } {
   if { [SharedFlowNode_isGuiRuntimeKeyExist ${exp_path} ${node} ${datestamp} max_ext_value] == true }  {
      set value [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} max_ext_value]
   } else {
      set value 5
   }
   return ${value}
}

# see getMaxExtValue
proc SharedFlowNode_setMaxExtValue { exp_path node datestamp max_ext_value } {
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} max_ext_value ${max_ext_value}
}

proc SharedFlowNode_getMemberStatusMsg { exp_path node datestamp member } {
   set value "init"

   if { [tsv::exists SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == 1 } {
      set values {init}
      if { $member == "" } {
         set member "null"
      }
      # get the latest member 
      if { $member == "latest" } {
         # set member [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} latest_member]
         set member [SharedFlowNode_getLatestExt ${exp_path} ${node} ${datestamp}]
      }
      catch {
         array set statuses [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses]
         if { [info exists statuses($member)] } {
            set values $statuses($member)
         }
      }
      # set value [lindex ${values} 2]
      set value [lindex ${values} 2]
   }

   return $value
}

# retrieves the status for a given member iteration
# This is a generic procedure that is used even for node that are not part of
# loops... In that case the member value is simply an empty string
# For nodes that are part of loops or npass_task nodes, the member can either be the
# member value i.e. +1 or +00000036 or the value "latest".
proc SharedFlowNode_getMemberStatus { exp_path node datestamp member } {
   set value "init"

      # puts "tsv::exists SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}? [tsv::exists SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}]"
   if { [tsv::exists SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == 1 } {
      set values {init}
      # puts "tsv::keylkeys SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}? [tsv::keylkeys SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}]"
      if { $member == "" } {
         set member "null"
      }
      # get the latest member 
      if { $member == "latest" } {
         # set member [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} latest_member]
         set member [SharedFlowNode_getLatestExt ${exp_path} ${node} ${datestamp}]
      }
      catch {
         array set statuses [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses]
         if { [info exists statuses($member)] } {
            set values $statuses($member)
         }
      }
      set value [lindex ${values} 0]
   }

   return $value
}

# sets the status of a node. Generic procedure used for all type of nodes
# called by LogReader
# difference between status orig_status:
# status=end, begin
# orig_status=end or endx, begin or beginx
proc SharedFlowNode_setMemberStatus { exp_path node datestamp member status orig_status timestamp {status_msg ""} {is_recursive false} } {
   if { [tsv::names SharedFlowNode_${exp_path}_${datestamp}_runtime] == "" || [tsv::keylget  SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == ""} {
      # puts "SharedFlowNode_setMemberStatus SharedFlowNode_initNodeDatestamp"
      SharedFlowNode_initNodeDatestamp ${exp_path} ${node} ${datestamp}
   }

   set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]
   if { ${nodeType} == "npass_task" || ${nodeType} == "loop" } {
      set currentMax [SharedFlowNode_getMaxExtValue ${exp_path} ${node} ${datestamp}]
      set newMax [string length [lindex [split ${member} +] end ] ]
      if { ${newMax} > ${currentMax} } {
         SharedFlowNode_setMaxExtValue  ${exp_path} ${node} ${datestamp} ${newMax}
      }
   }

   if { ${nodeType} == "npass_task"} {
      SharedFlowNode_setNptMemberStatus ${exp_path} ${node} ${datestamp} ${member} ${status} ${timestamp} ${status_msg}
   } else {

      array set statuses [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses]

      if { $member == "" } {
         set member null
	    if { ${status_msg} == "" } {
               set statuses($member) "${status} ${timestamp}"
	    } else {
               set statuses($member) "${status} ${timestamp} [list ${status_msg}]"
	    }
      } else {
         if { ${status} == "init" } {
            if { [info exists statuses($member)] } {
               # reset the exact member match
               unset statuses($member)
            }
            # reset all members that are part of the same iteration
            set resetList [array get statuses ${member}+*]
            foreach {item value} ${resetList} {
               unset statuses($item)
            }
         } else {
	    if { ${status_msg} == "" } {
               set statuses($member) "${status} ${timestamp}"
	    } else {
               set statuses($member) "${status} ${timestamp} [list ${status_msg}]"
	    }
	    if { ${nodeType} == "loop"} {
	       # for loops, the latest_member stores the value of the whole loop.
	       # for inn   # how many parent loops do I have
               set nofParentLoops [llength [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} loops]]
               # how many index separator do I have from the given member
               set nofSeparators [expr [llength [split ${member} +]] - 1]

               if { ${nofParentLoops} > 1 && [expr ${nofParentLoops} - 1] == ${nofSeparators} } {
                 #  tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} latest_member $member
	          SharedFlowNode_setLatestExt ${exp_path} ${node} ${datestamp} ${member}
               }
	    } else {
               # tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} latest_member $member
	       SharedFlowNode_setLatestExt ${exp_path} ${node} ${datestamp} ${member}
	    }
         }
      }
      set values [array get statuses]
      tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses "${values}"
   }

   SharedFlowNode_setStatInfo ${exp_path} ${node} ${datestamp} ${member} ${orig_status} ${timestamp}

   if { ${is_recursive} } {
      set submits [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} submits]
      if { ${submits} != "" } {
         foreach submitName ${submits} {
            set submitNode ${node}/${submitName}
            SharedFlowNode_setMemberStatus ${exp_path} ${submitNode} ${datestamp} ${member} ${status} ${orig_status} ${timestamp} ${status_msg} 1
         }
      }
   }
}

# add to statistic info list... calculation of exec time
proc SharedFlowNode_setStatInfo { exp_path node datestamp member stat_key timestamp } {
   array set statsinfo {}
   ::log::log debug "SharedFlowNode_setStatInfo node:$node stat_key:$stat_key timestamp:$timestamp"

   # replace endx/beginx/abortx by end/begin/abort
   set stat_key [SharedData_getRippleStatusMap ${stat_key} false]

   catch { array set statsinfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_stats ${node} stats] }

   if { ${stat_key} != "submit" && [info exists statsinfo($member)] } {
         set memberInfoList $statsinfo($member)
         set foundIndex [lsearch ${memberInfoList} ${stat_key}]

         if { ${foundIndex} == -1 } {
            # status is new, store the new status
            lappend memberInfoList ${stat_key} ${timestamp}
         } else {
            # update status with new info
	    switch ${stat_key} {
	       begin {
	          # delete any abort or end status
	          set abortIndexes [ lreverse [lsearch -all ${memberInfoList} abort]]
	          # puts "node:$node member:$member abortIndexes:$abortIndexes"
	          foreach deleteIndex ${abortIndexes} {
	             set memberInfoList [lreplace  ${memberInfoList} ${deleteIndex} [expr ${deleteIndex} +1]]
	          }
	          set endIndexes [lreverse [lsearch -all ${memberInfoList} end]]
	          # puts "node:$node member:$member endIndexes:$endIndexes"
	          foreach deleteIndex ${endIndexes} {
	             set memberInfoList [lreplace  ${memberInfoList} ${deleteIndex} [expr ${deleteIndex} +1]]
	          }
                  # recalculate index
                  set foundIndex [lsearch ${memberInfoList} ${stat_key}]
	       }
	       default {
	       }
	    }
            set memberInfoList [lreplace ${memberInfoList} ${foundIndex} [expr ${foundIndex} + 1] ${stat_key} ${timestamp}]
         }
         set statsinfo($member) ${memberInfoList}
         # puts "node:$node member:$member memberInfoList:$memberInfoList"
   } else {
      # puts "SharedFlowNode_setStatInfo node:$node member:$member initialising..."
      # initialise status
      array set statsinfo {}
      set statsinfo($member) [list ${stat_key} ${timestamp}]
   }
   ::log::log debug "SharedFlowNode_setStatInfo node:$node [array get statsinfo]"
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_stats ${node} stats "[array get statsinfo]"
}

proc SharedFlowNode_getExecTime { exp_path node datestamp member } {
   # puts "SharedFlowNode_getExecTime exp_path:$exp_path node:$node datestamp:$datestamp member:$member"
   if { ${member} == "" } {
      set member null
   }
   set execTime ""
   set timestampFormat {%Y%m%d.%H:%M:%S}
   set timeDisplayFormat {%H:%M:%S}
   set beginStatus begin
   set endStatus end

   if { [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${member}] == "end" } {
      array set statsinfo {}
      catch { array set statsinfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_stats ${node} stats] }

      if { [info exists statsinfo($member)] } {
         # if the exectime exists already, use it, else calculate it
         set memberInfoList $statsinfo($member)
         set execTimeIndex [lsearch -exact ${memberInfoList} exectime]
	 if { ${execTimeIndex} != -1 } {
	    # found the exectime
            set execTime [lindex ${memberInfoList} [expr ${execTimeIndex} + 1]]
	 } else {
	    # calculate the exec time
            set beginIndex [lsearch -exact ${memberInfoList} ${beginStatus}]
            set endIndex [lsearch -exact ${memberInfoList} ${endStatus}]
	    if { ${beginIndex} != -1 && ${endIndex} != -1 } {
	       set beginTime [lindex ${memberInfoList} [expr ${beginIndex} + 1]]
	       set endTime [lindex ${memberInfoList} [expr ${endIndex} + 1]]
	       set execTimeString [expr [clock scan ${endTime} -format ${timestampFormat}] -  [clock scan ${beginTime} -format ${timestampFormat}] ]
	       set execTime [clock format ${execTimeString} -timezone :UTC -format ${timeDisplayFormat}]
	    }
	    # store the calculated time
	    # lappend memberInfoList exectime ${execTime}
	    # set statsinfo($member) ${memberInfoList}
            # tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_stats ${node} stats "[array get statsinfo]"
	 }
      }
   }
   return ${execTime}
}

proc SharedFlowNode_getMiscAvgTime { exp_path node datestamp member type } {
   if { ${member} == "" } {
      set member null
   }
   set miscTime ""
   array set avg {}
   catch { array set avg [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_stats ${node} avg] }
   if { [info exists avg($member)] } {
      set memberAvgList $avg($member)
      set miscTimeIndex [lsearch -exact ${memberAvgList} $type]
      set miscTime [lindex ${memberAvgList} [expr ${miscTimeIndex} + 1]]
   }
   return ${miscTime}
}

proc SharedFlowNode_getRelativeExecTime { exp_path node datestamp member } {
   if { ${member} == "" } {
      set member null
   }
   if { [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_stats ${node} avg {}] == 0 } {
      return ""
   }
   set relativeExecTime ""
   set timeDisplayFormat {%H:%M:%S}
   set execTime [SharedFlowNode_getExecTime $exp_path $node $datestamp $member]
   set avgExecTime [SharedFlowNode_getMiscAvgTime $exp_path $node $datestamp $member exectime]

   if { $execTime != "" && $avgExecTime != "" } {
      if { [clock scan ${execTime} -format ${timeDisplayFormat}] > [clock scan ${avgExecTime} -format ${timeDisplayFormat}] } {
         set relativeExecTimeString [expr [clock scan ${execTime} -format ${timeDisplayFormat}] -  [clock scan ${avgExecTime} -format ${timeDisplayFormat}] ]
         set relativeExecTime +[clock format ${relativeExecTimeString} -timezone :UTC -format ${timeDisplayFormat}]
      } elseif { [clock scan ${execTime} -format ${timeDisplayFormat}] < [clock scan ${avgExecTime} -format ${timeDisplayFormat}] } {
         set relativeExecTimeString [expr [clock scan ${avgExecTime} -format ${timeDisplayFormat}] - [clock scan ${execTime} -format ${timeDisplayFormat}] ]
         set relativeExecTime -[clock format ${relativeExecTimeString} -timezone :UTC -format ${timeDisplayFormat}]
      } else {
         set relativeExecTime "00:00:00"
      }
   }
   return $relativeExecTime
}

proc SharedFlowNode_isStatsInfoExists {  exp_path node datestamp } {
   set isExists false
   catch {
      set keys [tsv::keylkeys SharedFlowNode_${exp_path}_${datestamp}_stats ${node}]
      if { [lsearch ${keys} stats] != -1 } {
         set isExists true
      }
   }
   return ${isExists}
}

proc SharedFlowNode_getBeginTime { exp_path node datestamp member } {
   if { ${member} == "" } {
      set member null
   }
   set beginTime ""
   set timestampFormat {%Y%m%d.%H:%M:%S}
   set timeDisplayFormat {%H:%M:%S}
   set beginStatus begin

   set currentStatus [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${member}]
   if { ${currentStatus} == "submit" || ${currentStatus} == "init" || ${currentStatus} == "wait" || ${currentStatus} == "discret" } {
	return ""
   }

   array set statsinfo {}
   catch { array set statsinfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_stats ${node} stats] }
   if { [info exists statsinfo($member)] } {
      set memberInfoList $statsinfo($member)
      set beginIndex [lsearch -exact ${memberInfoList} ${beginStatus}]
      if { ${beginIndex} != -1 } {
	 set beginTimeValue [lindex ${memberInfoList} [expr ${beginIndex} + 1]]
	 set beginTimeString [clock scan ${beginTimeValue} -format ${timestampFormat}]
         set beginTime [clock format ${beginTimeString} -format ${timeDisplayFormat}]
      }
   }

   return ${beginTime}
}

proc SharedFlowNode_getEndTime { exp_path node datestamp member } {
   if { ${member} == "" } {
      set member null
   }
   set endTime ""
   set timestampFormat {%Y%m%d.%H:%M:%S}
   set timeDisplayFormat {%H:%M:%S}

   if { [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${member}] == "end" } {
      array set statsinfo {}
      catch { array set statsinfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_stats ${node} stats] }
      if { [info exists statsinfo($member)] } {
         set memberInfoList $statsinfo($member)
         set endIndex [lsearch -exact ${memberInfoList} end]
	 if { ${endIndex} != -1 } {
	    set endTimeValue [lindex ${memberInfoList} [expr ${endIndex} + 1]]
	    set endTimeString [clock scan ${endTimeValue} -format ${timestampFormat}]
	    set endTime [clock format ${endTimeString} -format ${timeDisplayFormat}]
	 }
      }
   }
   return ${endTime}
}

proc SharedFlowNode_getSubmitDelay { exp_path node datestamp member } {
   if { ${member} == "" } {
      set member null
   }
   set submitDelay ""
   set timestampFormat {%Y%m%d.%H:%M:%S}
   set timeDisplayFormat {%H:%M:%S}
   set submitStatus submit
   set beginStatus begin

   set currentStatus [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${member}]
   if { ${currentStatus} == "submit" || ${currentStatus} == "init" || ${currentStatus} == "wait" || ${currentStatus} == "discret" } {
	return ""
   }

   array set statsinfo {}
   catch { array set statsinfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_stats ${node} stats] }
   if { [info exists statsinfo($member)] } {
      # if the submitdelay exists already, use it, else calculate it
      set memberInfoList $statsinfo($member)
      set submitDelayIndex [lsearch -exact ${memberInfoList} submitdelay]
      if { ${submitDelayIndex} != -1 } {
         set submitDelayIndex [lsearch -exact ${memberInfoList} submitdelay]
         set submitDelay [lindex ${memberInfoList} [expr ${submitDelayIndex} + 1]]
      } else {
	 # calculate
         set beginIndex [lsearch -exact ${memberInfoList} ${beginStatus}]
         set submitIndex [lsearch -exact ${memberInfoList} ${submitStatus}]
	 if { ${beginIndex} != -1 && ${submitIndex} != -1 } {
	    set submitTime [lindex ${memberInfoList} [expr ${submitIndex} + 1]]
	    set beginTime [lindex ${memberInfoList} [expr ${beginIndex} + 1]]
	    set delayTimeString [expr [clock scan ${beginTime} -format ${timestampFormat}] -  [clock scan ${submitTime} -format ${timestampFormat}] ]
	    set submitDelay [clock format ${delayTimeString} -format ${timeDisplayFormat}]
	 } 
      }
   }
   return ${submitDelay}
}

proc SharedFlowNode_getDeltaFromStart { exp_path node datestamp member } {
   if { ${member} == "" } {
      set member null
   }
   set deltaFromStart ""
   set timeDisplayFormat {%H:%M:%S}
   set timeStoredFormat {%Y%m%d.%H:%M:%S}
   set submitStatus submit
   set endStatus end

   if { [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${member}] == "end" } {

      # info from root node since the info is relative to the root node
      set rootNode [SharedData_getExpRootNode ${exp_path} ${datestamp}]
      set rootNodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${rootNode} ${datestamp} type]
      set rootNodeMember null
      if { ${rootNodeType} == "loop" } {
         set rootNodeMember all
      }
      array set rootnode_stats {}
      catch { array set rootnode_stats [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_stats ${rootNode} stats] }
      if { [array size rootnode_stats] == 0 || ! [info exists rootnode_stats($rootNodeMember)] } {
         ::log::log debug "SharedFlowNode_getDeltaFromStart ${exp_path} $node $member $datestamp : cannot retrieve rootnode=${rootNode} stats"
         return ""
      }
      array set statsinfo {}
      catch { array set statsinfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_stats ${node} stats] }
      if { [info exists statsinfo($member)] } { 
         set memberInfoList $statsinfo($member)
         set deltaFromStartIndex [lsearch -exact ${memberInfoList} deltafromstart]
         if { ${deltaFromStartIndex} != -1 } {
            set deltaFromStart [lindex ${memberInfoList} [expr ${deltaFromStartIndex} + 1]]
	 } else {
	    # calculate it
            set endIndex [lsearch -exact ${memberInfoList} ${endStatus}]
            set rootNodeInfoList $rootnode_stats($rootNodeMember)
            set submitIndex [lsearch -exact ${rootNodeInfoList} ${submitStatus}]
            if { ${endIndex} != -1 && ${submitIndex} != -1 } {
               set endTime [lindex ${memberInfoList} [expr ${endIndex} + 1]]
               set rootSubmitTime [lindex ${rootNodeInfoList} [expr ${submitIndex} + 1]]
               set deltaFromStartString [expr [clock scan ${endTime} -format ${timeStoredFormat}] -  [clock scan ${rootSubmitTime} -format ${timeStoredFormat}] ]
	       set deltaFromStart [clock format ${deltaFromStartString} -timezone :UTC -format ${timeDisplayFormat}]
            }
	 }
      }
   }
   return ${deltaFromStart}
}

#relative progress --> average time from submit of root node to end of target node
proc SharedFlowNode_getRelativeProgress { exp_path node datestamp member } {
   if { ${member} == "" } {
      set member null
   }
   if { [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_stats ${node} avg {}] == 0 } {
      return ""
   }
   set relativeProgress ""
   set timeDisplayFormat {%H:%M:%S}
   set progress [SharedFlowNode_getDeltaFromStart $exp_path $node $datestamp $member]
   set avgProgress [SharedFlowNode_getMiscAvgTime $exp_path $node $datestamp $member deltafromstart]

   if { $progress != "" && $avgProgress != "" } {
      set ref_level1 [SharedData_getTimingProgressLevel1 ${exp_path}]
      set ref_level2 [SharedData_getTimingProgressLevel2 ${exp_path}]
      set ref_lev1_min [Utils_getMinuteFromTime $ref_level1]
      set ref_lev2_min [Utils_getMinuteFromTime $ref_level2]
      ::log::log debug "SharedFlowNode_getRelativeProgress exp_path:$exp_path node:$node datestamp:$datestamp ref_lev1_min:$ref_lev1_min ref_lev2_min:$ref_lev2_min"

      set relativeProgress [list 0 "min" "normal"]

      set progressClockValue [clock scan ${progress} -format ${timeDisplayFormat}] 
      set avgProgressClockValue [clock scan ${avgProgress} -format ${timeDisplayFormat}] 
      # any difference less than 60 seconds is considered normal
      if { ${progressClockValue} > ${avgProgressClockValue} && [expr ${progressClockValue} - ${avgProgressClockValue}] >= 60 } {
         set relativeProgressString [expr ${progressClockValue} - ${avgProgressClockValue}]
         set tm_minute [ expr [scan [clock format ${relativeProgressString} -format %M] %d] + 60 * [clock format ${relativeProgressString} -format %k]]
	 ::log::log debug "SharedFlowNode_getRelativeProgress exp_path:$exp_path node:$node datestamp:$datestamp tm_minute:$tm_minute"
         if { ${tm_minute} >= ${ref_lev1_min} && ${tm_minute} < ${ref_lev2_min}} {
            set relativeProgress [list +${tm_minute} "min" "orange"]
         } elseif { ${tm_minute} >= ${ref_lev2_min}} {
            set relativeProgress [list +${tm_minute} "min" "red"]
         } else {
            set relativeProgress [list +${tm_minute} "min" "normal"]
         }
      } elseif { ${progressClockValue} < ${avgProgressClockValue} &&  [expr ${avgProgressClockValue} - ${progressClockValue}] >= 60 } {
         set relativeProgressString [expr ${avgProgressClockValue} - ${progressClockValue}]
         set tm_minute [ expr [scan [clock format ${relativeProgressString} -format %M] %d] + 60 * [clock format ${relativeProgressString} -format %k]]
         set relativeProgress [list -${tm_minute} "min" "normal"]
      }
   }
   return $relativeProgress
}

# If time_a is older than time_b return 1, else return 0
proc SharedFlowNode_isTimestampOlder { time_a time_b } {
   set tmp_time_a [split $time_a {}]
   set tmp_time_b [split $time_b {}]
   set i 0
   set max_field [llength $tmp_time_a]
   while {$i < $max_field} {
      if {[lindex $tmp_time_a $i] != "." && [lindex $tmp_time_a $i] != ":"} {
         if {[lindex $tmp_time_a $i] > [lindex $tmp_time_b $i]} {
            return 1
         } elseif {[lindex $tmp_time_a $i] < [lindex $tmp_time_b $i]} {
            return 0
         }
      }
      incr i
   }
   return 0
}

proc SharedFlowNode_setNptMemberStatus { exp_path node datestamp member status timestamp {status_msg ""}} {
   ::log::log debug "SharedFlowNode_setNptMemberStatus ${exp_path} $node $member $status"
   if { [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type] != "npass_task" } {
      return
   }

   if { [tsv::keylkeys SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == "" } {
      tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses {}
   }

   array set statuses [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses]

   # how many parent loops do I have
   set nofParentLoops [llength [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} loops]]
   # how many index separator do I have from the given member
   set nofSeparators [expr [llength [split ${member} +]] - 1]

   set parentLoopExt [SharedFlowNode_getParentLoopExt ${exp_path} ${node} ${datestamp}]

   if { ${nofParentLoops} != "" } {
      if { ${nofSeparators} == ${nofParentLoops} && ${status} == "init" } {
         # whole loop iteration
         # need to init all indexes in the npt that matches
         foreach { stored_member status } [array get statuses] {
            if { [string match ${member}+* ${stored_member}] } {
               # removing is same as init... less data
               unset statuses($stored_member)
            }
         }
         catch { unset statuses($member) }
         # reset the latest reference if needed
         set latestMember [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} statuses]

         if { [string match ${member}+* ${latestMember}] } {
            # tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} latest_member ""
	    SharedFlowNode_setLatestExt ${exp_path} ${node} ${datestamp} ""
         }

         set baseExt [SharedFlowNode_getExtBasePart ${member}]
	 set latestMemberKey latest_member_${baseExt}
         if { [SharedFlowNode_isRuntimeKeyExist ${exp_path} ${node} ${datestamp} ${latestMemberKey}] == true }  {
	    # tsv::keyldel SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} ${latestMemberKey}
            SharedFlowNode_setLatestExt ${exp_path} ${node} ${datestamp} ${member} ${latestMemberKey}
	 }

      } elseif { [expr ${nofSeparators} > ${nofParentLoops}] } {
         # changing one npt index only
         if { ${status_msg} == "" } {
            set statuses($member) "${status} ${timestamp}"
         } else {
            set statuses($member) "${status} ${timestamp} [list ${status_msg}]"
         }
         set baseExt [SharedFlowNode_getExtBasePart ${member}]
         # tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} latest_member $member
         SharedFlowNode_setLatestExt ${exp_path} ${node} ${datestamp} ${member}
	 if { ${baseExt} != "" } {
	    set latestMemberKey latest_member_${baseExt}
            # tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} ${latestMemberKey} $member
            SharedFlowNode_setLatestExt ${exp_path} ${node} ${datestamp} ${member} ${latestMemberKey}
	 }
      } elseif { [expr ${nofSeparators} < ${nofParentLoops}] } {
         # not for myself
         return
      }
   } else {
      # changing one npt member not part of a loop
      if { ${status_msg} == "" } {
         set statuses($member) "${status} ${timestamp}"
      } else {
         set statuses($member) "${status} ${timestamp} [list ${status_msg}]"
      }
      # tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} latest_member $member
      SharedFlowNode_setLatestExt ${exp_path} ${node} ${datestamp} ${member}
   }
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses "[array get statuses]"
}

# returns the list of extensions application for the npass_task_node
# the npass_task may have a list of many values but they might not
# all be visible if the task is running within a loop...
# for instance if the user selects a loop index then only the npass_task values
# that start with that index is relevant
proc SharedFlowNode_getNptExtensions { exp_path node datestamp } {
   set extensions {}
   set loopList [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} loops]
   set loopExt ""
   set isAllLatest true
   set returnedExtensions {}

   if { [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses dummy_var] != 0 } {

      array set statuses [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses]
      set extensions [array names statuses]
      foreach ext ${extensions} {
         lappend returnedExtensions [string range ${ext} [expr [string last + ${ext}] + 1]  end]
      }
      set returnedExtensions [lsort -unique ${returnedExtensions}]
   }
   return ${returnedExtensions}
}



################################################################################################3
# The part here relates to display information for nodes in xflow running within a datestamp value
################################################################################################3
proc SharedFlowNode_isCollapsed { exp_path node datestamp } {
   set value 0
   if { [tsv::exists SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node}] == 1 } {
      catch {
         set displayInfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} display_infos]
         set value [lindex $displayInfo 0]
      }
   }

   return $value
}

proc SharedFlowNode_isParentCollapsed { exp_path node datestamp } {
   # puts "SharedFlowNode_isParentCollapsed exp:${exp_path} node:${node} datestamp:${datestamp} "
   if { [tsv::exists SharedFlowNode_${exp_path}_${datestamp}_runtime ${node}] == 0 } {
      return 0
   }

   set submitter [SharedFlowNode_getSubmitter ${exp_path} ${node} ${datestamp} ]
   set value [SharedFlowNode_isCollapsed ${exp_path} ${submitter} ${datestamp}]
   return ${value}
}

proc SharedFlowNode_setCollapsed { exp_path node datestamp value } {
   if { [tsv::exists SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node}] == 1 } {
      set displayInfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} display_infos]
      set displayInfo [lreplace $displayInfo 0 0 $value]
      tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} display_infos ${displayInfo}

      set submits [SharedFlowNode_getSubmits ${exp_path} ${node} ${datestamp}]
      foreach submitName ${submits} {
         set submitNode ${node}/${submitName}
         SharedFlowNode_setCollapsed ${exp_path} ${submitNode} ${datestamp} ${value}
      }
   }
}

# if the current node is collapsed,
# searches up the submit parent chain to look for first parent that is collapsed,
# and then sets the collapse value to 0 from the found parent down to every submit child
# returns the first parent found 
# else returns empty string
proc SharedFlowNode_uncollapseBranch { exp_path node datestamp } {
   if { [SharedFlowNode_isCollapsed ${exp_path} ${node} ${datestamp} ] == 0 ||  [SharedFlowNode_isCollapsed ${exp_path} ${node} ${datestamp} ] == 2} {
      return ""
   }

   set previousNode ${node}
   set nextNode [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} submitter]
   set found false
   set value 0
   while { ${nextNode} != "" && ${found} == false } {
      set displayInfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${nextNode} display_infos]
      set value [lindex $displayInfo 0]
      if { $value == 0 || $value == 2 } {
         set found true ; break
      }
      set previousNode ${nextNode}
      set nextNode [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${nextNode} submitter]
   }
   SharedFlowNode_setCollapsed ${exp_path} ${previousNode} ${datestamp} 0
   return ${previousNode}
}

proc SharedFlowNode_uncollapseAll { exp_path node datestamp } {
   SharedFlowNode_setCollapsed  ${exp_path} ${node} ${datestamp} 0
}

# values must be a list of {x1 y1 x2 y2 max_x max_y}
proc SharedFlowNode_setDisplayCoords { exp_path node datestamp values } {
      SharedFlowNode_initNodeDatestampDisplay ${exp_path} ${node} ${datestamp} 
   set displayInfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} display_infos]
   set displayInfo [join [lreplace $displayInfo 2 7 $values]]

   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} display_infos ${displayInfo}
}

proc SharedFlowNode_setDisplayY { exp_path node datestamp value } {
      SharedFlowNode_initNodeDatestampDisplay ${exp_path} ${node} ${datestamp} 
   # set value for current node to be used by children node
   set displayInfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} display_infos]
   set displayInfo [lreplace $displayInfo 8 8 ${value}]

   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} display_infos ${displayInfo}
}

proc SharedFlowNode_getDisplayY { exp_path node datestamp } {

   set displayInfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} display_infos]
   return [lindex ${displayInfo} 8]
}

proc SharedFlowNode_getDisplayCoords { exp_path node datestamp } {
   set displayInfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} display_infos]
   return [lrange $displayInfo 2 7]
}

proc  SharedFlowNode_setIsRootNode { exp_path node datestamp value} {
      SharedFlowNode_initNodeDatestampDisplay ${exp_path} ${node} ${datestamp} 
   set displayInfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} display_infos]
   set displayInfo [lreplace $displayInfo 1 1 $value]

   tsv::keylset SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} display_infos ${displayInfo}
}

proc  SharedFlowNode_isRootNode { exp_path node datestamp } {
   set displayInfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} display_infos]
   set value [lindex $displayInfo 1]
   return $value
}

proc SharedFlowNode_resetNodeStatus { exp_path node datestamp } {
   SharedFlowNode_resetAllStatus ${exp_path} ${node} ${datestamp}
   set submits [SharedFlowNode_getSubmits ${exp_path} ${node} ${datestamp}]
   foreach submitName ${submits} {
      set submitNode ${node}/${submitName}
      SharedFlowNode_resetNodeStatus ${exp_path} ${submitNode} ${datestamp}
   }
}

# returns the extension of the current node based
# on parent loops
proc SharedFlowNode_getNodeExtension { exp_path node datestamp } {
   set extension ""
   set loopList [SharedFlowNode_getLoops ${exp_path} ${node} ${datestamp}]
   set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]
   if { ${nodeType} == "npass_task" } {
      # current index selection for the nptask
      set nptExtension [SharedFlowNode_getCurrentExt ${exp_path} ${node} ${datestamp}]
      set parentLoopExt [SharedFlowNode_getParentLoopExt ${exp_path} ${node} ${datestamp}]
      if { ${parentLoopExt} == "latest" || ${nptExtension} == "latest" } {
         # get latest if any of selection is latest
         set extension [SharedFlowNode_getLatestExt ${exp_path} ${node} ${datestamp}]
      } else {
         # get npt extension corresponding to loop extension
         set extension ${parentLoopExt}${nptExtension}
      }
   } else {
      if { ${nodeType} == "loop" && [llength ${loopList}] == 1 && [SharedFlowNode_getCurrentExt ${exp_path} ${node} ${datestamp}] == "latest" } {
         # exception case for top loop
         return "all"
      } else {
         foreach loopNode ${loopList} {
            set currentExt [SharedFlowNode_getCurrentExt ${exp_path} ${loopNode} ${datestamp}]
            if { ${currentExt} == "latest" } {
               return [SharedFlowNode_getLatestExt ${exp_path} ${node} ${datestamp}]
            }
            set extension "${extension}[SharedFlowNode_getCurrentExt ${exp_path} ${loopNode} ${datestamp}]"
         }
      }
   }
   return ${extension}
}

# returns the extension text that should be displayed
proc SharedFlowNode_getExtDisplay { exp_path node datestamp loop_ext } {
   set displayValue ""
   set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]
   if { ${nodeType} == "loop" || ${nodeType} == "npass_task"} {
      if { $loop_ext == "all" || $loop_ext == "latest" } {
         return ""
      }
   }

   if { $loop_ext != "" } {
      if { $loop_ext != "latest" } {
         set displayValue "\[$loop_ext\]"
         # replace the first _ by [
         set displayValue [string replace $loop_ext 0 0 \[]
         # add ] at the end
         set displayValue "${displayValue}]"
         # replace any _ by ][
         set displayValue [string map {_ \]\[} $displayValue]
      } else {
         set displayValue "\[\]"
      }
   }

   return $displayValue
}

proc SharedFlowNode_getParentLoopExt {exp_path node datestamp} {
   set parentExt ""
   set count 0
   set isLatest 0
   set loopList [SharedFlowNode_getLoops ${exp_path} ${node} ${datestamp}]

   foreach loopNode $loopList {
      set currentExt [SharedFlowNode_getCurrentExt ${exp_path} ${loopNode} ${datestamp}]
      if { ${loopNode} == ${node} } {
         break
      }
      if { ${currentExt} == "latest" } {
         set parentExt latest
      } else {
         if { $count == 0 } {
            set parentExt "${currentExt}"
         } else {
            set parentExt "${parentExt}${currentExt}"
         }
      }
      incr count
   }
   return ${parentExt}
}

proc SharedFlowNode_getIndexValue { value } {
   set returnValue $value
   if { [string first "+" $value] == 0 } {
      catch { set returnValue [string range $value 1 end] }
   }
   return $returnValue
}

# input: /a/b/c+12+1 or /a/b/c.+12+1
# output: /a/b/c
proc SharedFlowNode_getNodeFromDisplayFormat { node_with_ext } {
   set newNodeName ${node_with_ext}
   set firstSepIndex [string first "+" ${node_with_ext}]
   if { [expr ${firstSepIndex} != -1] } {
      set newNodeName [string range ${node_with_ext} 0 [expr ${firstSepIndex} - 1]]
   }
   set newNodeName [string trim ${newNodeName} .]
   return ${newNodeName}
}

# returns +123 from node+123
# return "" if no index
proc SharedFlowNode_getExtFromDisplayFormat { node_with_ext } {
   set extValue ""
   set firstSepIndex [string first "+" ${node_with_ext}]
   if { [expr ${firstSepIndex} != -1] } {
      set extValue [string range ${node_with_ext} ${firstSepIndex} end]
   }
   return ${extValue}
}

proc SharedFlowNode_getLoopTooltip { exp_path loop_node datestamp } {
   set tooltipTxt ""
   if { [SharedFlowNode_getGenericAttribute ${exp_path} ${loop_node} ${datestamp} type] == "loop" } {
         set seq_node [SharedFlowNode_getSequencerNode $exp_path $loop_node $datestamp]
      if { [TsvInfo_haskey ${exp_path} $seq_node ${datestamp} loop.expression] } {
         set tmpExpression [TsvInfo_getNodeInfo ${exp_path} ${seq_node} ${datestamp} loop.expression]
         #set tmpExpression [SharedFlowNode_getGenericAttribute ${exp_path} ${loop_node} ${datestamp} expression]
         set nodeCount 0
         set defCount 1
         set expArray [split $tmpExpression ",:"]
         foreach defNode $expArray {
            switch $nodeCount {
               0 {
                  append tooltipTxt "${defCount}) start=${defNode},"
                  incr nodeCount
               }
               1 {
                  append tooltipTxt "end=${defNode},"
                  incr nodeCount
               }
               2 {
                  append tooltipTxt "step=${defNode},"
                  incr nodeCount
               }
               3 {
                  append tooltipTxt "set=${defNode}\n"
                  set nodeCount 0
                  incr defCount
               }
            }
         }
      } else {
         # set start [SharedFlowNode_getGenericAttribute ${exp_path} ${loop_node} ${datestamp} start]
         # set step [SharedFlowNode_getGenericAttribute ${exp_path} ${loop_node} ${datestamp} step]
         # set setValue [SharedFlowNode_getGenericAttribute ${exp_path} ${loop_node} ${datestamp} set]
         # set end [SharedFlowNode_getGenericAttribute ${exp_path} ${loop_node} ${datestamp} end]
         set start [TsvInfo_getNodeInfo ${exp_path} ${seq_node} ${datestamp} loop.start]
         set step [TsvInfo_getNodeInfo ${exp_path} ${seq_node} ${datestamp} loop.step]
         set setValue [TsvInfo_getNodeInfo ${exp_path} ${seq_node} ${datestamp} loop.set]
         set end [TsvInfo_getNodeInfo ${exp_path} ${seq_node} ${datestamp} loop.end]
         set tooltipTxt "\[start=${start},end=${end},step=${step},set=${setValue}\]"
      }
   }
   return ${tooltipTxt}
}

# returns the node extension that should be used
# for listings
# user should have chosen an extension or all
# loops should be "latest"
proc SharedFlowNode_getListingNodeExtension { exp_path current_node datestamp {full_loop "0"} } {
   set extension ""
   set count 0
   set latestCount 0
   set loopList [SharedFlowNode_getLoops ${exp_path} ${current_node} ${datestamp}]
   set numberOfLoops [llength $loopList]
   if { [SharedFlowNode_getNodeType ${exp_path} ${current_node} ${datestamp}] == "npass_task" } {
      set currentNptExt [SharedFlowNode_getCurrentExt ${exp_path} ${current_node} ${datestamp}]
      set extension ${currentNptExt}

      if { ${loopList} != "" } {
         set parentLoopExt [SharedFlowNode_getParentLoopExt ${exp_path} ${current_node} ${datestamp}]
         if { ${parentLoopExt} == "latest" || ${currentNptExt} == "latest" } {
            set extension [SharedFlowNode_getLatestExt ${exp_path} ${current_node} ${datestamp}]
	 } else {
            set extension ${parentLoopExt}${currentNptExt}
         }
      } else {
         if { ${currentNptExt} == "latest" } {
            set extension [SharedFlowNode_getLatestExt ${exp_path} ${current_node} ${datestamp}]
         }
      }
   } else {
      foreach loopNode $loopList {
         incr count
         set currentExt [SharedFlowNode_getCurrentExt ${exp_path} ${loopNode} ${datestamp}]
         # this part is only for loop nodes
         if { ${full_loop} == "1" && $count == $numberOfLoops } {
            set currentExt ""
         }
         if { $currentExt == "latest" } {
            incr latestCount
            set latestExt [SharedFlowNode_getLatestExt ${exp_path} ${loopNode} ${datestamp}]
            if { $latestExt == "all" } {
               set currentExt ""
            } else {
               set currentExt $latestExt
            }
         }
         # the all extension is used for loop nodes to store
         # the status of the loop node as a whole
         set extension "${extension}${currentExt}"
      }

      if { $latestCount != 0 } {
         # user is on latest mode, get the latest for the current node
         set extension [SharedFlowNode_getLatestExt ${exp_path} ${current_node} ${datestamp}]
         if { $extension == "all" } {
            set extension ""
         }
      }
   }
   return $extension
}

# returns the input arguments as expected by the
# sequencer for loop arguments
# it builds the loop arguments for all loops
# contained in the node loops attribute
# 
# exts sample: +2+4 for outer_loop index +2 and inner loop index +4
proc SharedFlowNode_getLoopArgs { exp_path node datestamp exts} {
   # puts "SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp} ${exts}"
   set args ""
   set count 0
   set loopList [SharedFlowNode_getLoops ${exp_path} ${node} ${datestamp}]
   if { ${exts} != "" } {
      set exts [split ${exts} +]
      set exts [lrange ${exts} 1 end]
   }
   if { [llength $loopList] > 0 } {
      foreach loopNode $loopList {
         if { ${exts} == "" } {
	    # retrieve from xflow selection
            set currentExt [SharedFlowNode_getCurrentExt ${exp_path} ${loopNode} ${datestamp}]
	 } else {
	    # get from given list
            set currentExt [lindex ${exts} ${count}]
	 }
         if { ${currentExt} == "latest" } {
            return ""
	 } elseif { ${currentExt} != "" } {
            # remove the + sign before extension
            set currentExt [string trim ${currentExt} +]
            set nodeName [SharedFlowNode_getName ${exp_path} ${loopNode} ${datestamp}]
            if { $count == 0 } {
               set args "-l ${nodeName}=${currentExt}"
            } else {
               set args "${args},${nodeName}=${currentExt}"
            }
         }
         incr count
      }
   }
   return $args
}

# npass_index argument is used when user is provided manual
# the index value at submission time
proc SharedFlowNode_getNptArgs { exp_path node datestamp {loop_index ""} {npass_index ""} } {
   # puts "SharedFlowNode_getNptArgs exp_path:$exp_path node:$node datestamp:$datestamp loop_index:$loop_index npass_index:$npass_index"
   set args ""

   # parentLoopArgs if not empty already contains -l
   set parentLoopArgs [SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp} ${loop_index}]
   set latestExt [SharedFlowNode_getLatestExt ${exp_path} ${node} ${datestamp}]
   set latestExt [SharedFlowNode_getExtLeafPart ${latestExt}]

   set nodeName [SharedFlowNode_getName ${exp_path} ${node} ${datestamp}]

   if { ${parentLoopArgs} != "" } {
      # there are arguments for parent loops
      set parentLoopArgs "${parentLoopArgs}"
   } elseif { [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
      # means parent loops has latest selected
      # build from the the latest
      set fullExt [SharedFlowNode_getLatestExt ${exp_path} ${node} ${datestamp}]
      if { ${fullExt} != "" } {
         # build the args and return
         set args "[SharedFlowNode_getLoopArgs ${exp_path} ${node} ${datestamp} ${fullExt}],${nodeName}=${latestExt}"
	 return ${args}
      }
   }

   if { ${npass_index} != "" } {
      set trimmedNpassIndex [SharedFlowNode_getExtLeafPart ${npass_index}]
      # if npass_index is passed use it...
      if { ${npass_index} == "latest" } {
         if { ${latestExt} == "" } {
	    # no index for current npt
	    set args ${parentLoopArgs}
         } else {
	    if { ${parentLoopArgs} != "" } {
	       set args "${parentLoopArgs},${nodeName}=${latestExt}"
	    } else {
	       set args "-l ${nodeName}=${latestExt}"
	    }
         }
      } else {
         # means user has provided it manually
	 if { ${parentLoopArgs} != "" } {
            set args "${parentLoopArgs},${nodeName}=${trimmedNpassIndex}"
	 } else {
	    set args "-l ${nodeName}=${trimmedNpassIndex}"
	 }
      }
   } else {
      set currentExt [SharedFlowNode_getCurrentExt ${exp_path} ${node} ${datestamp}]
      if { ${currentExt} == "latest" } {
         if { ${latestExt} == "" } {
	    # no index for current npt
	    set args ${parentLoopArgs}
         } else {
	    if { ${parentLoopArgs} != "" } {
	       set args "${parentLoopArgs},${nodeName}=${latestExt}"
	    } else {
	       set args "-l ${nodeName}=${latestExt}"
	    }
         }
      } else {
         # remove the + sign before extension
         set currentExt [SharedFlowNode_getExtLeafPart ${currentExt}]
	 if { ${parentLoopArgs} != "" } {
            set args "${parentLoopArgs},${nodeName}=${currentExt}"
	 } else {
	    set args "-l ${nodeName}=${currentExt}"
	 }
      }
   }

   return $args
}

proc SharedFlowNode_getParentLoopArgs { exp_path node datestamp } {
   set args ""
   set count 0
   set isLatest 0
   set loopList [SharedFlowNode_getLoops ${exp_path} ${node} ${datestamp}]

   if { [llength $loopList] > 1 } {
      foreach loopNode $loopList {
         set currentExt [SharedFlowNode_getCurrentExt ${exp_path} ${loopNode} ${datestamp}]
         if { $node != $loopNode && ${currentExt} == "latest" } {
            set args "-1"
            return $args
         } else {
            # remove the + sign before extension
            if { $node == ${loopNode} } {
               break
            }
            set currentExt [string range ${currentExt} 1 end]
            set nodeName [SharedFlowNode_getName ${exp_path} ${loopNode} ${datestamp}]
            if { $count == 0 } {
               set args "-l ${nodeName}=${currentExt}"
            } else {
               set args "${args},${nodeName}=${currentExt}"
            }
         }
         incr count
      }
   }
   return $args
}

# input +2+3 returns +2
# input +2+3+4 returns +2+3
# input +2 returns ""
proc SharedFlowNode_getExtBasePart { value } {
   set returnVal ""
   switch [llength [split ${value} +]] {
      0 -
      2 {
         set returnVal ""
      }

      default {
         set returnVal [string range ${value} 0 [expr [string last + ${value}] - 1]]
      }
   }

   return ${returnVal}
}

# input +2+3 returns 3
# input +2 returns 2
# input "" return ""
proc SharedFlowNode_getExtLeafPart { value } {
   set returnVal ""
   set splittedValue [split ${value} +]
   set returnVal [lindex ${splittedValue} end]
   return ${returnVal}
}

# this function is used to know whether we should redisplay
# a node branch when an update to a node is detected from
# the exp log file. To minimize the number of updates done
# at the gui level, only changes that affects the visibility
# of nodes are being redrawned. For instance, if you are viewing a loop iteration
# of 1 and updates are on another iteration, the data is updated but the gui is not
proc SharedFlowNode_isRefreshNeeded { exp_path flow_node datestamp current_ext } {
   ::log::log debug "SharedFlowNode_isRefreshNeeded $exp_path $flow_node $datestamp current_ext:$current_ext"
   set refreshNeeded true
   set nodeType [SharedFlowNode_getNodeType ${exp_path} ${flow_node} ${datestamp}]
   if { [SharedFlowNode_getLoops ${exp_path} ${flow_node} ${datestamp}] != "" } {
      # if the current is either a loop node or part of a loop container,
      # I will only call a redraw on the flow if current update affects the display
      set parentLoopExt [SharedFlowNode_getParentLoopExt ${exp_path} ${flow_node} ${datestamp}]
      # nodeExt is the value of the current loop and any parent loop
      set nodeExt [SharedFlowNode_getNodeExtension ${exp_path} ${flow_node} ${datestamp}]

      switch ${nodeType} {
         loop {
            # current is the value of current loop listbox selection
            set currentLoopSelection [SharedFlowNode_getCurrentExt ${exp_path} ${flow_node} ${datestamp}]
            if { ${parentLoopExt} == "" || ${parentLoopExt} != "latest" } {
               if { ${currentLoopSelection} != "latest" && ${nodeExt} != ${current_ext} } {
                  # we don't refresh the current update if the user is currently viewing
                  # a specific iteration and the update is not on that iteration
                  set refreshNeeded false
               }
            }
	 }
         npass_task {
            # current is the value of current listbox selection
            set currentIterationSelection [SharedFlowNode_getCurrentExt ${exp_path} ${flow_node} ${datestamp}]
            if { ${parentLoopExt} != "latest" && ${currentIterationSelection} == "latest" } {
	       # parent loop is latest, so only update if npt iteration belongs to parent loop
	       if { [string first ${parentLoopExt} ${current_ext}] != 0 } {
                  set refreshNeeded false
	       }
	    } elseif { ${parentLoopExt} == "" || ${parentLoopExt} != "latest" } {
               if { ${currentIterationSelection} != "latest" && ${nodeExt} != ${current_ext} } {
                  # we don't refresh the current update if the user is currently viewing
                  # a specific iteration and the update is not on that iteration
                  set refreshNeeded false
               }
            }
	 }
         default {
            # non indexed nodes part of a loop container
            if { ${parentLoopExt} != "latest" && ${nodeExt} != ${current_ext} } {
               set refreshNeeded false
            }
         }
      }
   }
   ::log::log debug "SharedFlowNode_isRefreshNeeded $flow_node ${current_ext} refreshed? ${refreshNeeded}"
   return ${refreshNeeded}
}

# change from node+123 to node[123]
proc SharedFlowNode_convertToDisplayFormat { node_with_ext } {
   set firstSepIndex [string first "+" ${node_with_ext}]
   set newNodeName ${node_with_ext}
   if { [expr ${firstSepIndex} != -1] } {
      set newNodeName [string replace ${node_with_ext} ${firstSepIndex} ${firstSepIndex} "\["]
      set newNodeName "${newNodeName}\]"
   }
   return ${newNodeName}
}

# change node[123] back to node+123
proc SharedFlowNode_convertFromDisplayFormat { node_with_ext } {
   set lastSepIndex [string last "\]" ${node_with_ext}]
   set firstSepIndex [string first "\[" ${node_with_ext}]
   set newNodeName ${node_with_ext}
   if { [expr ${lastSepIndex} != -1] } {
      set newNodeName [string range ${node_with_ext} 0 end-1]
      if { [expr ${firstSepIndex} != -1] } {
         set newNodeName [string replace ${newNodeName} ${firstSepIndex} ${firstSepIndex} "+"]
      }
   }
   return ${newNodeName}
}

proc SharedFlowNode_setSwitchingType { exp_path node datestamp switching_type } {
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp} ${node} switching_type ${switching_type}
}

proc SharedFlowNode_setSwitchingItem { exp_path node datestamp switching_item } {
   tsv::keylset SharedFlowNode_${exp_path}_${datestamp} ${node} switching_item ${switching_item}
}

proc SharedFlowNode_getSwitchingExtensions { exp_path node datestamp } {
   set extensions {}
   set dummy_var ""
   if { [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} switching_item dummy_var] != 0 } {
      lappend extensions ${dummy_var}
   }
   return ${extensions}
}

proc SharedFlowNode_getSwitchingInfo { exp_path node datestamp } {
   set value ""
   if { [SharedFlowNode_getNodeType  ${exp_path} ${node} ${datestamp}] == "switch_case" } {
      set switchType [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} switching_type]
      switch ${switchType} {
         datestamp_hour {
	    set hour [Utils_getHourFromDatestamp ${datestamp}]
	    # set value "\[dshour-${hour}\]"
	    set value "\[dshour]"
         }
         day_of_week {
	    # set value "\[dshour-${hour}\]"
	    set value "\[dow]"
	 }
	 default {
	 }
      }
   }
   return ${value}
}

proc SharedFlowNode_printNode { exp_path node datestamp {print_child false} } {
   puts "---------------------------------------------------------"
   puts "node:${node}"
   puts "---------------------------------------------------------"
   foreach key [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node}] {
      puts "   ${key}:[tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} ${key}]"
   }
   if { ${datestamp} != "" } {
      SharedFlowNode_printNodeStatus ${exp_path} ${node} ${datestamp}
   }

   if { ${print_child} == true } {
      foreach child [tsv::keylget SharedFlowNode_${exp_path}_${datestamp} ${node} submits] {
         SharedFlowNode_printNode ${exp_path} ${node}/${child} ${datestamp} ${print_child}
      }
   }
}

proc SharedFlowNode_printNodeStatus  { exp_path node datestamp} {
   puts "   @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@"
   if { [tsv::keylget  SharedFlowNode_${exp_path}_${datestamp} ${node}] != "" } {
      set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]
      array set statuses [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses]
      foreach { member status } [array get statuses] {
         puts "   member:${member} status:${status}"
      }
      if { ${nodeType} == "npass_task" || ${nodeType} == "loop" } {
         puts "   max_ext_value:[tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} max_ext_value]"
         puts "   current:[tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_gui_runtime ${node} current]"
         # puts "   latest:[tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} latest_member]"
      }
      if { [SharedFlowNode_hasLoops ${exp_path} ${node} ${datestamp}] } {
         # puts "   latest:[tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} latest_member]"
      }
   }
}

proc SharedFlowNode_printNodeMembers { exp_path node datestamp } {
   if { [tsv::keylget  SharedFlowNode_${exp_path}_${datestamp} ${node}] != "" } {
      set nodeType [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} type]
      array set statuses [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_runtime ${node} statuses]
      array set statsinfo [tsv::keylget SharedFlowNode_${exp_path}_${datestamp}_stats ${node} stats]
      if { [SharedFlowNode_getLoops ${exp_path} ${node} ${datestamp}] != "" } {
         foreach { member } [lsort -integer [array names statuses]] {
            puts "   member:${member} status:$statuses($member) stats_info:$statsinfo($member)"
         }
      } else {
         foreach { member status } [array get statuses] {
            puts "   status:${status}"
         }
      }
   }
}
