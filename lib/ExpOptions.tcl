package require Tktable

# show support info from xml file
#
# for now the xml is quite small so I don't
# bother storing anything in memory...
# the xml file is simply parse everything the
# functionality is called
proc ExpOptions_showSupport { exp_path parent_widget } {
   global env dataArray
   set optionsFile ${exp_path}/ExpOptions.xml
   set supportData ""
   #puts "ExpOptions_showSupport exp_path:$exp_path"
   set parentCode ""
   if { ! [file exists ${optionsFile}] } {
      set msg "Support info file not found: ${exp_path}/ExpOptions.xml"
      set title "Experiment Support Info"
      tk_messageBox -title ${title} -parent ${parent_widget} -type ok -icon info -message ${msg}
      return
   }

   # retrieve data from xml file
   if { [file exists ${optionsFile}] } {
      set domDoc [ExpXmlOptions_parse ${optionsFile}]
      set supportData [ExpXmlOptions_getSupport ${domDoc} [file tail ${exp_path}]]
      ExpXmlOptions_done ${domDoc}
   }

   # built data array for widget
   array set dataArray { 0,0 "Exp Name" 0,1 "Executing" 0,2 "Support Status"}
   set nextRow 1
   foreach { exp execInfo statusInfo } ${supportData} {
      set dataArray(${nextRow},0) ${exp}
      set dataArray(${nextRow},1) ${execInfo}
      set dataArray(${nextRow},2) ${statusInfo}
      incr nextRow
   }

   set topW .support_top
   set tableBgColor [SharedData_getColor DEFAULT_BG]
   set headerBgColor [SharedData_getColor MSG_CENTER_ABORT_BG]
   set headerFgColor [SharedData_getColor DEFAULT_HEADER_FG]

   destroy ${topW}

   Utils_positionWindow [toplevel ${topW}] ${parent_widget}
   wm title ${topW} "Experiment Support Info"

   set tableW [table ${topW}.table -cols 3 -rows ${nextRow} -titlerows 1 -rowheight 2 -pady 6 \
      -colstretchmode all -rowstretchmode all -variable dataArray -wrap 1 \
      -bg ${tableBgColor} -state disabled]
   #${tableW} tag configure title -bd 1 -bg ${headerBgColor} -relief raised -font TkHeadingFont -fg ${headerFgColor}
   ${tableW} tag configure title -bd 1 -relief raised -font TkHeadingFont

   ${tableW} width 0 20 1 20 2 40
   set titleRelief raised

   pack ${tableW} -expand 1 -fill both
}

# displays the list of maestroe executables with a short description
