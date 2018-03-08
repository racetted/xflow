package require Tk
package require tablelist
package require autoscroll
package require tooltip
package require log

global env
set lib_dir $env(SEQ_XFLOW_BIN)/../lib
# puts "lib_dir=$lib_dir"
set auto_path [linsert $auto_path 0 $lib_dir ]

namespace eval ::dkfFontSel {
    # Use the tile package if it is present...
    if {![catch {package present tile}]} {
	namespace import ::ttk::*
    }
    proc readProperties { font {rc_file ""} } {   
      global env XFLOW_STANDALONE LIST_EXP LIST_FONT_LEVEL
      variable Applyon
      variable Style
      variable exp_path
      variable datestamp
      variable list_item
      array set list_item {
          font_name 0
          font_task 0
          font_label 0
          font_name_size 0
          font_task_size 0
          font_label_size 0
          font_name_style 0
          font_task_style 0
          font_label_style 0
          font_name_slant 0
          font_task_slant 0
          font_label_slant 0
          font_name_underl 0
          font_task_underl 0
          font_label_underl 0
      }

      set font_task  0
      set font_title 0
      set font_label 0
      
      foreach applyons {task titles label} {
	if { $Applyon($applyons) && $applyons == "task"} {
           set font_task  $Applyon($applyons)
        } elseif { $Applyon($applyons) && $applyons == "titles"} {
           set font_title $Applyon($applyons)
        } elseif { $Applyon($applyons) && $applyons == "label"} {
           set font_label $Applyon($applyons)
        }
      }
      set errorMsg ""
      set f [SharedData_getMiscData RC_FILE]
      if {![file writable ${f}]} {
        set errorMsg "$f \n permission denied"  
      } 
      set f.new $env(HOME)/.maestrorc.new
      if { [file exists ${f}] } {
         if { ${errorMsg} == "" } {
           set in   [open ${f}     r]
           set out  [open ${f.new} w]
           set patternst "font*style"
           set patternsl "font*slant"
           set patternul "font*underl"
           set pattersiz "font*size"

           while {[gets ${in} line] >= 0 && ${errorMsg} == "" } {
             if { [string index ${line} 0] != "#" && [string length ${line}] > 0 } {
               set splittedList [split ${line} =]
               if { [llength ${splittedList}] != 2 } {
                   # error "ERROR: While reading ${fileName}\nInvalid property syntax: ${line}"
                   set errorMsg "While reading ${fileName}\n\nInvalid property syntax: ${line}.\n"
               } else {
                   set keyFound   [string trim [lindex $splittedList 0]]
                   set valueFound [string trim [lindex $splittedList 1]]
                   if { [info exists list_item($keyFound)] } {
                     set list_item(${keyFound}) 1
                   }
                   if {(${keyFound} == "font_task" && $font_task) || (${keyFound} == "font_name" && $font_title) || (${keyFound} == "font_label" && $font_label) } {
                     puts $out "${keyFound} = [string trim [lindex $font 0]]"
                   } elseif { [string match $patternst ${keyFound}] || [string match $patternsl ${keyFound}] || [ string match $patternul ${keyFound}] } {
                      if {(${keyFound} == "font_task_style" && $font_task &&  $Style(bold)) || 
                          (${keyFound} == "font_name_style" && $font_title && $Style(bold)) ||
                          (${keyFound} == "font_label_style" && $font_label &&  $Style(bold))} {
                        puts $out "${keyFound} = bold"
                      } elseif {(${keyFound} == "font_task_style" && $font_task &&  !$Style(bold))  || 
                                (${keyFound} == "font_name_style" && $font_title &&  !$Style(bold)) ||
                                (${keyFound} == "font_label_style" && $font_label &&  !$Style(bold))} {
                        puts $out "${keyFound} = normal"
                      } elseif {[string match $patternst ${keyFound}]}  {
                        puts $out ${line}
                      }
                      if {(${keyFound} == "font_task_slant" && $font_task && $Style(italic))  ||
                          (${keyFound} == "font_name_slant" && $font_title && $Style(italic)) ||
                          (${keyFound} == "font_label_slant" && $font_label && $Style(italic))} {
                        puts $out "${keyFound} = italic"
                      } elseif {(${keyFound} == "font_task_slant" && $font_task && !$Style(italic) )  ||
                            (${keyFound} == "font_name_slant" && $font_title && !$Style(italic) ) ||
                            (${keyFound} == "font_label_slant" && $font_label && !$Style(italic))} {
                        puts $out "${keyFound} = roman"
                      } elseif {[string match $patternsl ${keyFound}]} {
                         puts $out ${line}
                      }
                      if {(${keyFound} == "font_task_underl" && $font_task && $Style(underline)) ||
                          (${keyFound} == "font_name_underl" && $font_title && $Style(underline)) ||
                          (${keyFound} == "font_label_underl" && $font_label && $Style(underline)) } {
                        puts $out "${keyFound} = 1"
                      } elseif {(${keyFound} == "font_task_underl" && $font_task && !$Style(underline)) ||
                          (${keyFound} == "font_name_underl"  && $font_title && !$Style(underline)) ||
                          (${keyFound} == "font_label_underl" && $font_label && !$Style(underline)) } {
                        puts $out "${keyFound} = 0"
                      } elseif {[string match $patternul ${keyFound}]} {
                        puts $out ${line}
                      }
                   } elseif {(${keyFound} == "font_task_size" && $font_task)  || 
                             (${keyFound} == "font_name_size" && $font_title) ||
                             (${keyFound} == "font_label_size" && $font_label)} {
                      puts $out "${keyFound} = [string trim [lindex $font 1]]"
                   } else {
                     puts $out ${line}
                   }
               }      
             } else {
               puts $out ${line}
             }
           }
           foreach key [array names list_item] { 
             if { !$list_item($key) } {
               if {${key} == "font_task" || ${key} == "font_name" || ${key} == "font_label"} {
                 puts $out "${key} = [string trim [lindex $font 0]]"
               } elseif {[string match $patternsl ${key}] && $Style(italic)}  {
                 puts $out "$key = italic"
               } elseif {[string match $patternsl ${key}] && !$Style(italic)}  {
                 puts $out "$key = roman"
               } elseif {[string match $patternst ${key}] && !$Style(bold)}  {
                 puts $out "$key = normal"
               } elseif {[string match $patternst ${key}] &&  $Style(bold)}  {
                 puts $out "$key = bold"
               } elseif  {[string match $patternul ${key}]}  {
                 puts $out "$key = $Style(underline)"
               } elseif  {[string match $pattersiz ${key}]}  {
                 puts $out "$key = [string trim [lindex $font 1]]"
               }
             }
           }
           catch { close ${in} }
           catch { close ${out}}
         }
      }
      if { ${errorMsg} != "" } {
         tk_messageBox -message ${errorMsg} \
     	    -title "Error" -type ok -icon info
      } else {
           file rename -force $f.new $f
           SharedData_readProperties
           ::DrawUtils::init
 
           if {[SharedData_getMiscData OVERVIEW_MODE] == "true" && ${XFLOW_STANDALONE} == "0"} {
              foreach litem $LIST_FONT_LEVEL  {
                 Overview_getLevelFont  [lindex $litem 0]  [lindex $litem 1] [lindex $litem 2]
              }
              Overview_getBoxLabelFont
              if { $font_label} {
                xflow_getExpLabelFont
              }
              set counter       0
              if { [llength ${LIST_EXP}] > 0} {
                set ll [lsort -unique $LIST_EXP]
                foreach item $ll {
                  set exp_path        [lindex $item 0]
                  set datestamp       [lindex $item 1]
                  set toplevelW       [xflow_getToplevel ${exp_path} ${datestamp}]
                  if { [winfo exists ${toplevelW}] } {
                     set canvas [xflow_getMainFlowCanvas ${exp_path} ${datestamp}]
                     set FLOW_SCALE_${exp_path}_${datestamp} [SharedData_getMiscData FLOW_SCALE]
                     ::DrawUtils::getBoxLabelFont $canvas
                     if { $font_task } {
                       xflow_refreshFlow ${exp_path} ${datestamp} true
                     }
                   } else {
                     set LIST_EXP  [lreplace ${LIST_EXP} ${counter} ${counter}]
                   }
                   incr counter
                }
             }
           } elseif  {[SharedData_getMiscData OVERVIEW_MODE] == "false" && ${XFLOW_STANDALONE} == "1"} {
              set canvas [xflow_getMainFlowCanvas ${exp_path} ${datestamp}]
              ::DrawUtils::getBoxLabelFont $canvas
              if { $font_label} {
                xflow_getExpLabelFont
              }
              if { $font_task} {
                xflow_refreshFlow ${exp_path} ${datestamp} true
              }
           }  
      }
    }

    # Local procedure names (ones that it is a bad idea to refer to
    # outside this namespace/file) are prepended with an apostrophe
    # character.  There are no externally useful variables.

    # First some library stuff that is normally in another namespace

    # Simple (nay, brain-dead) option parser.  Given the list of
    # arguments in arglist and the list of legal options in optlist,
    # parse the options to convert into array values (which are stored
    # in the caller's array named in optarray.  Does not handle errors
    # spectacularly well, and can be replaced by something that does a
    # better job without me feeling to fussed about it!
    proc 'parse_opts {arglist optlist optarray} {
	upvar $optarray options
	set options(foo) {}
	unset options(foo)
	set callername [lindex [info level -1] 0]
	if {[llength $arglist]&1} {
	    return -code error \
		    "Must be an even number of arguments to $callername"
	}
	array set options $arglist
	foreach key [array names options] {
	    if {![string match -?* $key]} {
		return -code error "All parameter keys must start\
			with \"-\", but \"$key\" doesn't"
	    }
	    if {[lsearch -exact $optlist $key] < 0} {
		return -code error "Bad parameter \"$key\""
	    }
	}
    }

    # Capitalise the given word.  Assumes the first capitalisable
    # letter is the first character in the argument.
    proc 'capitalise {word} {
	set cUpper [string toupper [string index $word 0]]
	set cLower [string tolower [string range $word 1 end]]
	return ${cUpper}${cLower}
    }

    # The classic functional operation.  Replaces each element of the
    # input list with the result of running the supplied script on
    # that element.
    proc 'map {script list} {
	set newlist {}
	foreach item $list {
	    lappend newlist [uplevel 1 $script [list $item]]
	}
	return $newlist
    }

    # ----------------------------------------------------------------------
    # Now we start in earnest
    namespace export dkf_chooseFont

    variable Family Helvetica
    variable Size   12
    variable Done   0
    variable exp_path 
    variable datestamp
    variable Win    {}
    variable Style
    array set Style {
	bold 0
	italic 0
	underline 0
    }
    variable Applyon 
    array set Applyon {
	task   0
        titles 0
        label  0
    }

    # Build the user interface (except for the apply button, which is
    # handled by the 'configure_apply procedure...
    proc 'make_UI {w} {
	# Labelled frames for the framed boxes & focus accelerators
	# for their contents
	foreach {subname row col cols padx pady focusWin} {
	    Family 0 0 1 2m     2m family
	    Style  0 1 1 {0 2m} 2m styleBold
	    Size   1 0 2 2m     0  size8
	    Sample 2 0 2 2m     2m sample.text
            Applyon 3 0 2 2m     2m task
	} {
	    set l [labelframe $w.lbl$subname]
	    grid $l -row $row -column $col -columnspan $cols -sticky nsew \
		    -padx $padx -pady $pady
	    'set_accel $l $w [list focus $w.$focusWin]
	}
	grid columnconfigure $w 0 -weight 1
	grid rowconfigure $w 0 -weight 1

	# Font families
	listbox $w.family -exportsel 0 -selectmode browse \
		-xscrollcommand [list $w.familyX set] \
		-yscrollcommand [list $w.familyY set]
	scrollbar $w.familyX -command [list $w.family xview]
	scrollbar $w.familyY -command [list $w.family yview]
	foreach family ['list_families] {
	    $w.family insert end ['map 'capitalise $family]
	}
	grid columnconfigure $w.lblFamily 0 -weight 1
	grid rowconfigure    $w.lblFamily 0 -weight 1
	grid $w.family  $w.familyY -sticky nsew -in $w.lblFamily
	grid $w.familyX            -sticky nsew -in $w.lblFamily
	bind $w.family <1> [namespace code {'change_family %W [%W nearest %y]}]
	bindtags $w.family [concat [bindtags $w.family] key$w.family]
	bind key$w.family <Key> [namespace code {'change_family %W active %A}]
	grid $w.family  -padx {1m 0} -pady {1m 0}
	grid $w.familyY -padx {0 1m} -pady {1m 0}
	grid $w.familyX -padx {1m 0} -pady {0 1m}

	# Font styles.
	foreach {fontstyle lcstyle row next prev} {
	    Bold      bold       0 Italic    {}
	    Italic    italic     1 Underline Bold
	    Underline underline  2 Strikeout Italic
	} {
	    set b $w.style$fontstyle
	    checkbutton $b -variable [namespace current]::Style($lcstyle) \
		    -command [namespace code 'set_font]
	    grid $b -in $w.lblStyle -sticky nsew -row $row -padx 1m
	    grid rowconfigure $w.lblStyle $row -weight 1
	    if {[string length $next]} {
		bind $b <Down> [list focus $w.style$next]
	    }
	    if {[string length $prev]} {
		bind $b <Up> [list focus $w.style$prev]
	    }
	    bind $b <Tab>       "[list focus $w.size8];break"
	    bind $b <Shift-Tab> "[list focus $w.family];break"
	    'set_accel $b $w "focus $b; $b invoke"
	    bind $b <Return> "$b invoke; break"
	}


	# Size adjustment.  Common sizes with radio buttons, and an
	# entry for everything else.
	foreach {size row col u d l r} {
	    8  0 0  {} 10 {} 12
	    10 1 0   8 {} {} 14
	    12 0 1  {} 14  8 18
	    14 1 1  12 {} 10 24
	    18 0 2  {} 24 12 {}
	    24 1 2  18 {} 14 {}
	} {
	    set b $w.size$size
	    radiobutton $b -variable [namespace current]::Size -value $size \
		    -command [namespace code 'set_font]
	    grid $b -in $w.lblSize -row $row -column $col -sticky ew
	    if {[string length $u]} {bind $b <Up>    [list focus $w.size$u]}
	    if {[string length $d]} {bind $b <Down>  [list focus $w.size$d]}
	    if {[string length $l]} {bind $b <Left>  [list focus $w.size$l]}
	    if {[string length $r]} {bind $b <Right> [list focus $w.size$r]}
	    bind $b <Tab>       "[list focus $w.sizeEntry ];break"
	    bind $b <Shift-Tab> "[list focus $w.styleBold];break"
	    'set_accel $b $w "focus $b; $b invoke"
	    bind $b <Return> "$b invoke; break"
	}
	entry $w.sizeEntry -textvariable [namespace current]::Size
	grid $w.sizeEntry -in $w.lblSize -row 0 -column 3 -rowspan 2 \
		-sticky ew -padx 1m
	grid columnconfigure $w.lblSize 3 -weight 1
	bind $w.sizeEntry <Return> \
		[namespace code {'set_font;break}]


	# Sample text.  Note that this is editable
	canvas $w.sample -highlightthickness 0
	grid $w.sample -in $w.lblSample -sticky nsew
	grid columnconfigure $w.lblSample 0 -weight 1
	grid rowconfigure $w.lblSample 0 -weight 1
	if {[llength [info command ::tk::entry]]} {
	    set classicEntry ::tk::entry
	} else {
	    set classicEntry ::entry
	}
	$classicEntry $w.sample.text -background [$w.sample cget -background]
	$w.sample.text insert 0 [option get $w.sample.text text Text]
	$w.sample create window 0 0 -anchor center -window $w.sample.text \
		-tag foo
	bind $w.sample <Configure> {
	    %W coords foo [expr %w/2] [expr %h/2]
	}
                # Font styles.
	foreach {applystyle lcapply row col l r} {
	    Task      task       0 0 {} Titles
	    Titles    titles     0 1 Task Label
            Label     label      0 2 Titles {}
	} {
	    set b $w.applyon$applystyle
	    checkbutton $b -variable [namespace current]::Applyon($lcapply) 
            grid $b -in $w.lblApplyon -row $row -column $col -sticky ew
	    if {[string length $r]} {bind $b <Right> [list focus $w.applyon$r]}
	    if {[string length $l]} {bind $b <Left>  [list focus $w.applyon$l]}
	    bind $b <Tab>       "[list focus $w.size8];break"
	    bind $b <Shift-Tab> "[list focus $w.family];break"
	    'set_accel $b $w "focus $b; $b invoke"
	    bind $b <Return> "$b invoke; break"
	}
        grid columnconfigure $w.lblApplyon 3 -weight 1
	# OK, Cancel and (partially) Apply.  See also 'configure_apply
	frame $w.butnframe
	grid $w.butnframe -row 4 -column 0 -sticky nsew -pady 0 -padx {2m 2m}
	foreach {but code dir target} {
	    ok  0  Down can
	    can 1  Up   ok
	} {
	    set b $w.butnframe.$but
	    button $b -command [namespace code [list set Done $code]]
	    'set_accel $b $w [list $b invoke]
	    pack $b -side left -fill x -padx {0 2m}
	    bind $b <$dir> [list focus $w.butnframe.$target]
	}
	button $w.butnframe.apl
    }
    # Install the accelerator for the given window ($w) on the second
    # given window ($bindwin) as the script ($script).
    proc 'set_accel {w bindwin script} {
	set accel [option get $w accelerator Accelerator]
	if {[string length $accel]} {bind $bindwin <$accel> $script}
    }


    # Called when changing the family.  Sets the family to either be
    # the first family whose name starts with the given character (if
    # char is non-empty and not special) or to be the name of the
    # family at the given index of the listbox.
    proc 'change_family {w index {char {}}} {
	variable Family
	if {[string length $char] && ![regexp {[]*?\\[]} $char]} {
	    set idx [lsearch -glob ['list_families] $char*]
	    if {$idx >= 0} {
		set index $idx
		$w activate $idx
		$w selection clear 0 end
		$w selection anchor $idx
		$w selection set $idx
		$w see $idx
	    }
	}
	set Family [$w get $index]
	##DEBUG
	#wm title [winfo toplevel $w] $Family
	'set_font
    }


    # The apply button runs this script when pressed.
    proc 'do_apply {w script} {
	'set_font
	set font [$w.sample.text cget -font]
        readProperties $font
	uplevel #0 $script [list $font]
    }


    # Based on whether the supplied script is empty or not, install an
    # apply button into the dialog.  This is not part of 'make_UI
    # since it happens at a different stage of initialisation.
    proc 'configure_apply {w script} {
	if {[string length $script]} {
	    # There is a script, so map the button
	    set b $w.butnframe.apl
	    set binding [list $b invoke]

	    array set packinfo [pack info $w.butnframe.ok]
	    $b configure -command [namespace code [list 'do_apply $w $script]]
	    pack $b -side left -fill x -padx $packinfo(-padx) \
		    -pady $packinfo(-pady)

	    bind $w.butnframe.can <Down> [list focus $w.butnframe.apl]
	    bind $w.butnframe.apl <Up>   [list focus $w.butnframe.can]

	    'set_accel $b $w $binding
	}
    }


    # Set the font on the editor window based on the information in
    # the namespace variables.  Returns a 1 if the operation was a
    # failure and 0 if it iwas a success.
    proc 'set_font {} {
	variable Family
	variable Style
	variable Size
	variable Win

	set styles {}
	foreach style {italic bold underline} {
	    if {$Style($style)} {
		lappend styles $style
	    }
	}
	if {[catch {
	    expr {$Size+0}
	    if {[llength $styles]} {
		$Win configure -font [list $Family $Size $styles]
	    } else {
		$Win configure -font [list $Family $Size]
	    }
	} s]} {
	    bgerror $s
	    return 1
	}
	return 0
    }


    # Get a sorted lower-case list of all the font families defined on
    # the system.  A canonicalisation of [font families]
    proc 'list_families {} {
	set fams {}
	foreach f [font families] {
	    # Special hack for my WinXP system...
	    if {[string match @* $f]} continue
	    lappend fams [list $f [string tolower $f]]
	}
	set result {}
	foreach f [lsort -unique -index 1 $fams] {
	    lappend result [lindex $f 0]
	}
	return $result
    }

    # ----------------------------------------------------------------------

    proc dkf_chooseFont {args} {
	variable Family
	variable Style
	variable Size
	variable Done
	variable Win
        variable Applyon
        variable exp_path
        variable datestamp

	array set options {
	    -parent {}
	    -title {Select a font}
	    -initialfont {}
	    -apply {}
            -exp   {}
            -datestamp {}
	}
	'parse_opts $args [array names options] options
	switch -exact -- $options(-parent) {
	    . - {} {
		set parent .
		set w .__dkf_chooseFont
	    }
	    default {
		set parent $options(-parent)
		set w $options(-parent).__dkf_chooseFont
	    }
	}
	catch {destroy $w}

	toplevel $w -class DKFChooseFont
	wm title $w $options(-title)
	wm transient $w $parent
	wm iconname $w ChooseFont
	wm group $w $parent
	wm protocol $w WM_DELETE_WINDOW {DkfFont_close}

	if {![string length $options(-initialfont)]} {
	    set options(-initialfont) [option get $w initialFont InitialFont]
	}

	set Win $w.sample.text
	'make_UI $w
	bind $w <Return>  [namespace code {set Done 0}]
	bind $w <Escape>  [namespace code {set Done 1}]
	bind $w <Destroy> [namespace code {set Done 1}]
	focus $w.butnframe.ok

	'configure_apply $w $options(-apply)

        set exp_path  $options(-exp)
        set datestamp $options(-datestamp)

	foreach style {italic bold underline} {
	    set Style($style) 0
	}
	array set parsing [font actual $options(-initialfont)]
	set family $parsing(-family)
	set size $parsing(-size)
	set styles {}
	foreach {item enabledVal flagname} {
	    -weight bold bold
	    -slant italic italic
	    -underline 1 underline
	} {
	    if {$parsing($item) eq $enabledVal} {
		lappend styles $flagname
	    }
	}
        foreach applyon {task titles label} {
           if {$applyon == "task"} { 
	     set Applyon($applyon) 1
           }
	}
        
	#foreach {family size styles} $options(-initialfont) {break}
	set Family $family
	set familyIndex [lsearch -exact ['list_families] $family]
	if {$familyIndex<0} {
	    wm withdraw $w
	    tk_messageBox -type ok -icon warning -title "Bad Font Family" \
		    -message "Font family \"$family\" is unknown.  Guessing..."
	    set family [font actual $options(-initialfont) -family]
	    set familyIndex [lsearch -exact ['list_families] \
		    [string tolower $family]]
	    if {$familyIndex<0} {
		return -code error "unknown font family fallback \"$family\""
	    }
	    wm deiconify $w
	}
	$w.family selection set $familyIndex
	$w.family see $familyIndex
	set Size $size
	foreach style $styles {set Style($style) 1}

	'set_font

	wm withdraw $w
	update idletasks
	if {$options(-parent)==""} {
	    set x [expr {([winfo screenwidth $w]-[winfo reqwidth $w])/2}]
	    set y [expr {([winfo screenheigh $w]-[winfo reqheigh $w])/2}]
	} else {
	    set pw $options(-parent)
	    set x [expr {[winfo x $pw]+
		    ([winfo width $pw]-[winfo reqwidth $w])/2}]
	    set y [expr {[winfo y $pw]+
		    ([winfo heigh $pw]-[winfo reqheigh $w])/2}]
	}
	wm geometry $w +$x+$y
	update idletasks
	wm deiconify $w
	tkwait visibility $w
	vwait [namespace current]::Done
	if {$Done} {
	    destroy $w
	    return ""
	}
	if {['set_font]} {
	    destroy $w
	    return ""
	}
	set font [$Win cget -font]
	destroy $w
	return $font
    }


    # Load platform-independent and platform-specific resource files
    # based on the current filename.
    proc 'load_resources {filebase} {
        global env
        set dirbase $env(SEQ_XFLOW_BIN)/../etc/constants/
	set filebase [file rootname $filebase]
        set filebase [file tail $filebase]
	option readfile ${dirbase}${filebase}.ad widgetDefault
	set platform $::tcl_platform(platform)
	catch {
	    option readfile ${dirbase}${filebase}_${platform}.ad widgetDefault
	}
    }

    'load_resources [info script]
}
namespace import ::dkfFontSel::dkf_chooseFont

# Is there anything already set up as a standard command?
if {![info exist tk_chooseFont]} {
    # If not, set ourselves up using an alias
    interp alias {} tk_chooseFont {} ::dkfFontSel::dkf_chooseFont
}

proc DkfFont_close {} {
   ::log::log debug "DkfFont_close..."
   wm withdraw [DkfFont_getToplevel]
}

proc DkfFont_show { {force false} } {
   ::log::log debug "DkfFont_show force:${force}"
   set topW [DkfFont_getToplevel]
   set currentStatus [wm state ${topW}]

   if { ${force} == false } {
      switch ${currentStatus} {
         withdrawn -
         iconic {
            wm deiconify ${topW}
         }
      }
      if { [SharedData_getMiscData STARTUP_DONE] == "true" } {
         raise ${topW}
      }
   } else {
      if { [SharedData_getMiscData STARTUP_DONE] == "true" } {
         # force remove and redisplay of msg center
         # Need to do this cause when the msg center is in another virtual
         # desktop, it is the only way for it to redisplay in the
         # current desktop
         wm withdraw ${topW}
         wm deiconify ${topW}
         raise ${topW}
      }
   }
}
proc DkfFont_getToplevel {} {
   return .__dkf_chooseFont
}

# ----------------------------------------------------------------------
# Stuff for testing the font selector
proc DkfFont_init {{_exp_path ""} {_datestamp ""}} {

  set font [dkf_chooseFont -apply "wm title ." -exp $_exp_path -datestamp $_datestamp]
  return
}
