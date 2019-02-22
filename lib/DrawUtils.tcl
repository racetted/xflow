package provide DrawUtils 1.0
package require Tk
package require BWidget 1.9

namespace eval ::DrawUtils {

   namespace export init clearCanvas drawTrapeze \
      drawNodeStatus getStatusColor

   # maps a family to image representation
   variable nodeTypeMap

   # maps a host to color representation
   variable hostColorMap
}

proc ::DrawUtils::init {} {
   variable nodeTypeMap
   variable constants

   array set nodeTypeMap {
      family rectangle
      module rectangle
      task rectangle
      npass_task arc
      loop oval
      outlet oval
      case losange
      switch_case losange
   }

   array set constants {
      border_width "3"
   }
   if { [SharedData_getMiscData FONT_NAME] != "" } {
      # use user defined font
      ::DrawUtils::setDefaultFonts [SharedData_getMiscData FONT_NAME] [SharedData_getMiscData FONT_NAME_SIZE] [SharedData_getMiscData FONT_NAME_SLANT] [SharedData_getMiscData FONT_NAME_UNDERL]
   }
}

proc ::DrawUtils::setDefaultFonts { {_family fixed} {_size 12} {_slant roman} {_underline 0}} {
   font configure TkDefaultFont -size ${_size} -family ${_family} -slant $_slant  -underline ${_underline}
   font configure TkTextFont -size ${_size} -family ${_family} -slant $_slant -underline ${_underline} 
   font configure TkMenuFont -size ${_size} -family ${_family} -slant $_slant -underline ${_underline} 
   font configure TkHeadingFont -size ${_size} -family ${_family} -slant $_slant -underline ${_underline} 
   font configure TkTooltipFont -size [expr ${_size} - 2] -family ${_family} -slant $_slant -underline ${_underline}
   font configure TkFixedFont -size ${_size} -family ${_family} -slant $_slant -underline ${_underline}
   font configure TkIconFont -size ${_size} -family ${_family} -slant $_slant -underline ${_underline}
}

proc ::DrawUtils::getBoxLabelFont { _canvas } {
   set labelFont flow_box_label_font
   
   if { [SharedData_getMiscData FONT_NAME] == "" } {
      # use legacy font
      return [SharedData_getMiscData FONT_BOLD]
   }

   # use user defined font
   if { [lsearch [font names] ${labelFont}] == -1 } {
      set newFont [font create ${labelFont}]
      font configure ${newFont} -family [SharedData_getMiscData FONT_TASK] \
         -size   [font actual ${_canvas} -size] \
         -weight [font actual ${_canvas} -weight] \
         -slant  [font actual ${_canvas} -slant ]

      # font configure ${newFont} -weight bold -size 11
      font configure ${newFont} -weight bold -size [expr  [font actual ${_canvas} -size] - 2 ]
   } else {
      font configure ${labelFont} -family [SharedData_getMiscData FONT_TASK] \
            -size   [SharedData_getMiscData FONT_TASK_SIZE] \
            -weight [SharedData_getMiscData FONT_TASK_STYLE] \
            -slant  [SharedData_getMiscData FONT_TASK_SLANT] \
            -underline [SharedData_getMiscData FONT_TASK_UNDERL]
   }
   return ${labelFont}
}

proc ::DrawUtils::getStatusColor { node_status } {
   ::log::log debug "::DrawUtils::getStatusColor ${node_status}"
   catch { set node_status [SharedData_getRippleStatusMap ${node_status}] }
   switch ${node_status} {
      init -
      begin -
      end -
      abort -
      catchup -
      discret -
      wait -
      submit {
         set key [string toupper COLOR_STATUS_${node_status}]
         set colors [SharedData_getColor ${key}]
      }
      default {
         set colors [SharedData_getColor COLOR_STATUS_UNKNOWN]
      }
   }

   return $colors
}

proc ::DrawUtils::getFgStatusColor { node_status } {
   set colors [getStatusColor ${node_status}]
   set value [lindex ${colors} 0]
   return ${value}
}

proc ::DrawUtils::getBgStatusColor { node_status } {
   set colors [getStatusColor ${node_status}]
   set value [lindex ${colors} 1]
   return ${value}
}

proc ::DrawUtils::getOutlineStatusColor { node_status } {
   set colors [getStatusColor ${node_status}]
   set value [lindex ${colors} 2]
   return ${value}
}

proc ::DrawUtils::clearBranch { exp_path node datestamp canvas { cmd_list "" } } {
   ::log::log debug "clearBranch $canvas $node"
   if { ${cmd_list} != "" } {
      upvar #0 ${cmd_list} evalCmdList
   }

   set pady [SharedData_getMiscData CANVAS_PAD_Y]
   set displayInfo [SharedFlowNode_getDisplayCoords ${exp_path} ${node} ${datestamp}]

   set allBoxInfo [${canvas} bbox all]
   if { $allBoxInfo == "" } {
      return
   }
   
   # I'm adding a small delta on the x and the y to include the current node
   # itself
   set newx1 [expr [lindex ${displayInfo} 0] - 5]
   set newy1 [expr [lindex ${displayInfo} 1] - 5]
   set newx2 [lindex ${allBoxInfo} 2]
   set newy2 [expr [lindex ${displayInfo} 3] + 5]

   set submits [SharedFlowNode_getSubmits ${exp_path} ${node} ${datestamp}]

   # delete submit arrows
   set lineTagName ${node}.submit_tag
   #${canvas} delete ${lineTagName}
   append evalCmdList "${canvas} delete ${lineTagName};"

   foreach submitName ${submits} {
      ::DrawUtils::clearBranch ${exp_path} ${node}/${submitName} ${datestamp} ${canvas}  ${cmd_list}
   }

   #${canvas} delete ${node}
   append evalCmdList "${canvas} delete ${node};"
   # puts "--------------------------------------------- ::DrawUtils::clearBranch end of node:$node ${evalCmdList}"
}

proc ::DrawUtils::getIndexWidgetTag { node } {
   return index_widget_${node}
}

proc ::DrawUtils::getIndexWidgetName { node canvas } {
   set newNode [regsub -all "/" ${node} _]   
   set newNode [regsub -all {[\.]} ${newNode} _]
   set indexListW "${canvas}.[string tolower ${newNode}]"
}

proc ::DrawUtils::clearCanvas { canvas } {
   if { [winfo exists $canvas] } {
      # flush everything in the canvas
      $canvas delete all
   }
   update idletasks
}

# canvas = "" means we draw the status on all canvases that
# the node might appear
proc ::DrawUtils::drawNodeStatus { exp_path node datestamp canvas {shadow_status 0} } {
   variable nodeStatusColorMap
   variable nodeTypeMap
   set type [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}]
   set currentExtension [SharedFlowNode_getNodeExtension ${exp_path} ${node} ${datestamp}]
   set status [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${currentExtension} ]

   # get the icon type of the node
   if [ catch { set imageType $nodeTypeMap($type) } ] {
      error "Invalid node type $type in proc ::DrawUtils::drawNodeStatus()"
      return
   }
   set imageType $nodeTypeMap($type)
   set canvasTag $node.$imageType
   set canvasTextTag $node.text
   set canvasShadowTag $node.shadow
   set colors [::DrawUtils::getStatusColor init]
   catch { set colors [::DrawUtils::getStatusColor $status] }

   ::log::log debug "::DrawUtils::drawNodeStatus node=$node canvasTag=$canvasTag canvasTextTag=$canvasTextTag status=$status font=[lindex $colors 0] fill=[lindex $colors 1]"
   # puts "::DrawUtils::drawNodeStatus node=$node canvasTag=$canvasTag canvasTextTag=$canvasTextTag status=$status font=[lindex $colors 0] fill=[lindex $colors 1]"

   # get the list of all canvases where the node appears
      if { [winfo exists $canvas] } {
         if { $shadow_status == "1" } {
            $canvas itemconfigure $canvasTextTag -fill "black"
            $canvas itemconfigure $canvasTag -fill white
            if { $status == "init" } {
               $canvas itemconfigure $canvasTag -outline [SharedData_getColor NORMAL_RUN_OUTLINE]
               $canvas itemconfigure ${canvasShadowTag} -fill [SharedData_getColor SHADOW_COLOR]
            } else {
               $canvas itemconfigure $canvasTag -outline [lindex $colors 1]
               $canvas itemconfigure ${canvasShadowTag} -fill [lindex $colors 1]
            }
         } else {
            $canvas itemconfigure $canvasTextTag -fill [lindex $colors 0]
            $canvas itemconfigure $canvasTag -fill [lindex $colors 1]
         }
      }
}

proc out {} {
proc ::DrawUtils::drawFamily { node canvas } {
   array set displayInfoList [$node cget -flow.display_infos]
   set displayInfo $displayInfoList($canvas)
   ::log::log debug "drawFamily displayInfo:$displayInfo"
   if {  [$node cget -flow.type] == "family" } {
      set x1 [expr [lindex $displayInfo 1] - 10]
      set x2 [expr [lindex $displayInfo 5] + 10]
      set y1 [expr [lindex $displayInfo 2] - 5]
      set y2 [expr [lindex $displayInfo 6] + 5]
      set color [getNextColor]
      #$canvas create rectangle $x1 $y1 $x2 $y2 \
      #   -dash . -outline "#9eacb3" -fill $color -width 2 -tags "box.$node"
      $canvas create rectangle $x1 $y1 $x2 $y2 \
         -outline "#9eacb3" -fill $color -width 2 -tags "box.$node"
      $canvas lower box.$node
   }
}
}
proc DrawUtils::drawTextBox { exp_path canvas tx1 ty1 text  textfill binder } {
  global NODE_DISPLAY_PREF
  ::log::log debug "DrawUtils::drawTextBox $exp_path $binder l_text:$text"
  set l_txt [split $text "\n"]
  set size   6
  set color  "normal"
  set i      0
 
  if { ${NODE_DISPLAY_PREF} == "Relative Progress" } {
    set i [llength $l_txt]
    if {$i > 1 && [string match *min* [lindex $l_txt end]]} {
      set color [lindex [lindex $l_txt end] end]
      set rpy [expr {$ty1 + $size}]
    }
  }

  if {[lsearch -exact $text ${color}] != "-1"} {
    switch ${color} {
          normal {set text [string map {" normal" ""} ${text}]}
          orange {set text [string map {" orange" ""} ${text}]}
          red    {set text [string map {" red" ""}    ${text}]}
    }
  }
  
  $canvas create text ${tx1} ${ty1} -text $text -fill $textfill \
          -justify center -anchor w -font [::DrawUtils::getBoxLabelFont ${canvas}] -tags "flow_element $binder ${binder}.text"
  if { ${NODE_DISPLAY_PREF} == "Relative Progress" && $color != "normal"} {
     $canvas create rectangle [expr {${tx1}-2}] [expr {$rpy-2}] [expr {$tx1 + $size}] [expr {$rpy + $size}] -fill $color \
            -outline black -tags "flow_element $binder ${binder}.rect"
   }
}
proc ::DrawUtils::drawLosange { exp_path datestamp canvas tx1 ty1 text textfill outline fill binder drawshadow shadowColor} {
   global FLOW_SCALE_${exp_path}_${datestamp} NODE_DISPLAY_PREF

   set flowScale [set FLOW_SCALE_${exp_path}_${datestamp}]
   variable constants
   if { ${flowScale} != "1" } {
      set text "   "
   }

   set newtx1 [expr ${tx1} + 30/${flowScale}]
   set newty1 [expr ${ty1} - 5]
  # $canvas delete ${binder}.rect
   set l_txt [split $text "\n"]
   set size   6
   set color  "normal" 
   set i      0
   set j      0
   set ok     0

   if { ${NODE_DISPLAY_PREF} == "Relative Progress" } {
     set i [llength $l_txt]
     while {$j < $i && !$ok} {
        if {[string match *min* [lindex $l_txt $j]]} {
          set color [lindex [lindex $l_txt $j] end]
          set rpy   [expr {$newty1 + $i }]
          set ok  1
        }
        incr j
     }
   }
 
   if {[lsearch -exact $text ${color}] != "-1"} {
       switch ${color} {
          normal {set text [string map {" normal" ""} ${text}]}
          orange {set text [string map {" orange" ""} ${text}]}
          red    {set text [string map {" red" ""}    ${text}]}
       }
   } 
  
   $canvas create text ${newtx1} ${ty1} -text $text -fill $textfill \
      -justify center -anchor w -font [::DrawUtils::getBoxLabelFont ${canvas}] -tags "flow_element $binder ${binder}.text"
   if {$color != "normal"} {  
      $canvas create rectangle [expr {${newtx1}-2}] [expr {$rpy-2}] [expr {$newtx1 + $size}] [expr {$rpy + $size}] -fill $color \
              -outline black -tags "flow_element $binder ${binder}.rect"
   }

   #    
   #
   #        x2,y2     x3,y3
   #         --------
   #       /        /
   #      /        /
   #      ---------
   #   x1,y1      x4,y4
   #
   set boxArea [$canvas bbox ${binder}.text]
   set nx1 [expr [lindex $boxArea 0] -30/${flowScale}]
   set nx2 [lindex $boxArea 0]
   set nx3 [expr [lindex $boxArea 2] +30/${flowScale}]
   set nx4 [lindex $boxArea 2]

   set ny1 [expr [lindex $boxArea 3] +5]
   set ny2 [expr [lindex $boxArea 1] -5]
   set ny3 $ny2
   set ny4 $ny1
   $canvas create polygon ${nx1} ${ny1} ${nx2} ${ny2} ${nx3} ${ny3} ${nx4} ${ny4} \
         -outline $outline -fill $fill -tags "flow_element $binder ${binder}.losange"
   set maximX ${nx3}
   set maximY ${ny1}
   set nextY  [expr $ny4 + 5]

   $canvas lower ${binder}.losange ${binder}.text

   if { $drawshadow == "on" } {
       # draw a shadow
       set sx1 [expr $nx1 + 5]
       set sx2 [expr $nx2 + 5]
       set sx3 [expr $nx3 + 5]
       set sx4 [expr $nx4 + 5]
       set sy1 [expr $ny1 + 5]
       set sy2 [expr $ny2 + 5]
       set sy3 [expr $ny3 + 5]
       set sy4 [expr $ny4 + 5]
       $canvas create polygon ${sx1} ${sy1} ${sx2} ${sy2} ${sx3} ${sy3} ${sx4} ${sy4} -width $constants(border_width) \
               -fill $shadowColor  -tags "flow_element ${binder} ${binder}.shadow"
       $canvas lower ${binder}.shadow ${binder}.losange
       set maximX ${sx2}
       set maximY ${sy3}
       set nextY  [expr $sy4 + 10]
   }

   SharedData_setExpDisplayData ${exp_path} ${datestamp} $canvas ${nextY} ${maximX} ${maximY}
   SharedFlowNode_setDisplayCoords ${exp_path} ${binder} ${datestamp} [list $nx1 $ny1 $nx3 $ny3 $nx3 $ny4]

   # this part adds a combo box to hold the index values of a switch node
   if {  [SharedFlowNode_getNodeType ${exp_path} ${binder} ${datestamp}] == "switch_case" } {
      set indexListW [::DrawUtils::getIndexWidgetName ${binder} ${canvas}]
      if { ! [winfo exists ${indexListW}] } {
         ComboBox ${indexListW} -bwlistbox 1 -hottrack 1 -text latest -width 7 \
            -postcommand [list ::DrawUtils::setIndexWidgetStatuses ${exp_path} ${binder} ${datestamp} ${indexListW}]
         ${indexListW} bind <4> [list ComboBox::_unmapliste ${indexListW}]
         ${indexListW} bind <5> [list ComboBox::_mapliste ${indexListW}]
      }

      # only redraw/create index widget window if not already created
      # avoids flickering in the display 
      set indexWidgetTag [::DrawUtils::getIndexWidgetTag ${binder}]
      set indexWidgetCoords  [$canvas coords ${indexWidgetTag}] 
      set barY [expr ${nextY} + 5]
      set barX [expr (${nx1} + ${nx3}) / 2 ]

      if { ${indexWidgetCoords} == "" } {
         pack ${indexListW} -fill both
         $canvas create window $barX $barY -window ${indexListW} -tags "flow_element ${indexWidgetTag}"
      } else {
         set xCoord [lindex ${indexWidgetCoords} 0]
         set yCoord [lindex ${indexWidgetCoords} 1]
         set deltaX [expr ${barX} - ${xCoord}]
         set deltaY [expr ${barY} - ${yCoord}]
         $canvas move $indexWidgetTag $deltaX $deltaY
      }
      if { [winfo height ${indexListW}] == "1" } {
         set nextY [expr $barY + 10]
      } else {
         set nextY [expr $barY + [winfo height ${indexListW}]]
      }
      SharedData_setExpDisplayData ${exp_path} ${datestamp} ${canvas} ${nextY} ${maximX} ${maximY}
   }
}

proc ::DrawUtils::drawOval { exp_path datestamp canvas tx1 ty1 txt maxtext textfill outline fill binder drawshadow shadowColor } {
   global FLOW_SCALE_${exp_path}_${datestamp} NODE_DISPLAY_PREF

   set flowScale [set FLOW_SCALE_${exp_path}_${datestamp}]
   variable constants
   ::log::log debug "drawOval canvas:$canvas txt:$txt textfill:$textfill fill:$fill binder:$binder"
   ::log::log debug "drawOval textfill:$textfill fill:$fill binder:$binder"

   set newtx1 [expr ${tx1} + 10]
   set newty1 $ty1
   set newrpy [expr ${ty1} - 5]
   set l_txt  [split $maxtext "\n"]
   set size   6
   set color  "normal"
   set i      0
   set j      0
   set ok     0

   if { ${NODE_DISPLAY_PREF} == "Relative Progress" } {
     set i [llength $l_txt]
     while {$j < $i && !$ok} {
        if {[string match *min* [lindex $l_txt $j]]} {
          set color [lindex [lindex $l_txt $j] end]
          set rpy   [expr {$newrpy + $i }]
          set ok  1
        }
        incr j
     }
   }
 
   if {[lsearch -exact $maxtext ${color}] != "-1"} {
       switch ${color} {
          normal {set maxtext [string map {" normal" ""} ${maxtext}]}
          orange {set maxtext [string map {" orange" ""} ${maxtext}]}
          red    {set maxtext [string map {" red" ""}    ${maxtext}]}
       }
   } 
   $canvas create text ${newtx1} ${newty1} -text $maxtext -fill $textfill \
      -justify center -anchor w -font [::DrawUtils::getBoxLabelFont ${canvas}] -tags "flow_element $binder ${binder}.text"
   if {$color != "normal"} {  
      $canvas create rectangle [expr {${newtx1}-2}] [expr {$rpy-2}] [expr {$newtx1 + $size}] [expr {$rpy + $size}] -fill $color \
             -outline black -tags "flow_element $binder ${binder}.rect"
   }
   set boxArea [$canvas bbox ${binder}.text]
   #$canvas itemconfigure ${binder}.text -text $txt

   set ovalSize [SharedData_getMiscData LOOP_OVAL_SIZE]
   set nx1 [expr [lindex $boxArea 0] - ${ovalSize}]
   set ny1 [expr [lindex $boxArea 1] - ${ovalSize}/${flowScale}]
   set nx2 [expr [lindex $boxArea 2] + ${ovalSize}]
   set ny2 [expr [lindex $boxArea 3] + ${ovalSize}/${flowScale}]
   set nextY ${ny2}
   
   $canvas create oval ${nx1} ${ny1} ${nx2} ${ny2}  \
          -fill $fill -tags "flow_element $binder ${binder}.oval"

   $canvas lower ${binder}.oval ${binder}.text

   if { $drawshadow == "on" } {
      # draw a shadow
      set sx1 [expr $nx1 + 5]
      set sx2 [expr $nx2 + 5]
      set sy1 [expr $ny1 + 5]
      set sy2 [expr $ny2 + 5]
      set nextY  [expr $sy2 + 10]
      $canvas create oval ${sx1} ${sy1} ${sx2} ${sy2} -width 0 \
            -fill $shadowColor  -tags "flow_element ${binder} ${binder}.shadow"
      $canvas lower ${binder}.shadow ${binder}.oval
      SharedData_setExpDisplayData ${exp_path} ${datestamp} ${canvas} ${nextY} ${sx2} ${sy2}
      set maxX ${sx2}
      set maxY ${sy2}
   } else {
      SharedData_setExpDisplayData ${exp_path} ${datestamp} ${canvas} ${nextY} ${nx2} ${ny2}
      set maxX ${nx2}
      set maxY ${ny2}
   }

   SharedFlowNode_setDisplayCoords ${exp_path} ${binder} ${datestamp} [list $nx1 $ny1 $nx2 $ny2 $nx2 $ny2]

   # this part adds a combo box to hold the index values of a loop node
   if {  [SharedFlowNode_getNodeType ${exp_path} ${binder} ${datestamp}] == "loop" } {
      set indexListW [::DrawUtils::getIndexWidgetName ${binder} ${canvas}]
      if { ! [winfo exists ${indexListW}] } {
         ComboBox ${indexListW} -bwlistbox 1 -hottrack 1 -text latest -values {latest} -width 7 \
            -postcommand [list ::DrawUtils::setIndexWidgetStatuses ${exp_path} ${binder} ${datestamp} ${indexListW}]
         ${indexListW} bind <4> [list ComboBox::_unmapliste ${indexListW}]
         ${indexListW} bind <5> [list ComboBox::_mapliste ${indexListW}]

      }

      set indexWidgetTag [::DrawUtils::getIndexWidgetTag ${binder}]
      set indexWidgetCoords  [$canvas coords ${indexWidgetTag}] 
      set barY [expr ${maxY} + 15]
      set barX [expr ($nx1 + $nx2)/2]
      set maxY ${barY}

      # only redraw/create index widget window if not already created
      # avoids flickering in the display 
      if { ${indexWidgetCoords} == "" } {
         pack ${indexListW} -fill both
         $canvas create window $barX $barY -window ${indexListW} -tags "flow_element ${indexWidgetTag}"
      } else {
         set xCoord [lindex ${indexWidgetCoords} 0]
         set yCoord [lindex ${indexWidgetCoords} 1]
         set deltaX [expr ${barX} - ${xCoord}]
         set deltaY [expr ${barY} - ${yCoord}]
         $canvas move $indexWidgetTag $deltaX $deltaY
      }

      if { [winfo height ${indexListW}] == "1" } {
         set nextY [expr $barY + 20]
      } else {
         set nextY [expr $barY + [winfo height ${indexListW}]]
      }
      SharedData_setExpDisplayData ${exp_path} ${datestamp} ${canvas} ${nextY} ${maxX} ${maxY}
   }
}

proc ::DrawUtils::showIndexWidget { node index_widget } {
   ${index_widget} bind <4> [list ComboBox::_unmapliste ${index_widget}]
}

# this function is called to populate the loop node listbox will
# all the loop indexes... This is ONLY called when the user is attempting
# to view the listbox items
proc ::DrawUtils::setIndexWidgetStatuses { exp_path node datestamp index_widget } {
   variable nodeStatusColorMap
   variable nodeTypeMap

   set nodeType [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}]
   switch ${nodeType} {
      npass_task {
         set extensions [SharedFlowNode_getNptExtensions ${exp_path} ${node} ${datestamp}]
      }
      switch_case {
         set extensions [SharedFlowNode_getSwitchingExtensions ${exp_path} ${node} ${datestamp}]
      }
      loop {
         set extensions [SharedFlowNode_getLoopExtensions ${exp_path} ${node} ${datestamp}]
      }
   }

   set extensions [linsert ${extensions} 0 latest]

   # assign the extensions to the widget
   ${index_widget} configure -values ${extensions}

   set listboxW [${index_widget} getlistbox]

   bind ${listboxW}  <4> [list ${listboxW} yview scroll -1 units]
   bind ${listboxW}  <5> [list ${listboxW} yview scroll +1 units]

   # Utils_bindMouseWheel ${listboxW} 3
   set maxItemLength [string length latest]

   set index 0
   set parentExt [SharedFlowNode_getParentLoopExt ${exp_path} ${node} ${datestamp}]
   # we through each extension and set the extension status color
   # in the listbox widget
   foreach ext ${extensions} {
      if { [expr [string length ${ext}] > ${maxItemLength}] } {   
         set maxItemLength [string length ${ext}]
      }
      set indexStatusImg [::DrawUtils::getStatusImage init]
      if { ${ext} != "latest" } {
         if { ${parentExt} == "" } {
            # got no loops
            # need to get status of every iteration
            set extStatus [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} +${ext}]
         } elseif { ${parentExt} == "latest" } {
            # parent loop set to latest but current loop set to a specific iteration
            # all our iteration should be in init state...
            set extStatus init
         } else {
            # parent has loop iteration set, every iteration is relative to parent one
            set extStatus [SharedFlowNode_getMemberStatus ${exp_path} ${node} ${datestamp} ${parentExt}+${ext}]
         }

         set indexStatusImg [::DrawUtils::getStatusImage ${extStatus}]
         ${listboxW} itemconfigure ${index} -image ${indexStatusImg}
      }
      incr index
   }

   set currentExt [SharedFlowNode_getCurrentExt ${exp_path} ${node} ${datestamp}]
   if { ${currentExt} != "" && ${currentExt} != "latest" } {
      set currentValue [SharedFlowNode_getIndexValue ${currentExt}]
      set currentValueIndex [lsearch ${extensions} ${currentValue}]
      # this is the format of the call of Bwidget combox to set a value for
      # a specific index
      ${index_widget} setvalue @${currentValueIndex}
   } else {
      ${index_widget} setvalue first
   }
   set listLength [llength ${extensions}]
   set desiredWidth [expr ${maxItemLength} + 3]
   if { ${listLength} > 10 } {
      ${index_widget} configure -height 10 -width ${desiredWidth}
   } else {
      ${index_widget} configure -height ${listLength} -width ${desiredWidth}
   }
}

proc ::DrawUtils::drawline { canvas x1 y1 x2 y2 arrow fill drawshadow shadowColor {tag_name ""} } {
    ::log::log debug "drawline canvas:$canvas x1:$x1 y1:$y1 x2:$x2 y2:$y2"

    if { $x1 < $x2 } {
      set x2 [expr $x2 - 2 ]

      #set shadow values
      set sx1 [expr $x1 + 1 ]
      set sx2 $x2
      set sy1 [expr $y1 + 1 ]
      set sy2 $sy1
    } else {
      
      #set shadow values
      set sx1 [expr $x1 + 1]
      set sx2 $sx1
      set sy1 [expr $y1 + 1]
      set sy2 [expr $y2 + 2]
    }
    if { $drawshadow == "on" } {
      # draw shadow
      if { ${tag_name} == "" } {
         $canvas create line ${sx1} ${sy1} ${sx2} ${sy2} -width 1.0 -arrow $arrow -fill $shadowColor
      } else {
         $canvas create line ${sx1} ${sy1} ${sx2} ${sy2} -width 1.0 -arrow $arrow -fill $shadowColor -tags ${tag_name}
      }
    }

    # draw line
   if { ${tag_name} == "" } {
      $canvas create line ${x1} ${y1} ${x2} ${y2} -width 1.0 -arrow $arrow -fill $fill
   } else {
      $canvas create line ${x1} ${y1} ${x2} ${y2} -width 1.0 -arrow $arrow -fill $fill -tags ${tag_name}
   }

}

proc ::DrawUtils::drawdashline { canvas x1 y1 x2 y2 arrow fill drawshadow shadowColor {tag_name ""}} {
    ::log::log debug "drawline canvas:$canvas x1:$x1 y1:$y1 x2:$x2 y2:$y2"

    if { $x1 < $x2 } {
      set x2 [expr $x2 - 3 ]

      #set shadow values
      set sx1 [expr $x1 + 1 ]
      set sx2 $x2
      set sy1 [expr $y1 + 1 ]
      set sy2 $sy1
    } else {
      
      #set shadow values
      set sx1 [expr $x1 + 1]
      set sx2 $sx1
      set sy1 [expr $y1 + 1]
      set sy2 $y2
    }

    if { $drawshadow == "on" } {
      # draw shadow
      if { ${tag_name} == "" } {
         $canvas create line ${sx1} ${sy1} ${sx2} ${sy2} -width 1.0 -arrow $arrow -fill $shadowColor -dash { 4 3 }
      } else {
         $canvas create line ${sx1} ${sy1} ${sx2} ${sy2} -width 1.0 -arrow $arrow -fill $shadowColor -dash { 4 3 } -tags ${tag_name}
      }
    }

   # draw line
   if { ${tag_name} == "" } {
      $canvas create line ${x1} ${y1} ${x2} ${y2} -width 1.0 -arrow $arrow -fill $fill -dash { 4 3 }
   } else {
      $canvas create line ${x1} ${y1} ${x2} ${y2} -width 1.0 -arrow $arrow -fill $fill -dash { 4 3 } -tags ${tag_name}
   }
}

proc ::DrawUtils::drawBoxSansOutline { exp_path datestamp canvas tx1 ty1 text maxtext textfill outline fill binder drawshadow shadowColor } {
   global FLOW_SCALE_${exp_path}_${datestamp}
   set flowScale [set FLOW_SCALE_${exp_path}_${datestamp}]
   variable constants
   ::log::log debug "drawBoxSaneoutline canvas:$canvas text:$text ty1=$ty1 fill=$fill binder:$binder"
   set pad 5
   if { ${flowScale} != "1" } {
      set text "/ "
      set maxtext ${text}
      set pad 0
   } else {
      set text /$maxtext
   }
  
   DrawUtils::drawTextBox  ${exp_path} ${canvas} ${tx1} ${ty1} ${text}  ${textfill} ${binder}

   # draw a box around the text
   set boxArea [$canvas bbox ${binder}.text]

   set nx1 [expr [lindex $boxArea 0] - ${pad}]
   set ny1 [expr [lindex $boxArea 1] - ${pad}]
   set nx2 [expr [lindex $boxArea 2] + ${pad} + 5]
   set ny2 [expr [lindex $boxArea 3] + ${pad}]
   set nextY ${ny2}

   ::log::log debug "drawBoxSansOutline text=$text nx1=$nx1 ny1=$ny1 nx2=$nx2 ny2=$ny2"
   $canvas create rectangle ${nx1} ${ny1} ${nx2} ${ny2} \
           -fill $fill -tags "flow_element $binder ${binder}.rectangle" 
   $canvas lower ${binder}.rectangle ${binder}.text

   if { $drawshadow == "on" } {
      # draw a shadow
      set sx1 [expr $nx1 + ${pad}]
      set sx2 [expr $nx2 + ${pad}]
      set sy1 [expr $ny1 + ${pad}]
      set sy2 [expr $ny2 + ${pad}]
      $canvas create rectangle ${sx1} ${sy1} ${sx2} ${sy2} -width 0 \
            -fill $shadowColor  -tags "flow_element ${binder} ${binder}.shadow"
      $canvas lower ${binder}.shadow ${binder}.rectangle
      SharedData_setExpDisplayData ${exp_path} ${datestamp} ${canvas} ${nextY} ${sx2} ${sy2}
   } else {
      SharedData_setExpDisplayData ${exp_path} ${datestamp} ${canvas} ${nextY} ${nx2} ${ny2}
   }

   SharedFlowNode_setDisplayCoords ${exp_path} ${binder} ${datestamp} [list $nx1 $ny1 $nx2 $ny2 $nx2 $ny2]
}

proc ::DrawUtils::drawBox { exp_path datestamp canvas tx1 ty1 text maxtext textfill outline fill binder drawshadow shadowColor } {
   global FLOW_SCALE_${exp_path}_${datestamp}
   variable constants
   set flowScale [set FLOW_SCALE_${exp_path}_${datestamp}]
   ::log::log debug "drawBox canvas:$canvas text:$text textfill=$textfill outline=$outline fill=$fill binder:$binder"
   if { ${flowScale} != "1" && [SharedFlowNode_getNodeType ${exp_path} ${binder} ${datestamp}]  != "npass_task" } {
      set text "   "
      set maxtext ${text}
      set padx 5
      set pady 0
   } else {
      set padx 5
      set pady 5
      set text /$maxtext
   }
   DrawUtils::drawTextBox  ${exp_path} ${canvas} ${tx1} ${ty1} ${maxtext}  ${textfill} ${binder}

   # draw a box around the text
   set boxArea [$canvas bbox ${binder}.text]

   set nx1 [expr [lindex $boxArea 0] - ${padx}]
   set ny1 [expr [lindex $boxArea 1] - ${pady}]
   set nx2 [expr [lindex $boxArea 2] + ${padx}]
   set ny2 [expr [lindex $boxArea 3] + ${pady}]
   set nextY ${ny2}
   $canvas create rectangle ${nx1} ${ny1} ${nx2} ${ny2} \
            -fill $fill -outline $outline -tags "flow_element $binder ${binder}.rectangle"
   $canvas lower ${binder}.rectangle ${binder}.text

   if { $drawshadow == "on" } {
       # draw a shadow
       set sx1 [expr $nx1 + ${padx}]
       set sx2 [expr $nx2 + ${pady}]
       set sy1 [expr $ny1 + ${padx}]
       set sy2 [expr $ny2 + ${pady}]
       $canvas create rectangle ${sx1} ${sy1} ${sx2} ${sy2} -width 0 \
               -fill $shadowColor  -tags "flow_element ${binder} ${binder}.shadow"
       $canvas lower ${binder}.shadow ${binder}.rectangle
      SharedData_setExpDisplayData ${exp_path} ${datestamp} ${canvas} ${nextY} ${sx2} ${sy2}
      set maxX ${sx2}
      set maxY ${sy2}
   } else {
      set maxX ${nx2}
      set maxY ${ny2}
      SharedData_setExpDisplayData ${exp_path} ${datestamp} ${canvas} ${nextY} ${nx2} ${ny2}
   }

   SharedFlowNode_setDisplayCoords ${exp_path} ${binder} ${datestamp} [list $nx1 $ny1 $nx2 $ny2 $nx2 $ny2]
}

proc DrawUtils::drawRoundBox { exp_path datestamp canvas tx1 ty1 text maxtext textfill outline fill binder drawshadow shadowColor } {
   
   DrawUtils::drawTextBox  ${exp_path} ${canvas} ${tx1} ${ty1} ${maxtext}  ${textfill} ${binder}
 
   set shadowOffset [SharedData_getMiscData CANVAS_SHADOW_OFFSET]
   # draw a box around the text
   set boxArea [$canvas bbox ${binder}.text]
   set radius 45

   set nx1 [expr [lindex $boxArea 0] -5]
   set ny1 [expr [lindex $boxArea 1] -5]
   set nx2 [expr [lindex $boxArea 2] +5]
   set ny2 [expr [lindex $boxArea 3] +5]
   set nextY ${ny2}
   set maxX ${nx2}
   set maxY ${ny2}

   $canvas create arc [expr ${nx1} - 4] [expr ${ny1} + 2] [expr ${nx1} + 10] [expr ${ny2} -2] -extent 180 -start 90 -fill ${fill} -outline ${outline} -tag "flow_element ${binder} ${binder}.arc"
   DrawUtils::roundRect ${canvas} ${nx1} ${ny1} ${nx2} ${ny2} ${radius} -fill $fill -outline ${outline} -tags "flow_element $binder ${binder}.arc"

   ${canvas} lower ${binder}.arc ${binder}.text

   if { $drawshadow == "on" } {
       # draw a shadow
       set sx1 [expr $nx1 + ${shadowOffset}]
       set sx2 [expr $nx2 + ${shadowOffset}]
       set sy1 [expr $ny1 + ${shadowOffset}]
       set sy2 [expr $ny2 + ${shadowOffset}]
       DrawUtils::roundRect $canvas ${sx1} ${sy1} ${sx2} ${sy2} ${radius} \
               -fill $shadowColor  -tags "flow_element ${binder} ${binder}.shadow"
       $canvas lower ${binder}.shadow ${binder}.arc
      set maxX ${sx2}
      set maxY ${sy2}
   }

   SharedFlowNode_setDisplayCoords ${exp_path} ${binder} ${datestamp} [list $nx1 $ny1 $nx2 $ny2 $nx2 $ny2]

   set indexListW [::DrawUtils::getIndexWidgetName ${binder} ${canvas}]
   if { ! [winfo exists ${indexListW}] } {
      ComboBox ${indexListW} -bwlistbox 1 -hottrack 1 -values {latest} -text latest -width 7 \
         -postcommand [list ::DrawUtils::setIndexWidgetStatuses ${exp_path} ${binder} ${datestamp} ${indexListW}]
      ${indexListW} bind <4> [list ComboBox::_unmapliste ${indexListW}]
      ${indexListW} bind <5> [list ComboBox::_mapliste ${indexListW}]
   }

   set indexWidgetTag [::DrawUtils::getIndexWidgetTag ${binder}]
   set indexWidgetCoords  [$canvas coords ${indexWidgetTag}] 
   set barY [expr ${maxY} + 15]
   set barX ${nx1}
   set maxY ${barY}

   # only redraw/create index widget window if not already created
   # avoids flickering in the display 
      if { ${indexWidgetCoords} == "" } {
      pack ${indexListW} -fill both
      $canvas create window $barX $barY -window  ${indexListW} -tags "flow_element ${indexWidgetTag}" -anchor w
   } else {
         set xCoord [lindex ${indexWidgetCoords} 0]
         set yCoord [lindex ${indexWidgetCoords} 1]
         set deltaX [expr ${barX} - ${xCoord}]
         set deltaY [expr ${barY} - ${yCoord}]
         $canvas move $indexWidgetTag $deltaX $deltaY
   }

   if { [winfo height ${indexListW}] == "1" } {
      set nextY [expr $barY + 20]
   } else {
      set nextY [expr $barY + [winfo height ${indexListW}]]
   }
   SharedData_setExpDisplayData ${exp_path} ${datestamp} ${canvas} ${nextY} ${maxX} ${maxY}
}

# got from the web pasting it as is
proc DrawUtils::roundRect { w x0 y0 x3 y3 radius args } {

    set r [winfo pixels $w $radius]
    set d [expr { 2 * $r }]

    # Make sure that the radius of the curve is less than 3/8
    # size of the box!

    set maxr 0.75

    if { $d > $maxr * ( $x3 - $x0 ) } {
        set d [expr { $maxr * ( $x3 - $x0 ) }]
    }
    if { $d > $maxr * ( $y3 - $y0 ) } {
        set d [expr { $maxr * ( $y3 - $y0 ) }]
    }

    set x1 [expr { $x0 + $d }]
    set x2 [expr { $x3 - $d }]
    set y1 [expr { $y0 + $d }]
    set y2 [expr { $y3 - $d }]

    set cmd [list $w create polygon]
    lappend cmd $x0 $y0
    lappend cmd $x1 $y0
    lappend cmd $x2 $y0
    lappend cmd $x3 $y0
    lappend cmd $x3 $y1
    lappend cmd $x3 $y2
    lappend cmd $x3 $y3
    lappend cmd $x2 $y3
    lappend cmd $x1 $y3
    lappend cmd $x0 $y3
    lappend cmd $x0 $y2
    lappend cmd $x0 $y1
    lappend cmd -smooth 1
    return [eval $cmd $args]
 }

proc ::DrawUtils::pointNode { exp_path datestamp node {canvas ""} } {
   ::log::log debug "::DrawUtils::pointNode exp_path:${exp_path} node:${node}"
   set canvasList ${canvas}
   if { ${canvas} == "" } {
      set canvasList [SharedData_getExpCanvasList ${exp_path} ${datestamp}]
   }
   foreach canvasW ${canvasList} {
      set newcords [${canvasW} bbox ${node}.text]
   
      if { [string length $newcords] == 0 } {
         ::log::log debug "::DrawUtils::pointNode can't find node:${node}"
         return 0
      }
      # the "target"s are the top-left and bottom-right
      # coordinates for the job box
      set target_x  [expr round([lindex $newcords 0]) - 5]
      set target_y  [expr round([lindex $newcords 1]) - 5]
      set target_x2 [expr round([lindex $newcords 2]) + 5]
      set target_y2 [expr round([lindex $newcords 3]) + 5]
   
      set x_offset 25
      set y_offset 25

      set searchTag ${canvasW}searchlines

      # draw four lines with arrows pointing at the job
      ${canvasW} create line $target_x $target_y [expr $target_x - $x_offset] \
      [expr $target_y - $y_offset] -arrow first -width 2m -tag ${searchTag} -fill black
      ${canvasW} create line $target_x2 $target_y [expr $target_x2 + $x_offset] \
      [expr $target_y - $y_offset] -arrow first -width 2m -tag ${searchTag} -fill black
      ${canvasW} create line $target_x $target_y2 [expr $target_x - $x_offset] \
      [expr $target_y2 + $y_offset] -arrow first -width 2m -tag ${searchTag} -fill black
      ${canvasW} create line $target_x2 $target_y2 [expr $target_x2 + $x_offset] \
      [expr $target_y2 + $y_offset] -arrow first -width 2m -tag ${searchTag} -fill black

      ::DrawUtils::viewCanvasItem ${canvasW} ${searchTag}
      raise [winfo toplevel ${canvasW}]
      # after a few seconds, delete the lines pointing at the job
      after 8000 [list ::DrawUtils::delPointNode ${canvasW}]
   }
}

proc ::DrawUtils::pointOverviewExp { exp_path datestamp canvasW expSearchTag } {

   ::log::log debug "::DrawUtils::pointOverviewNode exp_path:${exp_path} datestamp:${datestamp}"

      set newcords [${canvasW} bbox ${expSearchTag}]
   
      if { [string length $newcords] == 0 } {
         ::log::log debug "::DrawUtils::pointOverviewExp can't find Exp:${exp_path} Datestamp:${datestamp}"
         return 0
      }

      # the "target"s are the top-left and bottom-right
      # coordinates for the job box
      set target_x  [expr round([lindex $newcords 0]) - 5]
      set target_y  [expr round([lindex $newcords 1]) - 5]
      set target_x2 [expr round([lindex $newcords 2]) + 5]
      set target_y2 [expr round([lindex $newcords 3]) + 5]
   
      set x_offset 25
      set y_offset 25

      set searchTag ${canvasW}searchlines

      # draw four lines with arrows pointing at the job
      ${canvasW} create line $target_x $target_y [expr $target_x - $x_offset] \
      [expr $target_y - $y_offset] -arrow first -width 2m -tag ${searchTag} -fill black
      ${canvasW} create line $target_x2 $target_y [expr $target_x2 + $x_offset] \
      [expr $target_y - $y_offset] -arrow first -width 2m -tag ${searchTag} -fill black
      ${canvasW} create line $target_x $target_y2 [expr $target_x - $x_offset] \
      [expr $target_y2 + $y_offset] -arrow first -width 2m -tag ${searchTag} -fill black
      ${canvasW} create line $target_x2 $target_y2 [expr $target_x2 + $x_offset] \
      [expr $target_y2 + $y_offset] -arrow first -width 2m -tag ${searchTag} -fill black

      ::DrawUtils::viewCanvasItem ${canvasW} ${searchTag}
      raise [winfo toplevel ${canvasW}]
      # after a few seconds, delete the lines pointing at the job
      after 8000 [list ::DrawUtils::delPointNode ${canvasW}]
}

# search down the node tree for nodes in position 0 relative
# to the current node that might require more space than
# usual ones Example loop. Used mainly to know where to draw the first
# node of a branch
proc ::DrawUtils::getLineDeltaSpace { exp_path node datestamp display_pref {delta_value 0} } {
   global FLOW_SCALE_${exp_path}_${datestamp}
   ::log::log debug "::DrawUtils::getLineDeltaSpace ${exp_path} ${node} display_pref:$display_pref delta_value: $delta_value"
   set value ${delta_value}
   set flowScale [set FLOW_SCALE_${exp_path}_${datestamp}]
   # I only need to calculate extra space if the current node is not in position 0
   # in it's parent node. If it is in position 0, the extra space has already been calculated.

   set origNode ${node}
   if { [SharedFlowNode_getSubmitPosition ${exp_path} ${node} ${datestamp}] != 0 } {
      set done 0
      while { ! ${done} } {
         set nodeType [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}]
	 switch ${nodeType} {
	    loop {
	       set loopSize [SharedData_getMiscData LOOP_OVAL_SIZE]
               if { [expr ${value} < ${loopSize}] } {
                  set value ${loopSize}
               }
	    }
	    npass_task {
               if { [expr ${value} < 5] && ${flowScale} != "1" } { set value 5 }
	    }
	    module {
	       set moduleName [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} name]
               set moduleLocalName [SharedFlowNode_getGenericAttribute ${exp_path} ${node} ${datestamp} local_name]
               if { ${moduleName} != ${moduleLocalName} &&  [expr ${value} < 5 ] } {
	          set value 5
	          if { ${display_pref} != "normal" && [expr ${value} < 8] } {
		     set value 8
		  }
               }
	    }
	    default {
	       if { ${display_pref} != "normal" && [ expr ${value} < 5 ] } {
                  set value 5
               }
	    }
         }

         set submits [SharedFlowNode_getSubmits ${exp_path} ${node} ${datestamp}]
         # i'm only interested in the first position of the child list, the others will be calculated
         # when we move down the tree
         set submitName [lindex ${submits} 0]
      
         if { ${submitName} != "" } {
            # move further down the tree
            set node ${node}/${submitName}
         } else {
            set done 1
         }
      }
   }

      ::log::log debug "::DrawUtils::getLineDeltaSpace ----------------------- ${exp_path} ${origNode} display_pref:$display_pref delta_value: $value"

   return $value
}

proc ::DrawUtils::getNodeDeltaX { exp_path node datestamp canvas } {
   set deltax 0
   # puts "::DrawUtils::getNodeDeltaX SharedFlowNode_getNodeType ${exp_path} ${node}"
   if { [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}] == "npass_task" } {
      set indexListW [::DrawUtils::getIndexWidgetName ${node} ${canvas}]
      foreach { px1 py1 px2 py2 } [SharedFlowNode_getDisplayCoords ${exp_path} ${node} ${datestamp}] {break}
      # foreach { nx1 ny1 nx2 ny2 } [${canvas} bbox ${node}.index_widget] { break }
      foreach { nx1 ny1 nx2 ny2 } [${canvas} bbox index_widget_${node}] { break }
      if { ${nx2} > ${px2} } {
         set deltax [expr ${nx2} - ${px2}]
      }
   }
   return ${deltax}
}

proc  ::DrawUtils::delPointNode { canvas } {

    if { [winfo exists $canvas] } {
        $canvas delete ${canvas}searchlines
    }
}

proc ::DrawUtils::initStatusImages {} {
   set dummyImg [image create photo -width 17 -height 9]
   foreach status [list begin init submit abort end catchup wait discret] {
      set statusImage .${status}_set_image
      global STATUS_IMG_${status}
      set imageDir [SharedData_getMiscData IMAGE_DIR]
      if { ! [info exists STATUS_IMG_${status}] } {
         if { [SharedData_getColor [string toupper COLOR_STATUS_${status}]] == [SharedData_getColor [string toupper ORIG_COLOR_STATUS_${status}]] } {
	    # load from predefined images
            set STATUS_IMG_${status} [image create photo ${statusImage} -file ${imageDir}/status_${status}_icon.ppm]
	 } else {
	    # user defined colors... generate on the fly
            set bgColor [::DrawUtils::getBgStatusColor $status]
            set STATUS_IMG_${status} [image create photo ${statusImage} -height 9 -width 17 -data [${dummyImg} data -background ${bgColor} -format ppm]]
         }
      }
   }
   image delete ${dummyImg}
}

proc ::DrawUtils::getStatusImage { status } {
   set statusImage .${status}_set_image
   global STATUS_IMG_${status}

   return ${statusImage}
}

proc ::DrawUtils::highLightNode { exp_path node datestamp canvas_w } {
   global NodeHighLightRestoreCmd_${exp_path}_${datestamp}
   variable nodeTypeMap

   set type [SharedFlowNode_getNodeType ${exp_path} ${node} ${datestamp}] 
   set imageType $nodeTypeMap($type)
   set canvasTag $node.$imageType

   set selectColor [SharedData_getColor SELECT_BG]
   set currentWidth [${canvas_w} itemcget ${canvasTag} -width ]
   set currentOutline [${canvas_w} itemcget ${canvasTag} -outline]
   ${canvas_w} itemconfigure ${canvasTag} -width 2 -outline ${selectColor}
   set NodeHighLightRestoreCmd_${exp_path}_${datestamp} "${canvas_w} itemconfigure ${canvasTag} -width ${currentWidth} -outline ${currentOutline}"
}

# highlights a node that is selected with the find functionality
# by drawing a yellow rectangle around the node
proc ::DrawUtils::highLightFindNode { _exp_path _datestamp _node _canvas_w } {
   global NodeHighLightRestoreCmd_${_exp_path}_${_datestamp}
   variable nodeTypeMap

   set nodeShadowTag ${_node}.shadow
   set selectColor [SharedData_getColor FLOW_FIND_SELECT]

   # create a rectangle around the node
   foreach {x1 y1 x2 y2} [${_canvas_w} bbox ${_node}] {break}
   set findBoxDelta 5
   set x1 [expr ${x1} - ${findBoxDelta}]
   set y1 [expr ${y1} - ${findBoxDelta}]
   set x2 [expr ${x2} + ${findBoxDelta}]
   set y2 [expr ${y2} + ${findBoxDelta}]

   set selectTag ${_canvas_w}.find_select
   ${_canvas_w} create rectangle ${x1} ${y1} ${x2} ${y2} -fill ${selectColor} -tag ${selectTag}
   ${_canvas_w} lower ${selectTag} ${_node}

   # sets the command to restore the node to its previous state
   set NodeHighLightRestoreCmd_${_exp_path}_${_datestamp} "${_canvas_w} delete ${selectTag};"
   return ${selectTag}
}

# returns the visible area of the canvas
proc ::DrawUtils::getCanvasViewArea { _canvas } {

   # This foreach is used only as a "list assign", and has an empty body.
   foreach {junk junk totalXArea totalYArea} [${_canvas} cget -scrollregion] {break}
   set xview  [${_canvas} xview]
   set yview  [${_canvas} yview]

   set xstart [expr {int([lindex $xview 0] * $totalXArea)}]
   set xend   [expr {int([lindex $xview 1] * $totalXArea)}] 

   set ystart [expr {int([lindex $yview 0] * $totalYArea)}]
   set yend   [expr {int([lindex $yview 1] * $totalYArea)}] 

   return [list $xstart $ystart $xend $yend]
}

# move the item referenced by _tag to a visible area if it is not
# visible within the current scroll area
proc ::DrawUtils::viewCanvasItem { _canvas _tag } {
   foreach {x1 y1 x2 y2} [${_canvas} bbox ${_tag}] break
   #set y1 [expr $y1 - 10]
   #set x1 [expr $x1 - 10]

   if { ${y1} < 0 } {
      set y1 0
   }
   foreach {vx1 vy1 vx2 vy2} [::DrawUtils::getCanvasViewArea ${_canvas}] break
   foreach {sx1 sy1 sx2 sy2} [${_canvas} cget -scrollregion] break

    if { ! ( ${x1} >= ${vx1} && ${x2} <= ${vx2} && ${y1} >= ${vy1} && ${y2} <= ${vy2} ) } {
      # item is not within visible area
      set xfraction [expr {double($x1 - $sx1) / ($sx2 - $sx1)}]
      set yfraction [expr {double($y1 - $sy1) / ($sy2 - $sy1)}]
      ${_canvas} xview moveto $xfraction
      ${_canvas} yview moveto $yfraction
    }
}
