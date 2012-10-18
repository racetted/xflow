package require Thread

# This is a generic to store data for a specific experiment in
# a shared memory structure... This data can be retrieved from
# all threads within the application i.e. overview thread, msg center and experiment threads
#

# exp_path is the full path of the experiment i.e. SEQ_EXP_HOME
# key is the key for the specific value
proc SharedData_setExpData { exp_path key value } {
   if { [tsv::names ${exp_path}] == "" } {
      # does not exists... create it
      set initValues [list ${key} ${value}]
      tsv::array set ${exp_path} ${initValues}
   } else {
      array set values [tsv::array get ${exp_path}]
      set values(${key}) ${value}
      tsv::array set ${exp_path} [array get values]
   }
}

# retrieve experiment data based on the exp_path and the key
proc SharedData_getExpData { exp_path key } {
   set returnedValue ""
   if { [tsv::exists ${exp_path} ${key}] } {
      array set values [tsv::array get ${exp_path} ${key}]      
      set returnedValue $values(${key})
   }
   return ${returnedValue}
}

# removes experiment data based on the exp_path and the key
proc SharedData_unsetExpData { exp_path key } {
   if { [tsv::exists ${exp_path} ${key}] } {
      array set values [tsv::array get ${exp_path}]
      array unset values ${key}
      tsv::array reset ${exp_path} [array get values]
   }
}

# retrieves the experiment thread id
# There is usually a thread associated with an experiment and a datestamp in the
# following cases:
# 1) The flow is currently viewed by the user
# 2) The flow is currently active (log file modified within the last hour)
# 3) The flow is being read at application startup
proc SharedData_getExpThreadId { _exp_path _datestamp } {
   set threadId ""
   catch {
      set threadId [SharedData_getExpData ${_exp_path} ${_datestamp}_thread_id]
   }
   return ${threadId}
}

# removes the thread id associated with the experiment datestamp
proc SharedData_removeExpThreadId { _exp_path _datestamp } {
   SharedData_unsetExpData ${_exp_path} ${_datestamp}_thread_id
}

# sets the thread id associated with the experiment datestamp
proc SharedData_setExpThreadId { _exp_path _datestamp  _thread_id } {
   SharedData_setExpData ${_exp_path} ${_datestamp}_thread_id ${_thread_id}
}

# sets the log file offset associated with the experiment datestamp
# the offset is used by the LogReader to know where to read the log file between
# reads.
proc SharedData_setExpDatestampOffset { exp_path datestamp {offset 0} } {
   SharedData_setExpData ${exp_path} ${datestamp}_offset ${offset}
}

# retrieves the log file offset associated with the experiment datestamp
proc SharedData_getExpDatestampOffset { _exp_path _datestamp } {
   set offset 0
   catch {
      set offset [SharedData_getExpData ${_exp_path} ${_datestamp}_offset]
   }
   return ${offset}
}

proc SharedData_removeExpDatestampOffset { exp_path datestamp {offset 0} } {
   SharedData_unsetExpData ${exp_path} ${datestamp}_offset
}

proc SharedData_setExpOverviewUpdateAfterId { _exp_path _datestamp _afterid } {
   SharedData_setExpData ${_exp_path} ${_datestamp}_update_afterid ${_afterid}
}

proc SharedData_getExpOverviewUpdateAfterId { _exp_path _datestamp } {
   SharedData_getExpData ${_exp_path} ${_datestamp}_update_afterid
}

proc SharedData_setExpGroupDisplay { _exp_path _groupDisplay } {
   SharedData_setExpData ${_exp_path} groupdisplay ${_groupDisplay}
}

proc SharedData_setExpRootNode { _exp_path _datestamp _rootNode } {
   SharedData_setExpData ${_exp_path} ${_datestamp}_rootnode ${_rootNode}
}

proc SharedData_getExpRootNode { _exp_path _datestamp } {
   set rootNode [SharedData_getExpData ${_exp_path} ${_datestamp}_rootnode]
   return ${rootNode}
}

proc SharedData_setExpStartupDone { _exp_path _datestamp _startupDone } {
   SharedData_setExpData ${_exp_path} ${_datestamp}_startup ${_startupDone}
}

proc SharedData_getExpStartupDone { _exp_path _datestamp } {
   SharedData_getExpData ${_exp_path} ${_datestamp}_startup
}

proc SharedData_getExpGroupDisplay { _exp_path } {
   set groupDisplay [SharedData_getExpData ${_exp_path} groupdisplay]
   return ${groupDisplay}
}

proc SharedData_setExpDisplayName { _exp_path _displayName } {
   SharedData_setExpData ${_exp_path} displayname ${_displayName}
}

proc SharedData_getExpDisplayName { _exp_path } {
   set displayName [SharedData_getExpData ${_exp_path} displayname]
   return ${displayName}
}

proc SharedData_setExpTimings { _exp_path _timings } {
   SharedData_setExpData ${_exp_path} ref_timings ${_timings}
}

proc SharedData_getExpTimings { _exp_path } {
   set timings [SharedData_getExpData ${_exp_path} ref_timings]
   return ${timings}
}

proc SharedData_setExpSupportInfo { _exp_path _supportInfo } {
   SharedData_setExpData ${_exp_path} supportinfo ${_supportInfo}
}

proc SharedData_getExpSupportInfo { _exp_path } {
   set info [SharedData_getExpData ${_exp_path} supportinfo]
   return ${info}
}

proc SharedData_setExpShortName { _exp_path _shortName } {
   SharedData_setExpData ${_exp_path} shortname ${_shortName}
}

proc SharedData_getExpShortName { _exp_path } {
   set info [SharedData_getExpData ${_exp_path} shortname]
   return ${info}
}

proc SharedData_setExpModules { _exp_path _datestamp _modules } {
   SharedData_setExpData ${_exp_path} ${_datestamp}_modules ${_modules}
}

proc SharedData_addExpModule { _exp_path _datestamp _module } {
   set modules [SharedData_getExpData ${_exp_path} ${_datestamp} modules]
   if { [lsearch ${modules} ${_module}] == -1 } {
      lappend modules ${_module}
      SharedData_setExpModules ${_exp_path} ${_datestamp} ${modules}
   }
}

proc SharedData_getExpModules { _exp_path _datestamp } {
   set modules [SharedData_getExpData ${_exp_path} ${_datestamp}_modules]
   return ${modules}
}

proc SharedData_setExpUpdatedNodes { _exp_path _datestamp _nodeList } {
   SharedData_setExpData ${_exp_path} ${_datestamp}_updated_nodes ${_nodeList}
}

proc SharedData_getExpUpdatedNodes { _exp_path _datestamp} {
   set nodeList [SharedData_getExpData ${_exp_path} ${_datestamp}_updated_nodes]
   return ${nodeList}
}

proc SharedData_addExpNodeMapping { _exp_path _datestamp _real_node _flow_node } {
   # puts "SharedData_addExpNodeMapping exp_path:${_exp_path} datestamp:${_datestamp} real_node;${_real_node} flow_node:${_flow_node}"
   array set nodeMappings [SharedData_getExpData ${_exp_path} ${_datestamp}_node_mappings]
   set nodeMappings(${_real_node}) ${_flow_node}
   SharedData_setExpData ${_exp_path} ${_datestamp}_node_mappings [array get nodeMappings]
}

proc SharedData_getExpNodeMapping { _exp_path _datestamp _real_node } {
   # puts "SharedData_getExpNodeMapping exp_path:${_exp_path} datestamp:${_datestamp} real_node;${_real_node}"
   set flowNode ${_real_node}
   array set nodeMapping [SharedData_getExpData ${_exp_path} ${_datestamp}_node_mappings]
   if { [info exists nodeMapping(${_real_node})] } {
      set flowNode $nodeMapping(${_real_node})
   }
   # puts "SharedData_getExpNodeMapping exp_path:${_exp_path} datestamp:${_datestamp} real_node;${_real_node} flowNode:${flowNode}"
   return ${flowNode}
}

proc SharedData_resetExpDisplayData { _exp_path _canvas } {
   array set canvasList [SharedData_getExpData ${_exp_path} canvases]

   if { [info exists canvasList(${_canvas})] } {
      set canvasList(${_canvas}) [list 40 "/[file tail ${_exp_path}]" 40 40]
      SharedData_setExpData ${_exp_path} canvases [array get canvasList]
   }
}

proc SharedData_initExpDisplayData { _exp_path _canvas } {
   array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   if { ! [info exists canvasList(${_canvas})] } {
      set canvasList(${_canvas}) [list 40 "/[file tail ${_exp_path}]" 40 40]
      SharedData_setExpData ${_exp_path} canvases [array get canvasList]
   }
}

proc SharedData_setExpDisplayData { _exp_path _canvas next_y max_x max_y } {
   array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   if { ! [info exists canvasList(${_canvas})] } {
      SharedData_initExpDisplayData ${_exp_path} ${_canvas}
      array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   }

   set canvasInfo $canvasList(${_canvas})

   if { [expr ${next_y} > [lindex $canvasInfo 0]] } {
      set canvasInfo [lreplace $canvasInfo 0 0 $next_y]
   }

   if { [expr ${max_x} > [lindex $canvasInfo 2]] } {
      set canvasInfo [lreplace $canvasInfo 2 2 $max_x]
   }

   if { [expr ${max_y} > [lindex $canvasInfo 3]] } {
      set canvasInfo [lreplace $canvasInfo 3 3 $max_y]
   }

   set canvasList(${_canvas}) ${canvasInfo}
   SharedData_setExpData ${_exp_path} canvases [array get canvasList]
}

proc SharedData_setExpDisplayNextY { _exp_path _canvas _value } {
   array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   if { ! [info exists canvasList(${_canvas})] } {
      SharedData_initExpDisplayData ${_exp_path} ${_canvas}
      array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   }
   set canvasInfo $canvasList(${_canvas})
   set canvasList($canvas) [lreplace $canvasInfo 0 0 $value]
   SharedData_setExpData ${_exp_path} canvases [array get canvasList]
}

proc SharedData_setExpDisplayRoot { _exp_path _canvas _value } {
   array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   if { ! [info exists canvasList(${_canvas})] } {
      SharedData_initExpDisplayData ${_exp_path} ${_canvas}
      array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   }
   set canvasInfo $canvasList(${_canvas})
   set canvasList($canvas) [lreplace $canvasInfo 1 1 $value]
   SharedData_setExpData ${_exp_path} canvases [array get canvasList]
}

proc SharedData_getExpDisplayNextY { _exp_path _canvas } {
   array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   if { ! [info exists canvasList(${_canvas})] } {
      SharedData_initExpDisplayData ${_exp_path} ${_canvas}
      array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   }
   set canvasInfo $canvasList(${_canvas})
   return [lindex ${canvasInfo} 0]
}

proc SharedData_getExpDisplayMaximumX { _exp_path _canvas } {
   array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   if { ! [info exists canvasList(${_canvas})] } {
      SharedData_initExpDisplayData ${_exp_path} ${_canvas}
      array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   }
   set canvasInfo $canvasList(${_canvas})
   return [lindex $canvasInfo 2]
}

proc SharedData_getExpDisplayMaximumY { _exp_path _canvas } {
   array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   if { ! [info exists canvasList(${_canvas})] } {
      SharedData_initExpDisplayData ${_exp_path} ${_canvas}
      array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   }
   set canvasInfo $canvasList(${_canvas})
   return [lindex $canvasInfo 3]
}

proc SharedData_getExpDisplayRoot { _exp_path _canvas } {
   array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   if { ! [info exists canvasList(${_canvas})] } {
      SharedData_initExpDisplayData ${_exp_path} ${_canvas}
      array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   }
   set canvasInfo $canvasList(${_canvas})
   return [lindex $canvasInfo 1]
}

proc SharedData_getExpCanvasList { _exp_path } {
   set resultList {}

   array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   foreach {canvas info} [array get canvasList] {
      lappend resultList $canvas
   }

   return ${resultList}
}

proc SharedData_removeExpDisplayData { _exp_path _canvas } {
   array set canvasList [SharedData_getExpData ${_exp_path} canvases]
   array unset canvasList ${_canvas}
   SharedData_setExpData ${_exp_path} canvases [array get canvasList]
}

proc SharedData_setStatusInfo { _exp_path _datestamp _status _status_info  } {
   global datestamps_${_exp_path}
   # puts "in SharedData_setStatusInfo $_exp_path $_datestamp status:$_status statusinfo:$_status_info"
   if { ![info exists datestamps_${_exp_path}] } {
      array set datestamps_${_exp_path} {}
   }
   # array set datestamps [SharedData_getExpData ${_exp_path} datestamps]
   
   if { [info exists datestamps_${_exp_path}(${_datestamp})] } {
      set statusList [set datestamps_${_exp_path}(${_datestamp})]
      set index [lsearch ${statusList} ${_status}]
      #puts "SharedData_setStatusInfo index:$index"
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

proc SharedData_getStatusInfo { _exp_path _datestamp _status } {
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

proc SharedData_removeStatusDatestamp { _exp_path _datestamp _canvas } {
   global datestamps_${_exp_path}
   if { [info exists datestamps_${_exp_path}(${_datestamp})] } {
      array unset datestamps_${_exp_path} ${_datestamp}
   }
   SharedData_removeExpDisplayData ${_exp_path} ${_canvas}
   foreach key { offset update_afterid rootnode startup modules updated_nodes node_mappings} {
      SharedData_unsetExpData ${_exp_path} ${_datestamp}_${key}
   }
   SharedFlowNode_removeDatestamp ${_exp_path} ${_datestamp}
}

proc SharedData_getDatestamps { _exp_path } {
   global datestamps_${_exp_path}
   set datestampList [array names datestamps_${_exp_path}]
   return ${datestampList}
}

proc SharedData_printNodeMapping { _exp_path _datestamp } {
   array set nodeMapping [SharedData_getExpData ${_exp_path} ${_datestamp}_node_mappings]
   foreach { real_node flow_node } [array get nodeMapping] {
      puts "real_node:${real_node} flow_node:${flow_node}"
   }
}

proc SharedData_printData { _exp_path {_datestamp ""} } {
   global datestamps_${_exp_path}
   puts "-------------------------------------------"
   puts "${_exp_path}"
   puts "-------------------------------------------"
   #array set datestamps [SharedData_getExpData ${_exp_path} datestamps]
   set datestamps [SharedData_getDatestamps ${_exp_path}]
   foreach datestamp ${datestamps} {
      # set statusList $datestamps(${datestamp})
      set statusList [set datestamps_${_exp_path}(${_datestamp})]
      puts "datestamp:${datestamp} statuses:${statusList}"
   }
}

proc SharedData_setMiscData { key_ value_ } {
   tsv::set misc ${key_} ${value_}
}

proc SharedData_getMiscData { key_ } {
   set value ""
   if { [tsv::exists misc ${key_}] } {
      set value [tsv::set misc ${key_}]
   }
   return ${value}
}

proc SharedData_getColor { key_ } {
   set value ""
   if { [tsv::exists misc ${key_}] } {
     set value [tsv::set misc ${key_}]
   }
   return ${value}
}

proc SharedData_setColor { key_ color_ } {
   tsv::set misc ${key_} ${color_}
}

proc SharedData_initColors {} {
   if { ! [tsv::exists misc CANVAS_COLOR] } {

      SharedData_setColor FLOW_SUBMIT_ARROW "#787878"
      SharedData_setColor FLOW_SUBMIT_ARROW "#787878"

      SharedData_setColor FLOW_FIND_SELECT "#ffe600"
      SharedData_setColor CANVAS_COLOR "#ececec"
      SharedData_setColor SHADOW_COLOR "#676559"
      SharedData_setColor NORMAL_RUN_OUTLINE black
      SharedData_setColor NORMAL_RUN_FILL "#6D7886"
      SharedData_setColor NORMAL_RUN_TEXT black
      SharedData_setColor ACTIVE_BG "#509df4"
      SharedData_setColor SELECT_BG "#509df4"
      #SharedData_setColor SELECT_BG "#3875d7"
      SharedData_setColor DEFAULT_BG "#ececec"
      SharedData_setColor DEFAULT_HEADER_BG "#ececec"
      SharedData_setColor DEFAULT_HEADER_FG "#FFF8DC"
      SharedData_setColor DEFAULT_ROW_FG "#FFF8DC"
      SharedData_setColor DEFAULT_ROW_BG "#ececec"

      SharedData_setColor COLOR_MSG_CENTER_MAIN "#8B1012"
      SharedData_setColor MSG_CENTER_NORMAL_FG "black"
      SharedData_setColor COLOR_MSG_CENTER_ALT "black"
      SharedData_setColor MSG_CENTER_ABORT_FG "white"
      SharedData_setColor MSG_CENTER_STRIPE_BG "grey95"
      SharedData_setColor MSG_CENTER_NORMAL_BG "grey90"

      # the key is the status
      # first color is fg, second color is bg, 3rd is overview box outline
      SharedData_setColor COLOR_STATUS_BEGIN "white #016e11 #016e11"
      SharedData_setColor COLOR_STATUS_INIT "black #ececec black"
      SharedData_setColor COLOR_STATUS_SUBMIT "white #b8bdc3 #b8bdc3"
      SharedData_setColor COLOR_STATUS_ABORT "white #8B1012 #8B1012"
      SharedData_setColor COLOR_STATUS_END "white DodgerBlue3 DodgerBlue3"
      SharedData_setColor COLOR_STATUS_CATCHUP "white #913b9c #913b9c"
      SharedData_setColor COLOR_STATUS_WAIT "black #e7ce69 #e7ce69"
      SharedData_setColor COLOR_STATUS_DISCRET "white #913b9c #913b9c"
      SharedData_setColor COLOR_STATUS_UNKNOWN "white black black"

      SharedData_setColor STATUS_SHADOW "white black black"
   }
}

proc SharedData_getMsgCenterThreadId {} {
   if { [tsv::exists threads MSG_CENTER] } {
      set value [tsv::set threads MSG_CENTER]
   } else {
      set value ""
   }
   return ${value}
}

proc SharedData_setMsgCenterThreadId { thread_id } {
   tsv::set threads MSG_CENTER ${thread_id}
}

proc SharedData_getRippleStatusMap { status } {
   global RIPPLE_STATUS_MAP
   if { ! [info exists RIPPLE_STATUS_MAP] } {
      array set RIPPLE_STATUS_MAP {
         abortx abort
         abort  abort
         end    end
         endx   end
         begin  begin
         beginx begin
         init   init
         submit submit
         wait   wait
         catchup catchup
         discret discret
      }
   }

   set foundStatus ""
   if { [info exists RIPPLE_STATUS_MAP(${status})] } {
      set foundStatus $RIPPLE_STATUS_MAP(${status})
   }
}

proc SharedData_init {} {
   SharedData_initColors

   SharedData_setMiscData CANVAS_BOX_WIDTH 90
   SharedData_setMiscData CANVAS_X_START 40
   SharedData_setMiscData CANVAS_Y_START 40
   SharedData_setMiscData CANVAS_BOX_HEIGHT 43
   SharedData_setMiscData CANVAS_PAD_X 30
   SharedData_setMiscData CANVAS_PAD_Y 15
   SharedData_setMiscData CANVAS_PAD_TXT_X 4
   SharedData_setMiscData CANVAS_PAD_TXT_Y 23

   SharedData_setMiscData LOOP_OVAL_SIZE 15

   SharedData_setMiscData SHOW_ABORT_TYPE true
   SharedData_setMiscData SHOW_EVENT_TYPE true
   SharedData_setMiscData SHOW_INFO_TYPE true

   SharedData_setMiscData MSG_CENTER_BELL_TRIGGER 15
   SharedData_setMiscData MSG_CENTER_USE_BELL true

   #SharedData_setMiscData FONT_BOLD "-microsoft-verdana-bold-r-normal--11-*-*-*-p-*-iso8859-10"
   SharedData_setMiscData FONT_BOLD "-*-*-bold-r-normal--11-*-*-*-p-*-iso8859-10"
   SharedData_setMiscData DEBUG_TRACE 0
   SharedData_setMiscData FLOW_SCALE 1
   SharedData_setMiscData AUTO_LAUNCH true
   SharedData_setMiscData AUTO_MSG_DISPLAY true
   SharedData_setMiscData NODE_DISPLAY_PREF normal
   SharedData_setMiscData STARTUP_DONE false 

   SharedData_setMiscData FLOW_SCALE 1
   SharedData_setMiscData XFLOW_EXP_LABEL_SIZE 25
   SharedData_setMiscData OVERVIEW_MODE false
   SharedData_setMiscData DEFAULT_CONSOLE "konsole -e"
   SharedData_setMiscData TEXT_VIEWER default
   SharedData_setMiscData USER_TMP_DIR default

   SharedData_setMiscData MENU_RELIEF flat
   
   # number of threads created to process xflow instances
   SharedData_setMiscData MAX_XFLOW_INSTANCE 20

   # SharedData_readProperties
}

proc SharedData_readProperties { {rc_file ""} } {
   global env DEBUG_TRACE
   set DEBUG_TRACE [SharedData_getMiscData DEBUG_TRACE]
   set errorMsg ""
   if { ${rc_file} == "" } {
      set fileName $env(HOME)/.maestrorc
   } else {
      set fileName ${rc_file}
   }

   if { [file exists ${fileName}] } {
      set propertiesFile [open ${fileName} r]

      while {[gets ${propertiesFile} line] >= 0 && ${errorMsg} == "" } {
         #puts "SharedData_readProperties processing line: ${line}"
         if { [string index ${line} 0] != "#" && [string length ${line}] > 0 } {
            #puts "SharedData_readProperties found data line: ${line}"
            # the = sign is used to separate between the key and the value.
            # spaces around the values are trimmed
            set splittedList [split ${line} =]

            # if the list does not contain 2 elements, something's not right
            # output the error message
            if { [llength ${splittedList}] != 2 } {
               # error "ERROR: While reading ${fileName}\nInvalid property syntax: ${line}"
               set errorMsg "While reading ${fileName}\n\nInvalid property syntax: ${line}.\n"
            } else {
               set keyFound [string toupper [string trim [lindex $splittedList 0]]]
               set valueFound [string trim [lindex $splittedList 1]]
               #puts "SharedData_readProperties found key:${keyFound} value:${valueFound}"
               puts "maestrorc preference name:${keyFound} value:${valueFound}"
               SharedData_setMiscData ${keyFound} ${valueFound}
            }
         }
      }
      catch { close ${propertiesFile} }
      if { ${errorMsg} != "" } {
         Utils_fatalError . "Xflow Startup Error" ${errorMsg}
      }
   }
}
