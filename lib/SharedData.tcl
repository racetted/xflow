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
      SharedData_setColor STATUS_submit "white #016e11 #016e11"
      SharedData_setColor STATUS_abort "white #8B1012 #8B1012"
      SharedData_setColor STATUS_end "white DodgerBlue4 DodgerBlue4"
      SharedData_setColor STATUS_catchup "white #913b9c #913b9c"
      SharedData_setColor STATUS_wait "black #e7ce69 #e7ce69"

      SharedData_setColor STATUS_SHADOW "white black black"
      SharedData_setColor STATUS_UNKNOWN "white black black"
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
   SharedData_setMiscData FONT_BOLD "-microsoft-verdana-bold-r-normal--11-*-*-*-p-*-iso8859-10"
   SharedData_setMiscData DEBUG_TRACE 1
   SharedData_setMiscData DEBUG_LEVEL 5

   SharedData_setMiscData AUTO_MSG_DISPLAY true
   SharedData_setMiscData STARTUP_DONE false 
   SharedData_setMiscData OVERVIEW_MODE false
   SharedData_setMiscData MENU_RELIEF flat
   SharedData_setMiscData IMAGE_DIR /users/dor/afsi/sul/icons
}
