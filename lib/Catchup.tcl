package require Tk
package require tooltip

proc Catchup_createMainWidgets { _topLevelW } {
   if { [winfo exists ${_topLevelW}] } {
      destroy ${_topLevelW}
   }

   toplevel ${_topLevelW}

   Utils_positionWindow ${_topLevelW}

   wm title ${_topLevelW} "Maestro Catchup Settings"
   set catchupValues { Stop 1 2 3 4 5 6 7 Normal Discretionary }
   set catchupLabelW [label ${_topLevelW}.catchup_label -text "Catchup Values:"]
   set comboW [ttk::combobox ${_topLevelW}.catchup_combo -state readonly -values ${catchupValues} ]
   set buttonFrame [frame ${_topLevelW}.button_Frame]
   set closeButton [button ${buttonFrame}.close_button -text Close -command [list destroy ${_topLevelW}]]
   set applyButton [button ${buttonFrame}.apply_button -text Apply -command [list Catchup_applyCallback ${comboW}]]
   set refreshButton [button ${buttonFrame}.refresh_button -text Refresh -command [list Catchup_refreshCallback ${comboW}]]

   grid ${catchupLabelW} ${comboW} -padx { 5 2 } -pady 10
   grid ${refreshButton} ${applyButton} ${closeButton} -padx { 2 2 } -pady 5 -sticky e

   grid ${buttonFrame} -column 1 -padx 5 -sticky e

   # set initial value
   Catchup_refreshCallback  ${comboW}

   tooltip::tooltip ${refreshButton} "Retrieve saved catchup value."
   tooltip::tooltip ${applyButton} "Apply selected catchup value."
   tooltip::tooltip ${closeButton} "Close catchup window."

   wm resizable ${_topLevelW} 0 0
}

proc Catchup_refreshCallback { _catchupComboBox } {
   set catchupIntValue [Catchup_retrieve]
   ${_catchupComboBox} set [Catchup_getVerboseValue ${catchupIntValue}]
}

# called when user click on apply
proc Catchup_applyCallback { _catchupComboBox } {
   # get value from combo box
   set catchupValue [${_catchupComboBox} get]

   set topW [winfo toplevel ${_catchupComboBox}]
   # ask confirmation
   set answer [ tk_messageBox -icon question -parent ${topW} -type okcancel -title "Catchup Save Confirmation" \
      -message "Are you sure you want to save the experiment catchup value to '${catchupValue}'?" ]

   if { ${answer} == "ok" } {
      # get int value
      set catchupIntValue [Catchup_getIntValue ${catchupValue}]

      # save
      Catchup_save ${catchupIntValue}

      # post-save message
      tk_messageBox -parent ${topW} -type ok -title "Catchup Confirmation" -message "Catchup value saved."
   }
}

# returns the catchup value stored in the experiment,
# as given by the "expcatchup -g" command
proc Catchup_retrieve {} {
   global SEQ_EXP_HOME
   
   set catchupExec "[SharedData_getMiscData SEQ_BIN]/expcatchup"
   set cmd "export SEQ_EXP_HOME=${SEQ_EXP_HOME};${catchupExec} -g"
   set catchupValue ""
   set catchupValue [exec ksh -c $cmd]
   return ${catchupValue}
}

proc Catchup_save { _catchupIntValue } {
   global env
   
   set catchupExec "[SharedData_getMiscData SEQ_BIN]/expcatchup"
   set cmd "export SEQ_EXP_HOME=$env(SEQ_EXP_HOME);${catchupExec} -s ${_catchupIntValue}"
   set catchupValue ""
   set catchupValue [exec ksh -c $cmd]
   return ${catchupValue}
}

# returns integer value of catchup
# example: _catchupValue = 8, returns 8
# example: _catchupValue = Normal, returns 8
proc Catchup_getIntValue { _catchupValue } {
   array set catchupMapping {
      Stop 0
      Normal 8
      Discretionary 9
   }

   set intValue ${_catchupValue}
   if { ! [string is integer ${_catchupValue}] } {
      set intValue $catchupMapping($_catchupValue)
   }
   return ${intValue}
}

# return the string value of an integer catchup value
# example: _catchupValue = 8, returns Normal
# example: _catchupValue = 9, returns Discretionary
# example: _catchupValue = 4, returns 4
proc Catchup_getVerboseValue { _catchupValue } {
   array set catchupMapping {
      0 Stop
      8 Normal
      9 Discretionary
   }
   set verboseValue ${_catchupValue}
   if { [info exists catchupMapping($_catchupValue)] } {
      set verboseValue $catchupMapping($_catchupValue)
   }

   return ${verboseValue}
}
