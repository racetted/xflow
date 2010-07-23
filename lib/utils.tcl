# test
proc DEBUG { output {level 2} } {
   set debugOn [getGlobalValue "DEBUG_TRACE"]
   set debugLevel [getGlobalValue "DEBUG_LEVEL"]
   if { $debugOn && $debugLevel >= $level} {
      puts "$output"
      flush stdout
   }
}

proc setGlobalValue { key value } {
   global GLOBAL_LIST
   set GLOBAL_LIST($key) $value
}

proc getGlobalValue {key} {
   global GLOBAL_LIST
   set value $GLOBAL_LIST($key)
   return $value
}

proc bindMouseWheel { widget } {
   #puts "bindMouseWheel widget:$widget"
   bind $widget <4> {
      if {!$tk_strictMotif} {
         %W yview scroll -5 units
         #puts "bindMouseWheel yview -5 called"
      }
   }
   bind $widget <5> {
      if {!$tk_strictMotif} {
         %W yview scroll 5 units
         #puts "bindMouseWheel yview +5 called"
      }
   }
}

proc normalCursor { w } {
   if { [winfo exists $w] } {
      catch {
         $w configure -cursor arrow
         #blt::busy forget $w
         update idletasks
      }
   }
}

proc busyCursor { w } {
   if { [winfo exists $w] } {
      $w configure -cursor watch
      #blt::busy hold $w
      update idletasks
   }
}

proc isBusy { w } {
   if [
      catch {
         if { [winfo exists $w] } {
            if { [blt::busy status $w] == 1 } {
               return 1
            } else {
               return 0
            }
         }
      } ] {
      return 0
   }
}


proc raiseError { parent title err_msg } {
   tk_messageBox -icon error -parent $parent -title $title -message $err_msg
}

proc FatalError { parent title err_msg } {
   wm withdraw .
   raiseError $parent $title $err_msg
   exit 0
}

proc quit { {message ""} } {
   if { !($message == "") } {
      DEBUG "Error:$message" 4
   }
   DEBUG "Application Exits!" 4
   exit
}

setGlobalValue SEQ_BIN [Sequencer_getPath]
setGlobalValue SEQ_UTILS_BIN [Sequencer_getUtilsPath]
setGlobalValue DEBUG_TRACE 1
setGlobalValue DEBUG_LEVEL 5

