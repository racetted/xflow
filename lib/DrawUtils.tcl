package provide DrawUtils 1.0
package require Tk
package require FlowNodes
#package require Tix
package require tile
package require BWidget 1.9

#namespace delete ::DrawUtils

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
   variable hostColorMap
   variable constants
   variable rippleStatusMap

   array set nodeTypeMap {
      family rectangle
      module rectangle
      task rectangle
      npass_task rectangle
      loop oval
      outlet oval
      case losange
   }

   array set hostColorMap {
      castor "cornflowerblue"
      ib "cyan1"
      naos "IndianRed4"
      maia "IndianRed2"
      pollux "Sandybrown"
      unknown "black"
   }

   array set rippleStatusMap {
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

   array set constants {
      border_width "3"
   }
}

proc ::DrawUtils::getStatusColor { node_status } {
   DEBUG "::DrawUtils::getStatusColor ${node_status}" 5
   catch { set node_status $::DrawUtils::rippleStatusMap(${node_status}) }
   switch ${node_status} {
      init -
      begin -
      end -
      abort -
      catchup -
      discret -
      wait -
      submit {
         set key STATUS_${node_status}
         set colors [SharedData_getColor ${key}]
      }
      default {
         set colors [SharedData_getColor STATUS_unknown]
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

proc ::DrawUtils::clearBranch { canvas node { cmd_list "" } } {
   DEBUG "clearBranch $canvas $node" 5
   if { ${cmd_list} != "" } {
      upvar #0 ${cmd_list} evalCmdList
   }

   set pady [SharedData_getMiscData CANVAS_PAD_Y]
   set displayInfo [::FlowNodes::getDisplayCoords ${node} ${canvas}]

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

   set children [$node cget -flow.children]

   proc out {} {
      set indexListW ""
      if { [$node cget -flow.type] == "npass_task" || [$node cget -flow.type] == "loop" } {
         set indexListW [::DrawUtils::getIndexWidgetName ${node} ${canvas}]
         destroy ${indexListW}
         append evalCmdList "destroy ${indexListW};"
      }

      set tags [${canvas} find enclosed ${newx1} ${newy1} ${newx2} ${newy2}]
      foreach tagItem ${tags} {
         ${canvas} delete ${tagItem}
      }
   }

   # delete submit arrows
   set lineTagName ${node}.submit_tag
   #${canvas} delete ${lineTagName}
   append evalCmdList "${canvas} delete ${lineTagName};"

   set children [$node cget -flow.children]
   foreach child ${children} {
      ::DrawUtils::clearBranch ${canvas} ${node}/${child} ${cmd_list}
   }

   #${canvas} delete ${node}
   append evalCmdList "${canvas} delete ${node};"
   # puts "--------------------------------------------- ::DrawUtils::clearBranch end of node:$node ${evalCmdList}"
}

proc ::DrawUtils::getIndexWidgetName { node canvas } {
   set newNode [regsub -all "/" ${node} _]
   set indexListW "${canvas}.[string tolower ${newNode}]"
}

proc ::DrawUtils::clearCanvas { canvas } {
   if { [winfo exists $canvas] } {
      # flush everything in the canvas
      $canvas delete all
      set suiteRecord [xflow_getActiveSuite]
   }
   update idletasks
}

proc ::DrawUtils::drawNodeHost { node host {canvas ""}} {
   variable nodeTypeMap
   variable hostColorMap
   
   set type [$node cget -flow.type]
   if [ catch { set imageType $nodeTypeMap($type) } ] {
      error "Invalid node type $type in proc ::DrawUtils::drawNodeHost()"
      return
   }
   set imageType $nodeTypeMap($type)
   set canvasTag $node.$imageType
   set hostColor $hostColorMap(unknown)
   catch { set hostColor $hostColorMap($host) }
   if { $canvas == "" } {
      # get the list of all canvases where the node appears
      set canvasList [::FlowNodes::getDisplayList $node]
   } else {
      set canvasList $canvas
   }
   foreach canvas $canvasList {
      $canvas itemconfigure $canvasTag -outline $hostColor
   }
}

# canvas = "" means we draw the status on all canvases that
# the node might appear
proc ::DrawUtils::drawNodeStatus { node {shadow_status 0} } {
   variable nodeStatusColorMap
   variable nodeTypeMap
   set type [$node cget -flow.type]
   set currentExtension [::FlowNodes::getNodeExtension $node]
   set status [FlowNodes::getMemberStatus $node $currentExtension ]

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

   DEBUG "::DrawUtils::drawNodeStatus node=$node canvasTag=$canvasTag canvasTextTag=$canvasTextTag status=$status font=[lindex $colors 0] fill=[lindex $colors 1]" 5

   # get the list of all canvases where the node appears
   set canvasList [::FlowNodes::getDisplayList $node]
   foreach canvas $canvasList {
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
}

# canvas = "" means we draw the status on all canvases that
# the node might appear
proc ::DrawUtils::drawNodeText { node new_text {canvas ""} } {
   set canvasTextTag $node.text
   if { $canvas == "" } {
      # get the list of all canvases where the node appears
      set canvasList [::FlowNodes::getDisplayList $node]
   } else {
      set canvasList $canvas
   }
   if { [$node cget -flow.type] == "family" || [$node cget -flow.type] == "module"} {
      set new_text "/$new_text"
   }
   DEBUG "::DrawUtils::drawNodeText new_text:$new_text " 5
   foreach canvas $canvasList {
      if { [winfo exists $canvas] && [$canvas type $canvasTextTag] == "text" } {
         $canvas itemconfigure $canvasTextTag -text $new_text
      }
   }
}

proc ::DrawUtils::drawFamily { node canvas } {
   array set displayInfoList [$node cget -flow.display_infos]
   set displayInfo $displayInfoList($canvas)
   DEBUG "drawFamily displayInfo:$displayInfo" 5
   if {  [$node cget -flow.type] == "family" } {
      set x1 [expr [lindex $displayInfo 1] - 10]
      set x2 [expr [lindex $displayInfo 5] +10]
      set y1 [expr [lindex $displayInfo 2] -5]
      set y2 [expr [lindex $displayInfo 6] +5]
      set color [getNextColor]
      #$canvas create rectangle $x1 $y1 $x2 $y2 \
      #   -dash . -outline "#9eacb3" -fill $color -width 2 -tags "box.$node"
      $canvas create rectangle $x1 $y1 $x2 $y2 \
         -outline "#9eacb3" -fill $color -width 2 -tags "box.$node"
      $canvas lower box.$node
   }
}


proc ::DrawUtils::drawLosange { canvas tx1 ty1 text textfill outline fill binder drawshadow shadowColor} {
   variable constants
   #DEBUG "drawLosange canvas:$canvas text:$text binder:$binder" 5
   set newtx1 [expr ${tx1} + 30]
   $canvas create text ${newtx1} ${ty1} -text $text -fill $textfill \
      -justify center -anchor w -font [SharedData_getMiscData  FONT_BOLD] -tags "$binder ${binder}.text"

   set boxArea [$canvas bbox ${binder}.text]
   set nx1 [expr [lindex $boxArea 0] -30]
   set nx2 [lindex $boxArea 0]
   set nx3 [expr [lindex $boxArea 2] +30]
   set nx4 [lindex $boxArea 2]

   set ny1 [expr [lindex $boxArea 3] +5]
   set ny2 [expr [lindex $boxArea 1] -5]
   set ny3 $ny2
   set ny4 $ny1
   $canvas create polygon ${nx1} ${ny1} ${nx2} ${ny2} ${nx3} ${ny3} ${nx4} ${ny4} \
         -outline $outline -fill $fill -tags "$binder ${binder}.losange"

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
               -fill $shadowColor  -tags "${binder} ${binder}.shadow"
       $canvas lower ${binder}.shadow ${binder}.losange
   }

   set suiteRecord [xflow_getActiveSuite]

   set maximX ${sx2}
   set maximY ${sy3}
   set nextY  [expr $sy4 + 10]
   ::SuiteNode::setDisplayData $suiteRecord $canvas ${nextY} ${maximX} ${maximY}
   ::FlowNodes::setDisplayCoords $binder $canvas [list $nx1 $ny1 $nx3 $ny3 $nx3 $ny4]
}


proc ::DrawUtils::drawOval { canvas tx1 ty1 txt maxtext textfill outline fill binder drawshadow shadowColor } {
   variable constants
   DEBUG "drawOval canvas:$canvas txt:$txt textfill:$textfill fill:$fill binder:$binder" 5
   DEBUG "drawOval textfill:$textfill fill:$fill binder:$binder" 5
   set newtx1 [expr ${tx1} + 10]
   set newty1 $ty1
   $canvas create text ${newtx1} ${newty1} -text $maxtext -fill $textfill \
      -justify center -anchor w -font [SharedData_getMiscData  FONT_BOLD] -tags "$binder ${binder}.text"

   set boxArea [$canvas bbox ${binder}.text]
   $canvas itemconfigure ${binder}.text -text $txt

   set ovalSize [SharedData_getMiscData LOOP_OVAL_SIZE]
   set nx1 [expr [lindex $boxArea 0] - ${ovalSize}]
   set ny1 [expr [lindex $boxArea 1] - ${ovalSize}]
   set nx2 [expr [lindex $boxArea 2] + ${ovalSize}]
   set ny2 [expr [lindex $boxArea 3] + ${ovalSize}]
   
   $canvas create oval ${nx1} ${ny1} ${nx2} ${ny2}  \
          -fill $fill -tags "$binder ${binder}.oval"

   if { [$binder cget -record_type] == "FlowLoop" &&
         [$binder cget -loop_type] == "loopset" } {
      # add parallel icon
      set parx1 [expr $nx2 -5]
      set parx2 $parx1
      set pary1 [expr [lindex $boxArea 1] + 4]
      set pary2 [lindex $boxArea 3]
      $canvas create line $parx1 $pary1 [expr $parx1 - 5] [expr $pary1 + 5] -width 1.5 -fill black
      $canvas create line [expr $parx1 - 5] $pary1 [expr $parx1 - 10] [expr $pary1 + 5] -width 1.5 -fill black
   }

   $canvas lower ${binder}.oval ${binder}.text

   if { $drawshadow == "on" } {
       # draw a shadow
       set sx1 [expr $nx1 + 5]
       set sx2 [expr $nx2 + 5]
       set sy1 [expr $ny1 + 5]
       set sy2 [expr $ny2 + 5]
       $canvas create oval ${sx1} ${sy1} ${sx2} ${sy2} -width 0 \
               -fill $shadowColor  -tags "${binder} ${binder}.shadow"
       $canvas lower ${binder}.shadow ${binder}.oval
   }

   set suiteRecord [xflow_getActiveSuite]
   set maximX ${sx2}
   set maximY ${sy2}
   set nextY  [expr $sy2 + 10]
   ::SuiteNode::setDisplayData $suiteRecord $canvas ${nextY} ${maximX} ${maximY}
   ::FlowNodes::setDisplayCoords $binder $canvas [list $nx1 $ny1 $nx2 $ny2 $nx2 $ny2]

   # this part adds a combo box to hold the index values of a loop node
   if { [$binder cget -record_type] == "FlowLoop" } {
      set indexListW [::DrawUtils::getIndexWidgetName ${binder} ${canvas}]
      if { ! [winfo exists ${indexListW}] } {
         ComboBox ${indexListW} -bwlistbox 1 -hottrack 1 -width 7 \
            -postcommand [list ::DrawUtils::setIndexWidgetStatuses ${binder} ${indexListW}]
         ${indexListW} bind <4> [list ComboBox::_unmapliste ${indexListW}]
         ${indexListW} bind <5> [list ComboBox::_mapliste ${indexListW}]

      }
      set currentExt [${binder} cget -current]
      if {  ${currentExt} == "" || ${currentExt} == "latest" } {
        ${indexListW} configure -values {latest} -width [expr [${binder} cget -max_ext_value] + 3]
      } else {
        set indexValue [::FlowNodes::getIndexValue ${currentExt}] 
        ${indexListW} configure -values  ${indexValue} -width [expr [${binder} cget -max_ext_value] + 3]
      }
      ${indexListW} setvalue first

      # setIndexWidgetStatuses ${binder} ${indexListW}
      pack ${indexListW} -fill both
      set barY [expr $sy2 + 15]
      set barX [expr ($nx1 + $nx2)/2]
      $canvas create window $barX $barY -window ${indexListW}
      set maximX ${sx2}
      set maximY ${barY}
      set nextY [expr $barY + [winfo height ${indexListW}] + 20]
      ::SuiteNode::setDisplayData $suiteRecord $canvas ${nextY} ${maximX} ${maximY}
      # popup tooltip with loop arguments
      ::tooltip::tooltip $canvas -item ${binder} [::FlowNodes::getLoopTooltip ${binder}]
   }
}

proc ::DrawUtils::showIndexWidget { node index_widget } {
   ${index_widget} bind <4> [list ComboBox::_unmapliste ${index_widget}]
}

# this function is called to populate the loop node listbox will
# all the loop indexes... This is ONLY called when the user is attempting
# to view the listbox items
proc ::DrawUtils::setIndexWidgetStatuses { node index_widget } {
   variable nodeStatusColorMap
   variable nodeTypeMap

   if { [${node} cget -record_type] == "FlowNpassTask" } {
      set extensions [::FlowNodes::getNptExtensions ${node}]
   } else {
      set extensions [::FlowNodes::getLoopExtensions ${node}]
   }
   set extensions [linsert ${extensions} 0 latest]

   # assign the extensions to the widget
   ${index_widget} configure -values $extensions

   set listboxW [${index_widget} getlistbox]

   bind ${listboxW}  <4> [list ${listboxW} yview scroll -1 units]
   bind ${listboxW}  <5> [list ${listboxW} yview scroll +1 units]

   # Utils_bindMouseWheel ${listboxW} 3
   set maxItemLength [string length latest]

   set index 0
   set parentExt [::FlowNodes::getParentLoopExt ${node}]
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
            set extStatus [::FlowNodes::getMemberStatus ${node} +${ext}]
         } elseif { ${parentExt} == "latest" } {
            # parent loop set to latest but current loop set to a specific iteration
            # all our iteration should be in init state...
            set extStatus init
         } else {
            # parent has loop iteration set, every iteration is relative to parent one
            set extStatus [::FlowNodes::getMemberStatus ${node} ${parentExt}+${ext}]
         }

         set indexStatusImg [::DrawUtils::getStatusImage ${extStatus}]
         ${listboxW} itemconfigure ${index} -image ${indexStatusImg}
      }
      incr index
   }

   set currentExt [${node} cget -current]
   if { ${currentExt} != "" && ${currentExt} != "latest" } {
      set currentValue [::FlowNodes::getIndexValue ${currentExt}]
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
    DEBUG "drawline canvas:$canvas x1:$x1 y1:$y1 x2:$x2 y2:$y2" 5

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
    DEBUG "drawline canvas:$canvas x1:$x1 y1:$y1 x2:$x2 y2:$y2" 5

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

proc ::DrawUtils::drawX { canvas x1 y1 width fill } {
    DEBUG "drawline canvas:$canvas x1:$x1 y1:$y1" 5

    if { $x1 < $x2 } {
      set x2 [expr $x2 - 3 ]

      #set shadow values
      set sx1 [expr $x1 + 2 ]
      set sx2 $x2
      set sy1 [expr $y1 + 2 ]
      set sy2 $sy1
    } else {
      
      #set shadow values
      set sx1 [expr $x1 + 2]
      set sx2 $sx1
      set sy1 [expr $y1 + 2]
      set sy2 $y2
    }

    if { $drawshadow == "on" } {
      # draw shadow
      $canvas create line ${sx1} ${sy1} ${sx2} ${sy2} -width 1.5 -arrow $arrow -fill $shadowColor -dash { 4 3 }
    }

    # draw line
    $canvas create line ${x1} ${y1} ${x2} ${y2} -width 1.5 -arrow $arrow -fill $fill -dash { 4 3 }
}

proc ::DrawUtils::drawBoxSansOutline { canvas tx1 ty1 text maxtext textfill outline fill binder drawshadow shadowColor} {
   variable constants
   DEBUG "drawBoxSaneoutline canvas:$canvas text:$text ty1=$ty1 fill=$fill binder:$binder" 5
   set family [$binder cget -flow.family]
   $canvas create text ${tx1} ${ty1} -text /$maxtext -fill $textfill \
      -justify center -anchor w -font [SharedData_getMiscData  FONT_BOLD] -tags "$binder ${binder}.text"

   # draw a box around the text
   set boxArea [$canvas bbox ${binder}.text]

   $canvas itemconfigure ${binder}.text -text /$text

   set nx1 [expr [lindex $boxArea 0] -5]
   set ny1 [expr [lindex $boxArea 1] -5]
   set nx2 [expr [lindex $boxArea 2] +5]
   set ny2 [expr [lindex $boxArea 3] +5]
   DEBUG "drawBoxSansOutline Doug text=$text nx1=$nx1 ny1=$ny1 nx2=$nx2 ny2=$ny2"
   $canvas create rectangle ${nx1} ${ny1} ${nx2} ${ny2} \
           -fill $fill -tags "$binder ${binder}.rectangle" 
   $canvas lower ${binder}.rectangle ${binder}.text

   if { $drawshadow == "on" } {
       # draw a shadow
       set sx1 [expr $nx1 + 5]
       set sx2 [expr $nx2 + 5]
       set sy1 [expr $ny1 + 5]
       set sy2 [expr $ny2 + 5]
       $canvas create rectangle ${sx1} ${sy1} ${sx2} ${sy2} -width 0 \
               -fill $shadowColor  -tags "${binder} ${binder}.shadow"
       $canvas lower ${binder}.shadow ${binder}.rectangle
   }

   set suiteRecord [xflow_getActiveSuite]

   ::FlowNodes::setDisplayCoords $binder $canvas [list $nx1 $ny1 $nx2 $ny2 $nx2 $ny2]
   set maximX ${sx2}
   set maximY ${sy2}
   set nextY ${ny2}
   ::SuiteNode::setDisplayData $suiteRecord $canvas ${nextY} ${maximX} ${maximY}
}

proc ::DrawUtils::drawBox { canvas tx1 ty1 text maxtext textfill outline fill binder drawshadow shadowColor } {
   variable constants
   DEBUG "drawBox canvas:$canvas text:$text textfill=$textfill outline=$outline fill=$fill binder:$binder" 5

   $canvas create text ${tx1} ${ty1} -text $maxtext -fill $textfill \
      -justify center -anchor w -font [SharedData_getMiscData  FONT_BOLD] -tags "$binder ${binder}.text"

   # draw a box around the text
   set boxArea [$canvas bbox ${binder}.text]

   $canvas itemconfigure ${binder}.text -text $text

   set nx1 [expr [lindex $boxArea 0] -5]
   set ny1 [expr [lindex $boxArea 1] -5]
   set nx2 [expr [lindex $boxArea 2] +5]
   set ny2 [expr [lindex $boxArea 3] +5]
   $canvas create rectangle ${nx1} ${ny1} ${nx2} ${ny2} \
            -fill $fill -outline $outline -tags "$binder ${binder}.rectangle"
   $canvas lower ${binder}.rectangle ${binder}.text

   if { $drawshadow == "on" } {
       # draw a shadow
       set sx1 [expr $nx1 + 5]
       set sx2 [expr $nx2 + 5]
       set sy1 [expr $ny1 + 5]
       set sy2 [expr $ny2 + 5]
       $canvas create rectangle ${sx1} ${sy1} ${sx2} ${sy2} -width 0 \
               -fill $shadowColor  -tags "${binder} ${binder}.shadow"
       $canvas lower ${binder}.shadow ${binder}.rectangle
   }

   set suiteRecord [xflow_getActiveSuite]
   set maximX ${sx2}
   set maximY ${sy2}
   set nextY ${ny2}
   ::SuiteNode::setDisplayData $suiteRecord $canvas ${nextY} ${maximX} ${maximY}

   ::FlowNodes::setDisplayCoords $binder $canvas [list $nx1 $ny1 $nx2 $ny2 $nx2 $ny2]
   if { [$binder cget -record_type] == "FlowNpassTask" } {
      set indexListW [::DrawUtils::getIndexWidgetName ${binder} ${canvas}]
      if { ! [winfo exists ${indexListW}] } {
         ComboBox ${indexListW} -bwlistbox 1 -hottrack 1 -width 7 \
            -postcommand [list ::DrawUtils::setIndexWidgetStatuses ${binder} ${indexListW}]
         ${indexListW} bind <4> [list ComboBox::_unmapliste ${indexListW}]
         ${indexListW} bind <5> [list ComboBox::_mapliste ${indexListW}]
      }
      set currentExt [${binder} cget -current]
      if {  ${currentExt} == "" || ${currentExt} == "latest" } {
        ${indexListW} configure -values {latest} -width [expr [${binder} cget -max_ext_value] + 3]
        # ${indexListW} configure -values {latest}
      } else {
        set indexValue [::FlowNodes::getIndexValue ${currentExt}]
        ${indexListW} configure -values  ${indexValue} -width [expr [${binder} cget -max_ext_value] + 3]
      }
      ${indexListW} setvalue first

      pack ${indexListW} -fill both
      set barY [expr $sy2 + 15]
      set barX [expr ($nx1 + $nx2)/2]
      $canvas create window $barX $barY -window  ${indexListW}
      set maximX ${sx2}
      set maximY ${barY}
      set nextY  [expr $barY + [winfo height  ${indexListW}] + 20]
      ::SuiteNode::setDisplayData $suiteRecord $canvas ${nextY} ${maximX} ${maximY}
   }

}

proc ::DrawUtils::pointNode { suite_record node {canvas ""} } {
   DEBUG "::DrawUtils::pointNode ${suite_record} node:${node}" 5
   set canvasList ${canvas}
   if { ${canvas} == "" } {
      set canvasList [::SuiteNode::getCanvasList ${suite_record}]
   }
   foreach canvasW ${canvasList} {
      set newcords [${canvasW} coords ${node}]
   
      if { [string length $newcords] == 0 } {
         DEBUG "cb_findjob_no_widget can't find node:${node}" 5
         return 0
      }
      # the "target"s are the top-left and bottom-right
      # coordinates for the job box
      set target_x  [expr round([lindex $newcords 0])]
      set target_y  [expr round([lindex $newcords 1])]
      set target_x2 [expr round([lindex $newcords 2])]
      set target_y2 [expr round([lindex $newcords 3])]
   
      set x_offset 25
      set y_offset 25
   
      # draw four lines with arrows pointing at the job
      ${canvasW} create line $target_x $target_y [expr $target_x - $x_offset] \
      [expr $target_y - $y_offset] -arrow first -width 2m -tag ${canvasW}searchlines -fill black
      ${canvasW} create line $target_x2 $target_y [expr $target_x2 + $x_offset] \
      [expr $target_y - $y_offset] -arrow first -width 2m -tag ${canvasW}searchlines -fill black
      ${canvasW} create line $target_x $target_y2 [expr $target_x - $x_offset] \
      [expr $target_y2 + $y_offset] -arrow first -width 2m -tag ${canvasW}searchlines -fill black
      ${canvasW} create line $target_x2 $target_y2 [expr $target_x2 + $x_offset] \
      [expr $target_y2 + $y_offset] -arrow first -width 2m -tag ${canvasW}searchlines -fill black
   
      # bring to front
      wm withdraw .; wm deiconify .
      # after 5 seconds, delete the lines pointing at the job
      after 5000 [list ::DrawUtils::delPointNode ${canvasW}]
   }
}

# search down the node tree for nodes in position 0 relative
# to the current node that might require more space than
# usual ones Example loop. Used mainly to know where to draw the first
# node of a branch
proc ::DrawUtils::getLineDeltaSpace { flow_node {delta_value 0} } {
   DEBUG "::DrawUtils::getLineDeltaSpace $flow_node delta_value: $delta_value" 5
   set value ${delta_value}
   # I only need to calculate extra space if the current node is not in position 0
   # in it's parent node. If it is in position 0, the extra space has already been calculated.

   if { [::FlowNodes::getPosition ${flow_node}] != 0 } {
      set done 0
      set node ${flow_node}
      while { ! ${done} } {
         # for now only loops needs be treated
         if { [${node} cget -flow.type] == "loop" } {
            if { [expr ${value} < [SharedData_getMiscData LOOP_OVAL_SIZE]] } {
               set value [SharedData_getMiscData LOOP_OVAL_SIZE]
            }
         }
         set childNodes [${node} cget -flow.children]
         # i'm only interested in the first position of the child list, the others will be calculated
         # when we move down the tree
         set childNode [lindex ${childNodes} 0]
      
         if { ${childNode} != "" } {
            # move further down the tree
            set node ${node}/${childNode}
         } else {
            set done 1
         }
      }
   }
   return $value
}

proc  ::DrawUtils::delPointNode {canvas } {

    if { [winfo exists $canvas] } {
        $canvas delete ${canvas}searchlines
    }
}

proc ::DrawUtils::getStatusImage { status } {
   set statusImage .${status}_set_image
   global STATUS_IMG_${status}

   if { ! [info exists STATUS_IMG_${status}] } {
      set imageDir [SharedData_getMiscData IMAGE_DIR]
      image create photo ${statusImage} -file ${imageDir}/status_${status}_icon.ppm
      set STATUS_IMG_${status} ${statusImage}
   }
   return ${statusImage}
}

proc ::DrawUtils::highLightNode { suite_record node canvas_w } {
   global NodeHighLightRestoreCmd 
   variable nodeTypeMap

   set type [$node cget -flow.type]
   set imageType $nodeTypeMap($type)
   set canvasTag $node.$imageType

   set selectColor [SharedData_getColor SELECT_BG]
   set currentWidth [${canvas_w} itemcget ${canvasTag} -width ]
   set currentOutline [${canvas_w} itemcget ${canvasTag} -outline]
   ${canvas_w} itemconfigure ${canvasTag} -width 2 -outline ${selectColor}
   set NodeHighLightRestoreCmd "${canvas_w} itemconfigure ${canvasTag} -width ${currentWidth} -outline ${currentOutline}"
}