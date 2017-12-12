package require Tk
package require tablelist
package require autoscroll
package require tooltip
package require log

global env
set lib_dir $env(SEQ_XFLOW_BIN)/../lib
# puts "lib_dir=$lib_dir"
set auto_path [linsert $auto_path 0 $lib_dir ]

namespace eval ::trashSel {
    # Use the tile package if it is present...
    if {![catch {package present tile}]} {
	namespace import ::ttk::*
    }
    
    #Jobs will be activated only if occupation is enabled
    proc `Activate_listdate {w opt_item} {
       if { $opt_item == "del1" } {
          $w.datestamp configure -state normal
          for {set i 1} {$i < 7} {incr i} { 
            $w.size$i configure -state disable
          }
          $w.sizeEntry configure -state disable
	} else {
          $w.datestamp configure -state disable
          for {set i 1} {$i < 7} {incr i} { 
            $w.size$i configure -state normal
          }
          $w.sizeEntry configure -state normal
	}
    }

    proc `Datestamp_Refresh {w} {
        global EXP_PATH

        set size [$w.datestamp  size]
        $w.datestamp delete 0 [expr $size - 1]
        
        foreach datestamp ['list_datestamp ${EXP_PATH}] {
	    $w.datestamp insert end $datestamp
	}
    }
    
    proc  Exp_Clean {w {_exp_path ""} } {   
      variable cmd
      
      #set PROGRESS_REPORT_TXT "Cleanup experiment"
      #set progressW [ProgressDlg $w.pcleanup -title "Cleanup experiment" -parent ${w} -textvariable PROGRESS_REPORT_TXT -type incremental -variable 5]

      catch { eval [exec -ignorestderr ksh -c $cmd&]}
      ::log::log debug "Exp_Clean ksh -c $cmd"
      `Datestamp_Refresh $w 

      #destroy ${progressW}
      tk_messageBox -message "${_exp_path} has been cleaned..." \
     	    -title "Clean Experiment" -type ok -icon info
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
	#set cUpper [string toupper [string index $word 0]]
	#set cLower [string tolower [string range $word 1 end]]
        set cUpper [string toupper [string range $word 0 end]]
	return ${cUpper}
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
    namespace export trash_choose

    variable Datestamp 20161123
    variable Size   1
    variable Del    "del1"
    variable Done   0
    variable exp_path 
    variable datestamps
    variable Hostname ""
    variable cmd {}
    variable Option 
    array set Option {
        logs  0
    }
    
    # Build the user interface (except for the apply button, which is
    # handled by the 'configure_apply procedure...
    proc 'make_UI {w {_exp_path ""}} {
	# Labelled frames for the framed boxes & focus accelerators
	# for their contents
	foreach {subname row col cols padx pady focusWin} {
	    Datestamp 0 0 1 1m     2m datestamp
	    Hostname  0 1 1 {0 2m} 2m hostname
	    Size   1 0 2 2m     0  size1
            Option 2 0 2 2m     2m logs
	} {
	    set l [labelframe $w.lbl$subname]
	    grid $l -row $row -column $col -columnspan $cols -sticky nsew \
		    -padx $padx -pady $pady
	    'set_accel $l $w [list focus $w.$focusWin]
	}
	grid columnconfigure $w 0 -weight 1
	grid rowconfigure $w 0 -weight 1

	# Font families
	listbox $w.datestamp -exportsel 0 -selectmode browse \
		-xscrollcommand [list $w.datestampX set] \
		-yscrollcommand [list $w.datestampY set]
	scrollbar $w.datestampX -command [list $w.datestamp xview]
	scrollbar $w.datestampY -command [list $w.datestamp yview]
	foreach datestamp ['list_datestamp ${_exp_path}] {
	    $w.datestamp insert end  $datestamp
	}
	grid columnconfigure $w.lblDatestamp 0 -weight 1
	grid rowconfigure    $w.lblDatestamp 0 -weight 1
	grid $w.datestamp  $w.datestampY -sticky nsew -in $w.lblDatestamp
	grid $w.datestampX            -sticky nsew -in $w.lblDatestamp
	bind $w.datestamp <1> [namespace code {'change_datestamp %W [%W nearest %y]}]
	bindtags $w.datestamp [concat [bindtags $w.datestamp] key$w.datestamp]
	bind key$w.datestamp <Key> [namespace code {'change_datestamp %W active %A}]
	grid $w.datestamp  -padx {1m 0} -pady {1m 0}
	grid $w.datestampY -padx {0 1m} -pady {1m 0}
	grid $w.datestampX -padx {1m 0} -pady {0 1m}

	# Font styles.
        # Font families
	listbox $w.hostname -exportsel 0 -selectmode browse \
		-xscrollcommand [list $w.hostnameX set] \
		-yscrollcommand [list $w.hostnameY set]
	scrollbar $w.hostnameX -command [list $w.hostname xview]
	scrollbar $w.hostnameY -command [list $w.hostname yview]
	foreach hostname ['list_hostnames ${_exp_path}] {
	    $w.hostname insert end $hostname
	}
	grid columnconfigure $w.lblHostname 0 -weight 1
	grid rowconfigure    $w.lblHostname 0 -weight 1
	grid $w.hostname  $w.hostnameY -sticky nsew -in $w.lblHostname
	grid $w.hostnameX            -sticky nsew -in $w.lblHostname
	bind $w.hostname <1> [namespace code {'change_hostname %W [%W nearest %y]}]
	bindtags $w.hostname [concat [bindtags $w.hostname] key$w.hostname]
	bind key$w.hostname <Key> [namespace code {'change_hostname %W active %A}]
	grid $w.hostname  -padx {1m 0} -pady {1m 0}
	grid $w.hostnameY -padx {0 1m} -pady {1m 0}
	grid $w.hostnameX -padx {1m 0} -pady {0 1m}

	# Size adjustment.  Common sizes with radio buttons, and an
	# entry for everything else.
	foreach {size row col u d l r} {
	    1 0 0  {} 2  {} 3
	    2 1 0  1  {} {} 4
	    3 0 1  {} 4  1  5
	    4 1 1  3  {} 2  6
	    5 0 2  {} 6  3  {}
	    6 1 2  4  {} 4  {}
	} {
	    set b $w.size$size
	    radiobutton $b -variable [namespace current]::Size -value $size \
		    -command [namespace code 'set_listcln]
            ::tooltip::tooltip $b "Files older than $size days will be removed"
	    grid $b -in $w.lblSize -row $row -column $col -sticky ew
	    if {[string length $u]} {bind $b <Up>    [list focus $w.size$u]}
	    if {[string length $d]} {bind $b <Down>  [list focus $w.size$d]}
	    if {[string length $l]} {bind $b <Left>  [list focus $w.size$l]}
	    if {[string length $r]} {bind $b <Right> [list focus $w.size$r]}
	    bind $b <Tab>       "[list focus $w.sizeEntry ];break"
	    bind $b <Shift-Tab> "[list focus $w.datestamp];break"
	    'set_accel $b $w "focus $b; $b invoke"
	    bind $b <Return> "$b invoke; break"
	}
	entry $w.sizeEntry -textvariable [namespace current]::Size
	grid $w.sizeEntry -in $w.lblSize -row 0 -column 3 -rowspan 2 \
		-sticky ew -padx 1m
	grid columnconfigure $w.lblSize 2 -weight 1
	bind $w.sizeEntry <Return> \
		[namespace code {'set_listcln ;break}]

        # Font styles.
	foreach {opt_item lcitem row col l r} {
	    Logs    logs 0 0 {}   del1
            del1    del1 0 1 Logs del2
            del2    del2 0 2 del1 {}
	} {
	    set b $w.option$opt_item
            if { $opt_item != "Logs" } {
               radiobutton $b -variable [namespace current]::Del -value $lcitem \
		    -command [namespace code 'set_listcln ]
               bind $b <Button-1> [namespace code [list `Activate_listdate $w $opt_item]]
               if {$opt_item == "del1"} {
                 `Activate_listdate $w $opt_item
               }
            } else {
	       checkbutton $b -variable [namespace current]::Option($lcitem)
            } 
            grid $b -in $w.lblOption -row $row -column $col -sticky ew
	    if {[string length $r]} {bind $b <Right> [list focus $w.option$r]}
	    if {[string length $l]} {bind $b <Left>  [list focus $w.option$l]}
	    bind $b <Tab>       "[list focus $w.size1];break"
            bind $b <Shift-Tab> "[list focus $w.datestamp];break"
	    'set_accel $b $w "focus $b; $b invoke"
	    bind $b <Return> "$b invoke; break"
	}
        grid columnconfigure $w.lblOption 2 -weight 1

	# OK, Cancel and (partially) Apply.  See also 'configure_apply
	frame $w.butnframe
	grid $w.butnframe -row 4 -column 0 -sticky nsew -pady 0 -padx {2m 2m} 
	foreach {but code dir target} {
	    can 0  Down cln
	    cln 1  Up   can
	} {
	    set b $w.butnframe.$but
	    button $b -command [namespace code [list set Done $code]]
	    'set_accel $b $w [list $b invoke]
	    pack $b  -side left -fill x -padx {0 2m} 
	    bind $b <$dir> [list focus $w.butnframe.$target]
	}

    }
    # Install the accelerator for the given window ($w) on the second
    # given window ($bindwin) as the script ($script).
    proc 'set_accel {w bindwin script} {
	set accel [option get $w accelerator Accelerator]
	if {[string length $accel]} {bind $bindwin <$accel> $script}
    }


    # Called when changing the datestamp.  Sets the datestamp to either be
    # the first datestamp whose name starts with the given character (if
    # char is non-empty and not special) or to be the name of the
    # datestamp at the given index of the listbox.
    proc 'change_datestamp {w index {char {}} {_exp_path ""}} {
        global  EXP_PATH
	variable Datestamp

	if {[string length $char] && ![regexp {[]*?\\[]} $char]} {
	    set idx [lsearch -glob ['list_datestamp ${EXP_PATH}] $char*]
	    if {$idx >= 0} {
		set index   $idx
		$w activate $idx
		$w selection clear 0 end
		$w selection anchor $idx
		$w selection set $idx
		$w see $idx
	    }
	}
	set Datestamp [$w get $index]
	##DEBUG
	#wm title [winfo toplevel $w] $Datestamp
	'set_listcln ${EXP_PATH}
    }
    # Called when changing the datestamp.  Sets the datestamp to either be
    # the first datestamp whose name starts with the given character (if
    # char is non-empty and not special) or to be the name of the
    # datestamp at the given index of the listbox.
    proc 'change_hostname {w index {char {}} {_exp_path ""}} {
        global  EXP_PATH
	variable Hostname
        
	if {[string length $char] && ![regexp {[]*?\\[]} $char]} {
	    set idx [lsearch -glob ['list_hostnames ${EXP_PATH}] $char*]
	    if {$idx >= 0} {
		set index   $idx
		$w activate $idx
		$w selection clear 0 end
		$w selection anchor $idx
		$w selection set $idx
		$w see $idx
	    }
	}
	set Hostname [$w get $index]
	##DEBUG
	#wm title [winfo toplevel $w] $Datestamp
	'set_listcln ${EXP_PATH}
    }


    # The apply button runs this script when pressed.
    proc 'do_Clnexp {w script {_exp_path ""}} {
	set cmd ['set_listcln ${_exp_path}]
        
        Exp_Clean $w ${_exp_path}
	uplevel #0 $script
    }


    # Based on whether the supplied script is empty or not, install an
    # apply button into the dialog.  This is not part of 'make_UI
    # since it happens at a different stage of initialisation.
    proc 'configure_apply {w script {_exp_path ""}} {
	if {[string length $script]} {
	    # There is a script, so map the button
	    set b $w.butnframe.cln
	    set binding [list $b invoke]

	    array set packinfo [pack info $w.butnframe.can]
	    $b configure -command [namespace code [list 'do_Clnexp $w $script ${_exp_path}]]
	    pack $b -side left -fill x -padx $packinfo(-padx) \
		    -pady $packinfo(-pady) 

	    bind $w.butnframe.can <Down> [list focus $w.butnframe.cln]
	    bind $w.butnframe.cln <Up>   [list focus $w.butnframe.can]

	    'set_accel $b $w $binding
	}
    }

    # Set the font on the editor window based on the information in
    # the namespace variables.  Returns a 1 if the operation was a
    # failure and 0 if it iwas a success.
    proc 'set_listcln {{_exp_path ""}} {
        variable Option
	variable Datestamp
	variable Hostname
	variable Size
        variable Del
        variable cmd
      
        set cmd  {}
	if {[catch {
           if { $Option(logs) && ${Del} == "del2"} { 
              set cmd [list expclean -e ${_exp_path} -t $Size -m $Hostname -l 1]
           } elseif { $Option(logs) && ${Del} == "del1"} {
              set cmd [list expclean -e ${_exp_path} -d $Datestamp -m $Hostname -l 1]
           } elseif { !$Option(logs) && ${Del} == "del2"} {
              set cmd [list expclean -e ${_exp_path} -t $Size -m $Hostname]
           } elseif { !$Option(logs) && ${Del} == "del1"} {
              set cmd [list expclean -e ${_exp_path} -d $Datestamp -m $Hostname]
           } else {
              set cmd [list expclean -e ${_exp_path} -d $Datestamp -m $Hostname]
           } 
	} s]} {
	    bgerror $s
	    return 1
	}
	return 0
    }
    # Get a sorted lower-case list of all the font families defined on
    # the system.  A canonicalisation of [font families]
    proc 'list_datestamp {{exp_path ""}} {
        set result {}
        set files [glob -nocomplain -type f ${exp_path}/logs/*nodelog]
        if { [llength $files] > 0 } {
          foreach f [lsort $files] {
             lappend result [lindex  [split [file tail [lindex $f 0]] "_"] 0]
          }
        } 
	return $result
    }
     # Get a sorted lower-case list of all the font families defined on
    # the system.  A canonicalisation of [font families]
    proc 'list_hostnames {{exp_path ""}} {
        set result {}
        set result all

        set files [glob -nocomplain -type d ${exp_path}/listings/*]
        if { [llength $files] > 0 } {
          foreach f [lsort $files] {
             if {![string match "*latest*" $f]} {
               set     value   [lindex  [split [file tail [lindex $f 0]] "_"] 0]
               lappend result  $value
             }
          }
        }
	return $result
    }

    # ----------------------------------------------------------------------

    proc trash_choose {args} {
        global env
	variable Datestamp
	variable Hostname
        variable cmd
	variable Size
	variable Done
	variable Option
        variable exp_path
        variable datestamps

	array set options {
	    -parent {}
	    -title {Clean an experiment}
	    -initialDatestamp {}
            -initialHostname {}
	    -apply {}
            -exp   {}
            -datestamps {}
	}
	'parse_opts $args [array names options] options
	switch -exact -- $options(-parent) {
	    . - {} {
		set parent .
		set w .__trash_choose
	    }
	    default {
		set parent $options(-parent)
		set w $options(-parent).__trash_choose
	    }
	}
	catch {destroy $w}

	toplevel $w -class TRASHChoose
	wm title $w $options(-title)
	wm transient $w $parent
	wm iconname $w Choose
	wm group $w $parent
	wm protocol $w WM_DELETE_WINDOW {Trash_close}

	if {![string length $options(-initialDatestamp)]} {
	    set options(-initialDatestamp) [option get $w initialDatestamp InitialDatestamp]
	}
        if {![string length $options(-initialHostname)]} {
	    set options(-initialHostname) [option get $w initialHostname InitialHostname]
	}
        set exp_path   $options(-exp)
        set datestamps $options(-datestamps)
       
        set Option(logs) 1
	'make_UI $w ${exp_path}
	bind $w <Return>  [namespace code {set Done 0}]
	bind $w <Escape>  [namespace code {set Done 1}]
	bind $w <Destroy> [namespace code {set Done 1}]
	focus $w.butnframe.can

	'configure_apply $w $options(-apply) ${exp_path}

        set datestamp $options(-datestamps)
	
	set Datestamp $datestamp
        if {[llength ['list_datestamp ${exp_path}]]} { 
           $w.datestamp selection set 0
	   $w.datestamp see 0
        }
        set Hostname "all"
        if {[llength ['list_hostnames ${exp_path}]]} { 
	  $w.hostname selection set 0
	  $w.hostname see 0
        }
	set Size 1
        set Del  "del1"
        set cmd {}

	'set_listcln ${exp_path}

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
	if {['set_listcln ${exp_path}]} {
	    destroy $w
	    return ""
	}
	destroy $w
	return $Done
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
namespace import ::trashSel::trash_choose


proc Trash_close {} {
   ::log::log debug "Tash_close..."
   wm withdraw [Trash_getToplevel]
}

proc Trash_show { {force false} } {
   ::log::log debug "Trash_show force:${force}"
   set topW [Trash_getToplevel]
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
proc Trash_getToplevel {} {
   return .__trash_choose
}

# ----------------------------------------------------------------------
# Stuff for testing the font selector
proc Trash_init {{_exp_path ""} {_datestamp ""}} {
  global EXP_PATH

  set EXP_PATH $_exp_path
  set result  [trash_choose -apply "wm title ." -exp $_exp_path -datestamps $_datestamp]
  return
}
