#!/home/binops/afsi/ssm/sw/linux26-i686/bin/tclsh8.4
package require struct::record
package require tooltip
package require cmdline
package require Thread
namespace import ::tooltip::tooltip
namespace import ::struct::record::record

global env
if { ! [info exists env(SEQ_XFLOW_BIN) ] } {
   puts "Environment variable SEQ_XFLOW_BIN must be defined!"
   exit
}
puts "SEQ_XFLOW_BIN=$env(SEQ_XFLOW_BIN)"

set lib_dir $env(SEQ_XFLOW_BIN)/../lib
puts "lib_dir=$lib_dir"
set auto_path [linsert $auto_path 0 $lib_dir ]

package require SuiteNode

proc Overview_addFileMenu { parent } {
   set menuButtonW ${parent}.file_menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text File -underline 0 -menu $menuW -relief raised
   menu $menuW -tearoff 0

   $menuW add command -label "Quit" -underline 0 -command "Overview_quit $parent" 

   pack $menuButtonW -side left -pady 2 -padx 2
}

proc Overview_addPrefMenu { parent } {
   set menuButtonW ${parent}.pref_menub
   set menuW $menuButtonW.menu

   menubutton $menuButtonW -text Preferences -underline 0 -menu $menuW -relief raised
   menu $menuW -tearoff 0

   $menuW add checkbutton -label "Auto Launch" -variable AUTO_LAUNCH \
      -onvalue 1 -offvalue 0

   tooltip $menuW -index 0 "Automatic launch of flow when experiment starts"
   pack $menuButtonW -side left -pady 2 -padx 2
}

proc Overview_setCurrentTime { canvas } {
   global graphStartX graphStartY graphHourX graphy TimeAfterId
   DEBUG "setCurrentTime canvas:$canvas" 5
   $canvas delete current_timeline

   # setting current time
   set currentTime [exec date +%H.%M]
   set x1 [expr $graphStartX + $currentTime * $graphHourX]
   set x2 [expr $graphStartX + $currentTime * $graphHourX]
   set y1 [expr $graphStartY - 4]
   set y2 [expr $graphStartY + 4]
   set lineId [$canvas create line $x1 [expr $y1 - 40] $x2 [expr $y2 + $graphy + 40 ] -tag current_timeline -fill DarkGreen]
   ::tooltip::tooltip $canvas -item "${lineId}" "Current Time:${currentTime}Z\nUpdated every 30 seconds"

   if { [$canvas gettags current_timetext] == "" } {
      $canvas create text $x1 [expr $y2 + $graphy + 45] -fill DarkGreen -anchor w -justify left -tag current_timetext
   }

   $canvas itemconfigure current_timetext -text "Current Time: ${currentTime}Z"

   set TimeAfterId [after 30000 [list Overview_setCurrentTime $canvas]]
}

proc Overview_addExpBox { group_record canvas suite_record } {
   global graphStartX graphHourX expEntryHeight expBoxLength

   DEBUG "Overview_addExpBox group_record:$group_record exp_path:[$suite_record cget -suite_path]"
   set exp_path [$suite_record cget -suite_path]
   set startTime [$suite_record cget -ref_start]
   set endTime [$suite_record cget -ref_end]
   if { $startTime == "" || $endTime == ""} {
      set startX [expr [${group_record} cget -x] - 4]
      set endX [expr $startX + $expBoxLength]
      set labelX [expr $startX + 8]
   } else {
      set modifStart [regsub -all ":" ${startTime} .]
      set modifEnd [regsub -all ":" ${endTime} .]
      set startX [expr $graphStartX + $modifStart * $graphHourX ]
      set endX [expr $graphStartX + $modifEnd * $graphHourX]
      set labelX [expr $startX + 8]
   }
   set expY [${group_record} cget -y]
   set startY [${group_record} cget -y]
   set endY [expr $startY + $expEntryHeight/2 + 8]

   set tailName [file tail ${exp_path}]
   set expLabel " ${tailName} "

   # create the left box
   set startBoxId [$canvas create rectangle $startX $startY [expr $startX + 5] $endY \
      -fill bisque4 -outline bisque4 -tag "${exp_path} ${exp_path}.start"]

   # create the right box
   set endBoxId [$canvas create rectangle $endX $startY [expr $endX + 5]  $endY \
      -fill bisque4 -outline bisque4 -tag "${exp_path} ${exp_path}.end"]

   # create the middle box
   set middleBoxId [$canvas create rectangle [expr $startX + 5] $startY \
      $endX $endY -outline bisque4 -fill white -tag "${exp_path} ${exp_path}.middle"]

   # create the exp label
   set expLabelId [$canvas create text $labelX [expr $expY + $expEntryHeight/2] \
      -text $expLabel -fill grey20 -anchor w -tag "${exp_path} ${exp_path}.text"]

   # set newx for next item, only used when ref timings not used
   ${group_record} configure -x [expr $endX + 20] 

   Overview_resolveOverlap $group_record $canvas ${exp_path}
   $canvas bind $middleBoxId <Double-Button-1> [list Overview_launchExpFlow $canvas $exp_path ]
   $canvas bind ${exp_path} <Button-3> [ list Overview_boxMenu $canvas $exp_path %X %Y]
}

proc Overview_resolveOverlap { group_record canvas exp_path } {
   DEBUG "Overview_resolveOverlap $exp_path" 5
   global expEntryHeight
   set expList [$group_record cget -exp_list]
   set currentBox [$canvas bbox ${exp_path}]
   set x1 [lindex $currentBox 0]
   set y1 [lindex $currentBox 1]
   set x2 [lindex $currentBox 2]
   set y2 [lindex $currentBox 3]
   DEBUG "Overview_resolveOverlap x1:$x1 y1:$y1 x2:$x2 y2:$y2" 5
   foreach exp $expList {
      set xOverlap 0
      set yOverlap 0
      if { ${exp} != ${exp_path} && [${canvas} gettags ${exp}] != "" } {
         set thisExpBox [$canvas bbox $exp]
         set xx1 [lindex $thisExpBox 0]
         set yy1 [lindex $thisExpBox 1]
         set xx2 [lindex $thisExpBox 2]
         set yy2 [lindex $thisExpBox 3]
         DEBUG "Overview_resolveOverlap xx1:$xx1 yy1:$yy1 xx2:$xx2 yy2:$yy2" 5
         if { ([expr $x1 >= $xx1] && [expr $x1 <= $xx2]) ||
              ([expr $x2 >= $xx1] && [expr $x2 <= $xx2]) } {
            set xOverlap 1
         }
         if { ([expr $y1 >= $yy1] && [expr $y1 <= $yy2]) ||
              ([expr $y2 >= $yy1] && [expr $y2 <= $yy2]) } {
            set yOverlap 1
         }
      }
      if { $xOverlap && $yOverlap } {
         DEBUG "exp_path we have and overlap" 5
         break
      }
   }
   if { $xOverlap && $yOverlap } {
      $canvas move $exp_path 0 $expEntryHeight
      set newY [expr [$group_record cget -y] + $expEntryHeight]
      $group_record configure -y $newY
   }
}

proc Overview_boxMenu { canvas exp_path x y } {
   DEBUG "Overview_boxMenu() exp_path:$exp_path" 5
   set popMenu .popupMenu
   if { [winfo exists $popMenu] } {
      destroy $popMenu
   }
   menu $popMenu
   $popMenu add command -label "History" \
      -command [list Overview_historyCallback $canvas $exp_path $popMenu]
   $popMenu add command -label "Display Flow" -command [list Overview_launchExpFlow $canvas $exp_path]
   tk_popup $popMenu $x $y
}

proc Overview_historyCallback { canvas exp_path caller_menu } {
   DEBUG "Overview_historyCallback exp_path:$exp_path" 5
   set seqExec [getGlobalValue SEQ_UTILS_BIN]/nodehistory

   set seqNode "/[file tail $exp_path]"
   Sequencer_runCommand $exp_path $seqExec "Node History ${exp_path}" -n $seqNode
}

proc Overview_launchExpFlow { calling_w exp_path } {
   global env ExpThreadList
   set xflowCmd $env(SEQ_XFLOW_BIN)/xflow
   #set cmd "export SEQ_EXP_HOME=${exp_path};${xflowCmd}"
   #DEBUG "Overview_launchExpFlow executing ksh -c $cmd" 5
   #catch { eval [exec ksh -c $cmd &]}

   set mainid [thread::id]
   set formatName [::SuiteNode::formatName ${exp_path}]
   set suiteRecord SuiteInfo.${formatName}

   # create a child thread for the exp
   set childId [Overview_createThread]

   # create a dummy suite record in the child thread
   #thread::send ${childId} "thread_cp_record ${exp_path} 4000"

   # run the child thread
   #thread::send -async ${childId} "thread_launchFLow ${mainid} ${suiteRecord}"
   #thread::send ${childId} "thread_launchFLow ${mainid} ${suiteRecord}"

   set threadId [Overview_getExpThread ${exp_path}]
   thread::send ${threadId} "thread_launchFLow ${mainid} ${suiteRecord}"
}


# this function is called asynchronously by experiment child threads to
# update the status of an experiment node in the overview panel.
# See LogReader.tcl
proc Overview_updateExp { suite_record status timestamp {is_startup 0} } {
   global IS_STARTUP AUTO_LAUNCH
   DEBUG "Overview_updateExp status:$status timestamp:$timestamp is_startup:$is_startup" 5
   set colors [::DrawUtils::getStatusColor $status]
   set bgColor [lindex $colors 1]
   set canvas .overview_top.canvas

   # start synchronizing this block, get an exclusive lock
   set mutex [thread::mutex create]
   thread::mutex lock $mutex

   set tagName [$suite_record cget -suite_path]
   $suite_record configure -last_status $status -last_status_time $timestamp

   if { [winfo exists $canvas] } {
      $canvas itemconfigure ${tagName}.start -fill $bgColor -outline $bgColor
      $canvas itemconfigure ${tagName}.middle -outline $bgColor
      $canvas itemconfigure ${tagName}.end -fill $bgColor -outline $bgColor
   
      # launch the flow if needed
      if { $status == "begin" && ${AUTO_LAUNCH} && ! ${is_startup} } {
         Overview_launchExpFlow $canvas [$suite_record cget -suite_path]
      }
   
      # has the run started or ended late?
      if { $status == "end" || $status == "begin" } {
         set refEndTime [${suite_record} cget -ref_end]
         if { ${refEndTime} != "" } {
            set endTime [string range ${timestamp} 19 23]
            if { $endTime > $refEndTime } {
               $canvas itemconfigure ${tagName}.end -fill DarkViolet -outline DarkViolet
            }
         }
      }
   } else {
      DEBUG "Overview_updateExp canvas $canvas does not exists!" 5
   }

   # unlock and destroy the lock
   thread::mutex unlock $mutex
   thread::mutex destroy $mutex
}

proc Overview_addExpThread { exp_path thread_id } {
   global ExpThreadList

   set ExpThreadList(${exp_path}) $thread_id
}

proc Overview_getExpThread { exp_path } {
   global ExpThreadList

   if { [info exists ExpThreadList(${exp_path})] } {
      return $ExpThreadList(${exp_path})
   }
   return ""
}

proc Overview_addExp { group_record canvas exp_path } {
   DEBUG "Overview_addExp group_record:$group_record exp_path:$exp_path" 5
   
   set tagName [regsub -all "/" ${exp_path} _]
   set tagName [regsub -all " " ${tagName} _ ]
   set tailName [file tail ${exp_path}]
   #set expLabel " [file tail ${tailName}] "
   set expX [expr [${group_record} cget -x] + 10]
   DEBUG "Overview_addExp expX:$expX" 5
   set expY [${group_record} cget -y]

   set formatName [::SuiteNode::formatName ${exp_path}]
   set suiteRecord SuiteInfo.${formatName}
   SuiteInfo $suiteRecord -type "user" -suite_name ${tailName} -suite_path $exp_path \
      -read_interval 4000

   Overview_getExpTimings $suiteRecord

   Overview_addExpBox $group_record $canvas $suiteRecord
   set mainid [thread::id]

   # create a child thread for the exp
   set childId [Overview_createThread]
   # create a dummy suite record in the child thread
   thread::send ${childId} "thread_cp_record ${exp_path} 4000"
   # run the child thread
   thread::send -async ${childId} "thread_startLogReader 1 ${mainid} ${suiteRecord}"
   #thread::send ${childId} "thread_startLogReader ${mainid} ${suiteRecord}"

   Overview_addExpThread [${suiteRecord} cget -suite_path] ${childId}
}

proc Overview_createThread {} {

   set threadID [thread::create {

      global env
      set lib_dir $env(SEQ_XFLOW_BIN)/../lib
      set auto_path [linsert $auto_path 0 $lib_dir ]

      package require SuiteNode

      #
      # From here to the 'thread::wait' statement, define the procedure(s)
      # that will be called from your main program
      #
      # The 'thread::wait' is required to keep this thread alive indefinitely.
      #
      global this_id
      set this_id [thread::id]

      #proc sendHeartbeat { parent_id exp_path } {
      #   global this_id
      #   thread::send -async ${parent_id} "threadHeartbeat ${this_id} ${exp_path}"
      #   after 30000 [list sendHeartbeat $parent_id $exp_path]
      #}

      proc thread_cp_record { exp_path read_interval } {
         set formatName [::SuiteNode::formatName ${exp_path}]
         set suiteRecord SuiteInfo.${formatName}
         SuiteInfo $suiteRecord -type "user" -suite_name [file tail $exp_path] \
            -suite_path $exp_path -read_interval ${read_interval}
      }

      proc thread_startLogReader { parent_id suite_record } {
         global this_id
         #sendHeartbeat $parent_id $exp_path
         #readLog $parent_id $exp_path
         set isStartup 1
         set isOverview 1
         LogReader_readFile ${suite_record} ${isOverview} ${parent_id} ${isStartup}
      }

      proc thread_launchFLow { parent_id suite_record } {
         global this_id env
         set env(SEQ_EXP_HOME) [${suite_record} cget -suite_path]
         launchXflow
      }
      
      puts "child thread ${this_id} waiting..."
      # enter event loop
      thread::wait
   }]
   return ${threadID}
}

proc Overview_getExpTimings { suite_record } {
   set exp_path [${suite_record} cget -suite_path]
   # get exp timings if exists
   set timingsFile ${exp_path}/ExpTimings
   if { [file exists $timingsFile] } {
      if [catch {open "$timingsFile" "r"} fileId] {
         puts stderr "Cannot open $timingsFile: $timingsFile"
         return 0
      } else {
         while {[gets $fileId line] >= 0} {
            set modif_line [regsub -all "=" ${line} " " ]
            eval "set ${modif_line}"
         }
         catch {
            $suite_record configure -ref_start ${ref_start} -ref_end ${ref_end}
         }
      }      
   }
}

# this function creates the group labels at the left of the graph
# the values of the labels are read from a suites/exp list
proc Overview_addGroups { canvas } {
   global graphX graphy graphStartX graphStartY graphHourX expEntryHeight entryStartX entryStartY

   set displayGroups [record show instances DisplayGroup]
   set expEntryCurrentY $entryStartY
   set expEntryCurrentX $entryStartX

   foreach displayGroup $displayGroups {
      set groupName [$displayGroup cget -name]
      set displayName [file tail $groupName]
      # replace / and spaces with _
      # canvas tag does not like it with spaces
      set tagName [regsub -all "/" ${displayName} _]
      set tagName [regsub -all " " ${tagName} _ ]
      set tagName ${tagName}.label
      #puts "Overview_addGroups groupName:$groupName"
      set groupLevel [$displayGroup cget -level]

      # add indentation for each different level
      set expEntryCurrentX [expr $entryStartX + 4 + $groupLevel * 15]

      #puts "Overview_addGroups groupName:$groupName entryStartX:$entryStartX"
      set groupId [$canvas create text $expEntryCurrentX [expr $expEntryCurrentY + $expEntryHeight/2]  \
         -text $displayName -justify left -anchor w -fill grey20 -tag ${tagName} ]

      # get the font for each level
      set newFont [Overview_getLevelFont $canvas ${tagName} $groupLevel]

      $canvas itemconfigure ${tagName} -font $newFont
      ::tooltip::tooltip $canvas -item "${groupId}" "more info here for $displayName"

      # get the exps for each group if exists
      set expList [$displayGroup cget -exp_list]
      $displayGroup configure -x [expr $graphStartX + 20] -y $expEntryCurrentY
      foreach exp $expList {
         Overview_addExp $displayGroup $canvas $exp
      }

      set expEntryCurrentY [$displayGroup cget -y]
      $displayGroup configure -y [expr $expEntryCurrentY + $expEntryHeight]
      set expEntryCurrentY [$displayGroup cget -y]
   }
}

# this function is a place holder to add logic to
# display different font for each level
proc Overview_getLevelFont { canvas item_tag level } {
   #puts "Overview_getLevelFont item_tag:$item_tag"
   set searchFont canvas_level_${level}_font
   if { [lsearch [font names] $searchFont] == -1 } {
      set canvasFont [$canvas itemcget "${item_tag}" -font]
      set newFont [font create canvas_level_${level}_font]
      font configure $newFont -family [font actual $canvasFont -family] \
         -size [font actual $canvasFont -size] \
         -weight [font actual $canvasFont -weight] \
         -slant  [font actual $canvasFont -slant ]

      if { $level == 0 } {
         font configure $newFont  -weight bold
      }
   }

   return $searchFont
}

proc Overview_createGraph { canvas } {

   global graphX graphy graphStartX graphStartY graphHourX expEntryHeight entryStartX 

   # adds horiz shaded grid
   set x1 $entryStartX
   set x2  [expr $graphStartX + $graphX]
   set y1 $graphStartY
   set fillColor grey90
   while { $y1 < [expr $graphy + $graphStartY] } {
      $canvas create rectangle $x1 [expr $y1 ] $x2 [expr $y1 + $expEntryHeight ] -fill $fillColor -outline $fillColor
      set y1 [expr $y1 + $expEntryHeight]
      if { $fillColor == "grey90" } {
         set fillColor grey95
      } else {
         set fillColor grey90
      }
   }

   # creates hor lines at bottom & top
   $canvas create line $graphStartX $graphStartY [expr $graphStartX + $graphX] $graphStartY -arrow last
   $canvas create line $graphStartX [expr $graphStartY + $graphy] \
      [expr $graphStartX + $graphX] [expr $graphStartY + $graphy] -arrow last
   # x axis title
   $canvas create text [expr ${x2}/2 ] [expr $graphStartY + $graphy + 60] -text "Time (UTC)"
   
   # y axe origin
   $canvas create line $graphStartX [expr $graphStartY - 20] $graphStartX [expr $graphStartY + $graphy] -arrow first
   
   set count 1
   # adds hour delimiter & ver grid along hour
   while { $count < 25 } {
      if { $count < 10 } {
         set xLabel "0${count}Z"
      } else {
         set xLabel "${count}Z"
      }
      set x1 [expr $graphStartX + $count * $graphHourX]
      set x2 $x1
      set y1 [expr $graphStartY - 4]
      set y2 [expr $graphStartY + 4]
      $canvas create line $x1 $y1 $x2 $y2
      $canvas create line $x1 [expr $y1 + $graphy] $x2 [expr $y2 + $graphy ]
      $canvas create line $x1 [expr $y1 + 5] $x2 [expr $y2 + $graphy - 5 ] -dash 2 -fill grey60
   
      $canvas create text $x2 [expr $y1 - 20 ] -text $xLabel
      $canvas create text $x2 [expr $y2 + $graphy +20 ] -text $xLabel
      incr count
   }

}

proc Overview_init {} {
   global AUTO_LAUNCH
   global graphX graphy graphStartX graphStartY graphHourX expEntryHeight entryStartX entryStartY
   global expBoxLength

   set AUTO_LAUNCH 1

   # hor size of graph
   set graphX 1225
   # vert size of graph
   set graphy 600
   set graphStartX 200
   set graphStartY 50
   # x size of each hour
   set graphHourX 48
   # y size of each entry on the left side of y axis
   set expEntryHeight 20

   set expBoxLength 40
   
   # creates suite entries
   set entryStartY 70
   set entryStartX 20
}

proc Overview_readExperiments {} {
   global env
   set suitesFile [getGlobalValue SUITES_FILE]
   set suiteList {}
   if { [file exists $suitesFile] } {
      puts "Overview_readExperiments from file: $suitesFile"
      ExpXmlReader_readExperiments $suitesFile
      set suiteList [ExpXmlReader_getExpList]
      puts "suiteList: $suiteList"
   } else {
      FatalError . "Overview Startup Error" "${suitesFile} does not exists! Exiting..."
   }
}

proc Overview_quit { top } {
   global TimeAfterId
   if { [info exists TimeAfterId] } {
      after cancel $TimeAfterId
   }

   destroy $top
   exit 0
}

proc Overview_parseCmdOptions {} {
   global argv env 
   if { [info exists argv] } {
      set options {
         {main ""}
         {suites.arg "" "suites definition file"}
      }
   
      puts "parseCmdlineOptions arguments list: $argv"
   
      set usage "\[options] \noptions:"
      if [ catch { array set params [::cmdline::getoptions argv $options $usage] } message ] {
         puts "\n$message"
         exit 1
      }
      if { $params(main) } {
         setGlobalValue MAIN 1
      } else {
         setGlobalValue MAIN 0
      }
      if { ! ($params(suites) == "") } {
         DEBUG "parseCmdlineOptions using suites definition file :$params(suites)" 5
         setGlobalValue SUITES_FILE $params(suites)
      } else {
         setGlobalValue SUITES_FILE $env(HOME)/.suites/.xflow.suites.xml
      }
   } else {
      setGlobalValue MAIN 0
   }
}

global IS_STARTUP
wm withdraw .

#setGlobalValue DEBUG_TRACE 1
Overview_parseCmdOptions
set IS_STARTUP 1
if { [getGlobalValue MAIN] == 1 } {
   ::DrawUtils::init
   set topOverview .overview_top
   toplevel $topOverview
   #wm iconify $topOverview
   wm title $topOverview "Xflow Overview Panel"
   Overview_readExperiments
   Overview_init

   set topFrame $topOverview.topframe
   set topCanvas $topOverview.canvas
   ttk::frame $topFrame -relief raised
   grid $topFrame -row 0 -column 0 -sticky nw -padx 2 -pady 2
   Overview_addFileMenu $topFrame
   Overview_addPrefMenu $topFrame

   canvas $topCanvas -relief raised -bd 2 -bg cornsilk3
   grid $topCanvas -row 1 -column 0 -sticky nsew -padx 2 -pady 2
   grid columnconfigure $topOverview 0 -weight 1
   grid rowconfigure $topOverview 1 -weight 1

   Overview_createGraph $topCanvas
   Overview_addGroups $topCanvas
   Overview_setCurrentTime $topCanvas

   wm protocol $topOverview WM_DELETE_WINDOW [ list Overview_quit $topOverview ]
   wm geometry $topOverview =1500x800
   #wm deiconify $topOverview
}
set IS_STARTUP 0
