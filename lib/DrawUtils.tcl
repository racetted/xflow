package provide DrawUtils 1.0
package require Tk
package require FlowNodes
#package require Tix
package require tile

#namespace delete ::DrawUtils

namespace eval ::DrawUtils {

   namespace export init clearCanvas drawTrapeze \
      drawNodeStatus getStatusColor

   # maps a status name to text color / background color
   variable nodeStatusColorMap

   # maps a family to image representation
   variable nodeTypeMap

   # maps a host to color representation
   variable hostColorMap
}

proc out {} {
}

proc ::DrawUtils::init {} {
   variable nodeStatusColorMap
   variable nodeTypeMap
   variable hostColorMap
   variable constants

   array set nodeStatusColorMap {
      begin "white #108B5C"
      init "#FFF8DC cornsilk4"
      submit "white #ACB112"
      abort "white #8B1012"
      wait "black Sandybrown"
      catchup "white Magenta2"
      end "white DodgerBlue4"
      unknown "white black"
      shadow "white black"
   }

   array set nodeTypeMap {
      family rectangle
      module rectangle
      task rectangle
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

   array set constants {
      border_width "3"
   }
}

proc ::DrawUtils::getStatusColor { node_status } {
   variable nodeStatusColorMap
   if { [info exists nodeStatusColorMap($node_status)] } {
      set colors $nodeStatusColorMap($node_status)
   } else {
      set colors "white black"
   }
   return $colors
}

proc ::DrawUtils::clearCanvas { canvas } {
   if { [winfo exists $canvas] } {
      # flush everything in the canvas
      $canvas delete all
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
   set colors $nodeStatusColorMap(init)
   catch { set colors $nodeStatusColorMap($status) }

   DEBUG "::DrawUtils::drawNodeStatus node=$node canvasTag=$canvasTag canvasTextTag=$canvasTextTag status=$status font=[lindex $colors 0] fill=[lindex $colors 1]" 5

   # get the list of all canvases where the node appears
   set canvasList [::FlowNodes::getDisplayList $node]
   foreach canvas $canvasList {
      # $canvas itemconfigure $canvasTag -fill [lindex $colors 1]
      if { $shadow_status == "1" } {
         $canvas itemconfigure $canvasTextTag -fill "black"
         $canvas itemconfigure $canvasTag -fill white
         if { $status == "init" } {
            $canvas itemconfigure $canvasTag -outline [getGlobalValue NORMAL_RUN_OUTLINE]
            $canvas itemconfigure ${canvasShadowTag} -fill [getGlobalValue SHADOW_COLOR]
         } else {
            $canvas itemconfigure $canvasTag -outline [lindex $colors 1]
            $canvas itemconfigure ${canvasShadowTag} -fill [lindex $colors 1]
         }
      } else {
         $canvas itemconfigure $canvasTextTag -fill [lindex $colors 0]
         $canvas itemconfigure $canvasTag -fill [lindex $colors 1]
         #$canvas itemconfigure $canvasTag -outline [getGlobalValue NORMAL_RUN_OUTLINE]
         #$canvas itemconfigure ${canvasShadowTag} -fill [lindex $colors 1]
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
      if { [$canvas type $canvasTextTag] == "text" } {
         $canvas itemconfigure $canvasTextTag -text $new_text
      }
   }
}

proc ::DrawUtils::drawFamily { node canvas } {
   array set displayInfoList [$node cget -flow.display_infos]
   set displayInfo $displayInfoList($canvas)
   puts "drawFamily displayInfo:$displayInfo"
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

proc ::DrawUtils::drawTrapeze { canvas tx1 ty1 text textfill outline fill callback binder } {
   variable constants
   DEBUG "drawTrapeze canvas:$canvas tx1:$tx1 ty1:$ty1 text:$text callback:$callback binder:$binder" 5
   set newtx1 [expr ${tx1} + 15]
   $canvas create text ${newtx1} ${ty1} -text $text -fill $textfill \
      -justify center -anchor w -font [getGlobalValue FONT_BOLD] -tags "$binder ${binder}.text"

   set boxArea [$canvas bbox ${binder}.text]
   #set nx1 [expr [lindex $boxArea 0] -15]
   set nx1 [lindex $boxArea 0]
   set nx2 [lindex $boxArea 0]
   set nx3 [lindex $boxArea 2]
   set nx4 [lindex $boxArea 2]

   set ny1 [expr [lindex $boxArea 3] +5]
   set ny2 [expr [lindex $boxArea 1] -5]
   set ny3 $ny2
   set ny4 $ny1
   DEBUG "drawTrapeze polygon: ${nx1} ${ny1} ${nx2} ${ny2} ${nx3} ${ny3} ${nx4} ${ny4}" 5
   $canvas create polygon ${nx1} ${ny1} ${nx2} ${ny2} ${nx3} ${ny3} ${nx4} ${ny4}  \
         -fill $fill -tags "$binder ${binder}.trapeze"

   $canvas lower ${binder}.trapeze ${binder}.text

   set suite [::SuiteNode::getSuiteRecord $canvas]
   if { $ny4 > [::SuiteNode::getDisplayNextY $suite $canvas] } {
      ::SuiteNode::setDisplayNextY $suite $canvas $ny4
   }
   ::FlowNodes::setDisplayCoords $binder $canvas [list $nx1 $ny2 $nx4 $ny4 $nx4 $ny4]
}

proc ::DrawUtils::drawLosange { canvas tx1 ty1 text textfill outline fill callback binder drawshadow shadowColor} {
   variable constants
   #DEBUG "drawLosange canvas:$canvas text:$text callback:$callback binder:$binder" 5
   set newtx1 [expr ${tx1} + 30]
   $canvas create text ${newtx1} ${ty1} -text $text -fill $textfill \
      -justify center -anchor w -font [getGlobalValue FONT_BOLD] -tags "$binder ${binder}.text"

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
               -fill $shadowColor  -tags "${binder}.shadow"
       $canvas lower ${binder}.shadow ${binder}.losange
   }

   set suite [::SuiteNode::getSuiteRecord $canvas]
   if { $ny4 > [::SuiteNode::getDisplayNextY $suite $canvas] } {
      ::SuiteNode::setDisplayNextY $suite $canvas [expr $ny4 + 10]
   }
   ::FlowNodes::setDisplayCoords $binder $canvas [list $nx1 $ny1 $nx3 $ny3 $nx3 $ny4]
}

proc ::DrawUtils::drawBucket { canvas tx1 ty1 text textfill outline fill callback binder } {
   variable constants
   #DEBUG "drawBucket canvas:$canvas text:$text callback:$callback binder:$binder" 5
   set newtx1 ${tx1}
   set newty1 [expr ${ty1} - 5]
   $canvas create text ${newtx1} ${newty1} -text $text -fill $textfill \
      -justify center -anchor w -font [getGlobalValue FONT_BOLD] -tags "$binder ${binder}.text"

   set boxArea [$canvas bbox ${binder}.text]
   set nx1 [expr [lindex $boxArea 0] -5]
   set ny1 [expr [lindex $boxArea 1] -5]

   set nx2 [expr ([lindex $boxArea 0] + [lindex $boxArea 2]) / 2]
   set ny2 [expr $ny1 + -5]

   set nx3 [expr  [lindex $boxArea 2] + 5 ]
   set ny3 $ny1

   set nx4 $nx3
   set ny4 [expr [lindex $boxArea 3] + 15]

   set nx5 $nx1
   set ny5 $ny4

   $canvas create polygon ${nx1} ${ny1} ${nx2} ${ny2} ${nx3} ${ny3} ${nx4} ${ny4} ${nx5} ${ny5} -width $constants(border_width) \
         -outline $outline -fill $fill -tags "$binder ${binder}.module"

   $canvas lower ${binder}.module ${binder}.text

   set suite [::SuiteNode::getSuiteRecord $canvas]
   if { $ny2 > [::SuiteNode::getDisplayNextY $suite $canvas] } {
      ::SuiteNode::setDisplayNextY $suite $canvas $ny4
   }
   ::FlowNodes::setDisplayCoords $binder $canvas [list $nx1 $ny1 $nx4 $ny4 $nx3 $ny4]
}

proc ::DrawUtils::drawOval { canvas tx1 ty1 txt maxtext textfill outline fill callback binder drawshadow shadowColor } {
   variable constants
   DEBUG "drawOval canvas:$canvas txt:$txt textfill:$textfill fill:$fill callback:$callback binder:$binder" 5
   set newtx1 [expr ${tx1} + 10]
   #set newty1 [expr ${ty1} + 10]
   #set newtx1 $tx1
   set newty1 $ty1
   $canvas create text ${newtx1} ${newty1} -text $maxtext -fill $textfill \
      -justify center -anchor w -font [getGlobalValue FONT_BOLD] -tags "$binder ${binder}.text"

   set boxArea [$canvas bbox ${binder}.text]
   $canvas itemconfigure ${binder}.text -text $txt

   set nx1 [expr [lindex $boxArea 0] -15]
   set ny1 [expr [lindex $boxArea 1] -15]
   set nx2 [expr [lindex $boxArea 2] +15]
   set ny2 [expr [lindex $boxArea 3] +15]
   
   $canvas create oval ${nx1} ${ny1} ${nx2} ${ny2}  \
          -fill $fill -tags "$binder ${binder}.oval"

   if { [$binder cget -record_type] == "FlowLoop" &&
         [$binder cget -loop_type] == "loopset" } {
      # added to test parallel icon
      #set parx1 [lindex $boxArea 2]
      set parx1 [expr $nx2 -5]
      set parx2 $parx1
      set pary1 [expr [lindex $boxArea 1] + 4]
      set pary2 [lindex $boxArea 3]
      $canvas create line $parx1 $pary1 [expr $parx1 - 5] [expr $pary1 + 5] -width 1.5 -fill "#FFF8DC"
      $canvas create line [expr $parx1 - 5] $pary1 [expr $parx1 - 10] [expr $pary1 + 5] -width 1.5 -fill "#FFF8DC"
      #$canvas create line [expr $parx1 - 10] $pary1 [expr $parx1 - 15] [expr $pary1 + 5] -width 1.5 -fill "#FFF8DC"
      # end parallel icon
   }

   $canvas lower ${binder}.oval ${binder}.text

   if { $drawshadow == "on" } {
       # draw a shadow
       set sx1 [expr $nx1 + 5]
       set sx2 [expr $nx2 + 5]
       set sy1 [expr $ny1 + 5]
       set sy2 [expr $ny2 + 5]
       $canvas create oval ${sx1} ${sy1} ${sx2} ${sy2} -width 0 \
               -fill $shadowColor  -tags "${binder}.shadow"
       $canvas lower ${binder}.shadow ${binder}.oval
   }

   set suite [::SuiteNode::getSuiteRecord $canvas]
   if { $ny2 > [::SuiteNode::getDisplayNextY $suite $canvas] } {
      ::SuiteNode::setDisplayNextY $suite $canvas [expr $sy2 + 10]
   }
   ::FlowNodes::setDisplayCoords $binder $canvas [list $nx1 $ny1 $nx2 $ny2 $nx2 $ny2]
   
   if { [$binder cget -record_type] == "FlowLoop" } {
      set loopBar "${canvas}.[$binder cget flow.name]"
      puts "drawOval loopBar:$loopBar"
      if { ! [winfo exists ${loopBar}] } {
         ttk::combobox ${loopBar}
         ${loopBar} set latest
         set extensions [::FlowNodes::getLoopExtensions $binder]
         lappend extensions latest
         ${loopBar} configure -value $extensions -width 12
         bind ${loopBar} <<ComboboxSelected>> [list loopSelectionCallback $binder $canvas %W]
      }
      pack $loopBar -fill both
      #set barY [ expr [::SuiteNode::getDisplayNextY $suite $canvas] + 10 ]
      set barY [expr $sy2 + 15]
      set barX [expr ($nx1 + $nx2)/2]
      #set barX [expr ($nx1 + $nx2)/2 + 15]
      $canvas create window $barX $barY -window $loopBar
      ::SuiteNode::setDisplayNextY $suite $canvas [expr $barY + [winfo height $loopBar] + 20]
   }
}

proc ::DrawUtils::drawline { canvas x1 y1 x2 y2 arrow fill drawshadow shadowColor} {
    DEBUG "drawline canvas:$canvas x1:$x1 y1:$y1 x2:$x2 y2:$y2" 5

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
      set sy2 [expr $y2 + 3]
    }
    if { $drawshadow == "on" } {
      # draw shadow
      $canvas create line ${sx1} ${sy1} ${sx2} ${sy2} -width 1.5 -arrow $arrow -fill $shadowColor
    }

    # draw line
    $canvas create line ${x1} ${y1} ${x2} ${y2} -width 1.5 -arrow $arrow -fill $fill 

}

proc ::DrawUtils::drawdashline { canvas x1 y1 x2 y2 arrow fill drawshadow shadowColor} {
    DEBUG "drawline canvas:$canvas x1:$x1 y1:$y1 x2:$x2 y2:$y2" 5

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

proc ::DrawUtils::drawBoxSansOutline { canvas tx1 ty1 text maxtext textfill outline fill callback binder drawshadow shadowColor} {
   variable constants
   DEBUG "drawBoxSaneoutline canvas:$canvas text:$text ty1=$ty1 fill=$fill callback:$callback binder:$binder" 5
   set family [$binder cget -flow.family]
   $canvas create text ${tx1} ${ty1} -text /$maxtext -fill $textfill \
      -justify center -anchor w -font [getGlobalValue FONT_BOLD] -tags "$binder ${binder}.text"

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
               -fill $shadowColor  -tags "${binder}.shadow"
       $canvas lower ${binder}.shadow ${binder}.rectangle
   }

   set suite [::SuiteNode::getSuiteRecord $canvas]
   if { $ny2 > [::SuiteNode::getDisplayNextY $suite $canvas] } {
      ::SuiteNode::setDisplayNextY $suite $canvas $ny2
   }
   ::FlowNodes::setDisplayCoords $binder $canvas [list $nx1 $ny1 $nx2 $ny2 $nx2 $ny2]
}


proc ::DrawUtils::drawBox { canvas tx1 ty1 text maxtext textfill outline fill callback binder drawshadow shadowColor} {
   variable constants
   DEBUG "drawBox canvas:$canvas text:$text textfill=$textfill outline=$outline fill=$fill callback:$callback binder:$binder" 5
   set family [$binder cget -flow.family]

   $canvas create text ${tx1} ${ty1} -text $maxtext -fill $textfill \
      -justify center -anchor w -font [getGlobalValue FONT_BOLD] -tags "$binder ${binder}.text"

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
               -fill $shadowColor  -tags "${binder}.shadow"
       $canvas lower ${binder}.shadow ${binder}.rectangle
   }

   set suite [::SuiteNode::getSuiteRecord $canvas]
   if { $sy2 > [::SuiteNode::getDisplayNextY $suite $canvas] } {
      ::SuiteNode::setDisplayNextY $suite $canvas $ny2
      #::SuiteNode::setDisplayNextY $suite $canvas $sy2
   }
   ::FlowNodes::setDisplayCoords $binder $canvas [list $nx1 $ny1 $nx2 $ny2 $nx2 $ny2]
   #::FlowNodes::setDisplayCoords $binder $canvas [list $nx1 $ny1 $sx2 $sy2 $sx2 $sy2]
}
