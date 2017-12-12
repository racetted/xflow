proc TextEditor_bottom {w} {
    scan [$w.text index end] %d numlines
    $w.text yview -pickplace $numlines

}

proc TextEditor_linewrap {w} {
  
   global LINEWRAP
   if { $LINEWRAP($w) == 1 } {
       $w.text configure -wrap word
   } else {
       $w.text configure -wrap none
   }
}

proc TextEditor_search {w new_search} {

   global TEXTSEARCH_OFFSET SEARCHSTRING

   set string $SEARCHSTRING($w)
   # make sure that "SEARCHSTRING" is not empty
   if { $string == "" } {
      Utils_raiseError $w "Search String" "You must specify a string"
      return
   }

   if { $new_search } {
      ::log::log debug "TextEditor_search resetting search offset"
      set TEXTSEARCH_OFFSET($w) 1.0
      set offset $TEXTSEARCH_OFFSET($w)
   } else {
      ::log::log debug "TextEditor_search NOT resetting search offset"
      set offset $TEXTSEARCH_OFFSET($w)
   }

   set index [$w.text search -forw -nocase $string $offset]

   # not found
   if { $index == "" } {
      after 1 [list Utils_raiseError $w "Search String" "Could not find \"$string\""]
      return
   }

   # define colours for selected text
   set selectForeground [$w.text cget -background]
   set selectBackground [$w.text cget -foreground]

   # not found in remainder of the file
   set index_list [split $index .]
   set offset_list [split $offset .]

   set integer1 [lindex $index_list 0]
   set remainder1 [lindex $index_list 1]
   set integer2 [lindex $offset_list 0]
   set remainder2 [lindex $offset_list 1]

   if { ($integer1 < $integer2) || ($integer1 == $integer2 && $remainder1 < $remainder2) } {
      after 1 [list Utils_raiseError $w "Could not find \"$string\"" "Address search hit BOTTOM \
               without matching pattern"]
      return
   }

   $w.text see $index
   set index2 [expr [lindex $index_list 1] + [string length $string]]
   set TEXTSEARCH_OFFSET($w) "[lindex $index_list 0].$index2"
   $w.text tag add found $index $TEXTSEARCH_OFFSET($w)
   $w.text tag configure found -background $selectBackground \
                           -foreground $selectForeground \
                           -relief raised -borderwidth 2
}

proc TextEditor_createWindow {title tmpfile {position top} {calling_widget .}} {

   global TEXTSEARCH_OFFSET SEARCHSTRING LINEWRAP DEFAULT_COLORS FONTS
   global LEFT_ARROW_IMG RIGHT_ARROW_IMG LEFT_ENDARROW_IMG RIGHT_ENDARROW_IMG
   ::log::log debug "TextEditor_createWindow title:$title tmpfile:${tmpfile}"

   #example: change the title from 'iclogj -h 36 {{e1up168_00_1  }}' to 'iclogj -h 36 e1up168_00_1  '
   regsub -all "\{\{" $title {} title
   regsub -all "\}\}" $title {} title
   regsub -all "'" $title "" title
   regsub -all "\{" $title "" title
   regsub -all "\}" $title "" title
 
   # replace all blanks with underlines
   regsub -all " " [string trimright $title] _ win
   regsub -all "/" $win _ win
   regsub -all {[\.]} $win _ win
      
   set w .text_${win}
   set LINEWRAP($w) 0
   set TEXTSEARCH_OFFSET($w) 1.0
   set TEXT_WINDOW($title) $w
   set SEARCHSTRING($w) ""
   
   # if the window already exists, destroy it
   if { [winfo exists $w] } {
      destroy $w
   }

   toplevel $w

   wm minsize $w 500 100
   wm title $w $title
   Utils_positionWindow ${w} ${calling_widget}
   
   # menubar widget
   frame $w.mbar -relief raised -bd 2
   pack $w.mbar -fill x

   # menubar button
   button $w.mbar.quit -text Quit -command [list destroy $w]
   pack $w.mbar.quit -side left -pady .5m -padx 1m
   
   # create a frame to hold "Search string:",an entry widget and a 
   # couple of buttons
   frame $w.mbar.search
   pack $w.mbar.search -side left -padx 1m -pady .5m -expand 1 -fill x
   
   label $w.mbar.search.label -text "Search String:"
   entry $w.mbar.search.entry -width 20 -relief sunken -bd 2 -textvariable SEARCHSTRING($w)
   button $w.mbar.next -text Next -command [list TextEditor_search $w 0]
   
   # "linewrap" checkbutton allows the user to toggle linewrap on/off
   checkbutton $w.mbar.linewrap -text "linewrap" \
      -variable LINEWRAP($w) -onvalue 1 -offvalue 0 \
      -command [list TextEditor_linewrap $w]

   # "top" button positions the text widget so that the first line
   # is visible
   button $w.mbar.top -text Top -command [list $w.text yview -pickplace 0]

   # "bottom" button positions the text widget so that the last line
   # is visible
   button $w.mbar.bottom -text Bottom -command [list TextEditor_bottom $w]
   pack $w.mbar.search.label -side left
   pack $w.mbar.search.entry -side left -expand 1 -fill x 
   pack $w.mbar.next $w.mbar.linewrap $w.mbar.top $w.mbar.bottom -side left -padx 1m
   
   # Set a <return> binding to accept the search string
   bind $w.mbar.search.entry <Return> [list TextEditor_search $w 1]
   
   # set the focus to the entry widget
   focus $w.mbar.search.entry

   frame $w.tframe
   pack $w.tframe -fill both -expand 1
   
   #text widget with scrollbar
   text $w.text -relief raised -bd 2 -yscrollcommand [list $w.txt_yscroll set] \
      -xscrollcommand [list $w.txt_xscroll set] -undo 0 -wrap none
   scrollbar $w.txt_yscroll -command "$w.text yview"
   scrollbar $w.txt_xscroll -command "$w.text xview" -orient horizontal
   ::autoscroll::autoscroll $w.txt_yscroll
   ::autoscroll::autoscroll $w.txt_xscroll

   pack $w.txt_yscroll -side left -fill y -in $w.tframe

   pack $w.text -side left -fill both -expand yes -in $w.tframe
   
   Utils_bindMouseWheel $w.text 5
   set pad [expr [$w.txt_yscroll cget -width] + 2 * [$w.txt_yscroll cget -bd] + \
      [$w.txt_yscroll cget -highlightthickness]]

   frame $w.pad -width $pad -height $pad

   pack $w.pad -side left
   pack $w.txt_xscroll -side left -fill x -expand 1

   if [catch {open "$tmpfile" "r"} fileId] {
      puts stderr "Cannot open $tmpfile: $fileId"
      return 0
   } else {
      set endof_file 0
      set filesize [file size $tmpfile]
      ::log::log debug "file size of $tmpfile $filesize bytes"
      set maxSize 4000000
      set readChunkSize 400
      if { $filesize > $maxSize } {
         #read only the last $maxSize bytes if the file is too big
         
         set UP_ENDARROW_IMG .up_endarrow_image
         set DOWN_ENDARROW_IMG .down_endarrow_image
         set LEFT_ENDARROW_IMG .left_endarrow_image
         set RIGHT_ENDARROW_IMG .right_endarrow_image
         set LEFT_ARROW_IMG .left_arrow_image
         set RIGHT_ARROW_IMG .right_arrow_image

	 set imageDir [SharedData_getMiscData IMAGE_DIR]
         image create photo $DOWN_ENDARROW_IMG -file ${imageDir}/endarrow.small.down.ppm
         image create photo $UP_ENDARROW_IMG -file ${imageDir}/endarrow.small.up.ppm
         image create photo $LEFT_ENDARROW_IMG -file ${imageDir}/endarrow.small.left.ppm
         image create photo $RIGHT_ENDARROW_IMG -file ${imageDir}/endarrow.small.right.ppm
         image create photo $LEFT_ARROW_IMG -file ${imageDir}/arrow.small.left.ppm
         image create photo $RIGHT_ARROW_IMG -file ${imageDir}/arrow.small.right.ppm

         set downArrow $w.mbar.downArrow
         button $downArrow -image $LEFT_ARROW_IMG \
            -command [list getNextPage $w $fileId $position $readChunkSize 0]
            
         set startArrow $w.mbar.startArrow
         button $startArrow -image $LEFT_ENDARROW_IMG \
            -command [list goFirstPage $w $fileId $position $readChunkSize]
            
         set upArrow $w.mbar.upArrow
         button $upArrow -image $RIGHT_ARROW_IMG \
            -command [list getNextPage $w $fileId $position $readChunkSize 1]
         
         set endArrow $w.mbar.endArrow
         button $endArrow -image $RIGHT_ENDARROW_IMG \
            -command [list goLastPage $w $fileId $position $readChunkSize]
         
         pack $startArrow $downArrow $upArrow $endArrow -side left
            
         getNextPage $w $fileId $position $readChunkSize 1
      } else {
         getNextPage $w $fileId $position all 1
      }
   }
   $w.mbar.quit configure -command [list destroyTextWindow $w $fileId]
   $w.text configure -state disabled
   $w.mbar.numlines configure 
}

proc destroyTextWindow { w file_id } {
   catch { close $file_id }
   destroy $w
}

proc goFirstPage { w file_id position num_of_lines } {
   seek $file_id 0 start
   getNextPage $w $file_id $position $num_of_lines 0]
}

proc goLastPage { w file_id position num_of_lines } {
   seek $file_id -2048 end
   getNextPage $w $file_id $position $num_of_lines 1]
}

proc getNextPage { w file_id position {num_of_lines all} {up_or_down 1} } {
   global ${w}_PREVIOUS_OFFSET
   
   $w.text configure -state normal
   set linePerPage 50
   set getAll 0
   if { !($num_of_lines == "all") } {
      set linePerPage $num_of_lines
   } else {
      set getAll 1
   }
   set count 0
   set endof_file 0
   set mapList {  \\010 \b
                  \\011 \t
                  \\012 \n
                  \\013 \v
                  \\014 \f
                  \\015 \r
                  \\0300 À
                  \\0307 Ç
                  \\0310 È
                  \\0311 É
                  \\0312 Ê
                  \\0313 Ë
                  \\0340 à
                  \\0341 á
                  \\0342 â
                  \\0347 ç
                  \\0350 è
                  \\0351 é
                  \\0352 ê
                  \\0371 ù }
   $w.text delete 0.0 end
   set disableStart 0
   if { !$getAll } {
      if { [tell $file_id] == 0 } {
         set disableStart 1
      }
      set nextOffset [expr 2048*$num_of_lines]
      if { $up_or_down == "0" } {
         # where in previous mode, go to backup value
         set currentOffset [tell $file_id]
         set offsetToGo [expr 2*2048*$num_of_lines]
         if { $offsetToGo > $currentOffset } {
            seek $file_id 0 start
            set disableStart 1
         } else {
            seek $file_id -$offsetToGo current
         }
      }
      # we want to start reading on the next newline      
      # unless we are at the first line      
      set newLineFound 0
      set offsetcount 0
      while { !$newLineFound && ([tell $file_id] != 0)} {
         set char [read $file_id 1]
         if { $char == "\n" } {
            set newLineFound 1
         } elseif { [tell $file_id] != 0 } {
            incr offsetcount -1
            catch { seek $file_id $offsetcount current } {
               seek $file_id 0 start
            }
         }
      }
      # start reading
      while { ($count < $linePerPage) && !$endof_file } {
         set line [read $file_id 2048]
         $w.text insert end [string map $mapList $line]
      
         # I am adding a newline whenever the line is too long. This to prevent TCL to abort when adding extremely long line to the text widget.
         if {[string match *\n* $line] == 0} {
            $w.text insert end "\n"
         }
         set endof_file [eof $file_id]
         if { !($num_of_lines == "all") } {
            incr count
         }
      }
      # we want to stop reading on the next newline if it's next
      # this code is working for the next, put this back if it doesn't work
      set newLineFound 0
      while { !$newLineFound && !$endof_file} {
         set char [read $file_id 1]
         if { $char == "\n" } {
            set newLineFound 1
         }
         $w.text insert end [string map $mapList $char]
         set endof_file [eof $file_id]
      }

      ::log::log debug "getNextPage file offset after read:[tell $file_id]"
      set currentOffset [tell $file_id]
      if { [winfo exists $w.mbar.upArrow] } {
         if { $disableStart } {
            $w.mbar.downArrow configure -state disabled
            $w.mbar.startArrow configure -state disabled
         } else {
            $w.mbar.downArrow configure -state normal
            $w.mbar.startArrow configure -state normal
         }
      }
      if { [winfo exists $w.mbar.upArrow] } {
         if { $endof_file } {
            $w.mbar.upArrow configure -state disabled
            $w.mbar.endArrow configure -state disabled
         } else {
            $w.mbar.upArrow configure -state normal
            $w.mbar.endArrow configure -state normal
         }
      }
   } else {
         while {$endof_file == 0} {
            set line [read $file_id 2048]
            $w.text insert end [string map $mapList $line]
   
            # I am adding a newline whenever the line is too long. This to prevent TCL to abort when adding extremely long line to the text widget. 
            if {[string match *\n* $line] == 0} {
               $w.text insert end "\n"
            }
            set endof_file [eof $file_id]
         }
   }
   scan [$w.text index end] %d numlines
   if { ![winfo exists $w.mbar.numlines] } {
      label $w.mbar.numlines
   }
   $w.mbar.numlines configure -text "Lines:$numlines"
   pack $w.mbar.numlines -side left
   
   $w.text configure -state disabled
   
   # position the text widget according to $position {top or bottom}
   if { $position == "bottom" } {
      # position the widgit so that the last few lines are visible
      $w.text yview -pickplace [expr $numlines]
   }
}

proc TextEditor_goKonsole { _binary_path _title _command } {
   ::log::log debug "TextEditor_goKonsole ${_binary_path} ${_command}"
   #eval exec ${_binary_path} -T \"${_title}\" -e ${_command} &
   eval exec -ignorestderr ${_binary_path} ${_command} &
}
