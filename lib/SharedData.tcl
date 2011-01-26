package require Thread

# first element in the suites/exp_path is the suite's root_node
# second element in the suites/exp_path is the suite's thread id
proc SharedData_setRootNode { exp_path root_node } {
   set values {}
   if { [tsv::exists suites ${exp_path}] } {
      set values [tsv::set suites ${exp_path}]
   }
   set values [lreplace ${values} 0 0 ${root_node}]
   tsv::set suites ${exp_path} ${values}
}

proc SharedData_getRootNode { exp_path } {
   set returnedValue ""
   if { [tsv::exists suites ${exp_path}] } {
      set values [tsv::set suites ${exp_path}]
      set returnedValue [lindex ${values} 0]
   }
   return ${returnedValue}
}

proc SharedData_setSuiteData { exp_path key value } {
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

proc SharedData_getSuiteData { exp_path key } {
   set returnedValue ""
   if { [tsv::exists ${exp_path} ${key}] } {
      array set values [tsv::array get ${exp_path} ${key}]      
      set returnedValue $values(${key})
   }
   return ${returnedValue}
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
   if { [tsv::exists colors ${key_}] } {
     set value [tsv::set colors ${key_}]
   }
   return ${value}
}

proc SharedData_setColor { key_ color_ } {
   tsv::set colors ${key_} ${color_}
}

proc SharedData_initColors {} {
   if { ! [tsv::exists colors CANVAS_COLOR] } {

      SharedData_setColor FLOW_SUBMIT_ARROW "#787878"
      SharedData_setColor FLOW_SUBMIT_ARROW "#787878"

      SharedData_setColor CANVAS_COLOR "#ececec"
      SharedData_setColor SHADOW_COLOR "#676559"
      SharedData_setColor NORMAL_RUN_OUTLINE black
      SharedData_setColor NORMAL_RUN_FILL "#6D7886"
      SharedData_setColor NORMAL_RUN_TEXT blue
      SharedData_setColor ACTIVE_BG "#509df4"
      SharedData_setColor SELECT_BG "#509df4"
      #SharedData_setColor SELECT_BG "#3875d7"
      SharedData_setColor DEFAULT_BG "#ececec"
      SharedData_setColor DEFAULT_HEADER_BG "#ececec"
      SharedData_setColor DEFAULT_HEADER_FG "#FFF8DC"
      SharedData_setColor DEFAULT_ROW_FG "#FFF8DC"
      SharedData_setColor DEFAULT_ROW_BG "#ececec"

      SharedData_setColor MSG_CENTER_ABORT_BG "#8B1012"
      SharedData_setColor MSG_CENTER_NORMAL_FG "black"
      SharedData_setColor MSG_CENTER_ALT_BG "black"
      SharedData_setColor MSG_CENTER_ABORT_FG "white"

      # the key is the status
      # first color is fg, second color is bg, 3rd is overview box outline
      SharedData_setColor STATUS_begin "white #016e11 #016e11"
      SharedData_setColor STATUS_init "black #ececec black"
      SharedData_setColor STATUS_submit "white #b8bdc3 #b8bdc3"
      SharedData_setColor STATUS_abort "white #8B1012 #8B1012"
      SharedData_setColor STATUS_end "white DodgerBlue4 DodgerBlue4"
      SharedData_setColor STATUS_catchup "white #913b9c #913b9c"
      SharedData_setColor STATUS_wait "black #e7ce69 #e7ce69"
      SharedData_setColor STATUS_unknown "white black black"

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

   SharedData_setMiscData SHOW_ABORT_TYPE true
   SharedData_setMiscData SHOW_EVENT_TYPE true
   SharedData_setMiscData SHOW_INFO_TYPE true

   SharedData_setMiscData MSG_CENTER_BELL_TRIGGER 15
   SharedData_setMiscData MSG_CENTER_NUMBER_ROWS 25

   SharedData_setMiscData FONT_BOLD "-microsoft-verdana-bold-r-normal--11-*-*-*-p-*-iso8859-10"
   SharedData_setMiscData DEBUG_TRACE 1
   SharedData_setMiscData DEBUG_LEVEL 5
   SharedData_setMiscData AUTO_LAUNCH true
   SharedData_setMiscData AUTO_MSG_DISPLAY true
   SharedData_setMiscData NODE_DISPLAY_PREF normal
   SharedData_setMiscData STARTUP_DONE false 
   SharedData_setMiscData OVERVIEW_MODE false
   SharedData_setMiscData DEFAULT_CONSOLE konsole
   SharedData_setMiscData TEXT_VIEWER default
   SharedData_setMiscData USER_TMP_DIR default

   SharedData_setMiscData MENU_RELIEF flat

   SharedData_readProperties
}

proc SharedData_readProperties {} {
   global env DEBUG_TRACE DEBUG_LEVEL
   set DEBUG_TRACE [SharedData_getMiscData DEBUG_TRACE]
   set DEBUG_LEVEL [SharedData_getMiscData DEBUG_LEVEL]
   set errorMsg ""

   set fileName $env(HOME)/.maestrorc
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
               puts "SharedData_readProperties found key:${keyFound} value:${valueFound}"
               SharedData_setMiscData ${keyFound} ${valueFound}
            }
         }
      }
      catch { close ${propertiesFile} }
      if { ${errorMsg} != "" } {
         FatalError . "Xflow Startup Error" ${errorMsg}
      }
   }
}
