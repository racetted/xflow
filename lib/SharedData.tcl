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
      SharedData_setColor CANVAS_COLOR cornsilk3
      SharedData_setColor SHADOW_COLOR "#676559"
      SharedData_setColor NORMAL_RUN_OUTLINE black
      SharedData_setColor NORMAL_RUN_FILL "#6D7886"
      SharedData_setColor NORMAL_RUN_TEXT blue
      SharedData_setColor ACTIVE_BG blue
      SharedData_setColor SELECT_BG blue
      SharedData_setColor DEFAULT_BG cornsilk3
      SharedData_setColor DEFAULT_HEADER_BG cornsilk4
      SharedData_setColor DEFAULT_HEADER_FG "#FFF8DC"
      SharedData_setColor DEFAULT_ROW_FG "#FFF8DC"
      SharedData_setColor DEFAULT_ROW_BG "cornsilk3"

      SharedData_setColor STATUS_INIT_BG "cornsilk4"
      SharedData_setColor STATUS_INIT_FG "#FFF8DC"
      SharedData_setColor STATUS_SUBMIT_BG "cornsilk3"
      SharedData_setColor STATUS_SUBMIT_FG "white"
      SharedData_setColor STATUS_BEGIN_BG "#108B5C"
      SharedData_setColor STATUS_BEGIN_FG "white"
      SharedData_setColor STATUS_END_BG "DodgerBlue4"
      SharedData_setColor STATUS_END_FG "white"
      SharedData_setColor STATUS_ABORT_BG "#8B1012"
      SharedData_setColor STATUS_ABORT_FG "white"
      SharedData_setColor STATUS_WAIT_BG "Sandybrown"
      SharedData_setColor STATUS_ABORT_FG "black"
      SharedData_setColor STATUS_CATCHUP_BG "Magenta2"
      SharedData_setColor STATUS_CATCHUP_FG "white"
      SharedData_setColor STATUS_UNKNOWN_BG "black"
      SharedData_setColor STATUS_UNKNOWN_FG "white"
      SharedData_setColor STATUS_SHADOW_BG "black"
      SharedData_setColor STATUS_SHADOW_FG "white"

      SharedData_setColor NORMAL_MSG_FG "black"
      SharedData_setColor ABORT_MSG_ALTERNATE_BG "black"
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
   SharedData_setMiscData MENU_RELIEF flat
   SharedData_setMiscData IMAGE_DIR /data/bowmore/afsisul/downloads/icons/
}
