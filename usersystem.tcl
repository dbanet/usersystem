############################
##### START OF GLOBALS #####
############################

set userdb  "./scripts/usersystem/user.db" ;# path to user database on disk (should be r/w)
set channel "#habrahabr"                   ;# currently this script can support only one channel
set botuser "bot1"                         ;# the bot's account's name in userdb (there should be one)
global username                            ;# the bot's nick on the IRC (a global eggdrop variable)
set botnickname $username                  ;# if $username one time stops working... ;)
set users { }                              ;# where userdb gets parsed (the actual struct bot works with)

######################
### END OF GLOBALS ###
######################
### START OF BINDS ###
######################

#####################################################
#### TYPE #### FLAG #### MASK         #### PROC  ####
#####################################################
#=================PRIVATE COMMANDS===================
bind msg       -         register          register
bind msg       -         identify          identify
bind msg       -         forget            forget
bind msg       -         whoami            whoami

#=================PUBLIC COMMANDS====================
bind pub       -         reinterpretuserdb getusers
bind pub       -         regainoperators   setupmodes

#==================MISCELLANEOUS=====================
bind time      -         "* * * * *"       setupmodes
bind mode      -         *                 modechange
bind nick      -         *                 nickchange
bind part      -         *                 userexit
bind sign      -         *                 userexit
#####################################################

######################
###  END OF BINDS  ###
######################
### START OF PROCS ###
######################

#/**
# * Adds a new user entry (a line) to the $userdb file (global, should be
# * set up), and reparses the $userdb file to the $users list of the User
# * dictionaries (by calling the 'getusers' function).
# */
proc register {nick userhost handle query} {
	global userdb users

	### checking if a user is already registered"
	if {[lsearch $users "name $nick*"]!=-1} {
		puthelp "NOTICE $nick :Someone has already registered with username $nick, registration failed."
		return
	}

	### checking if a user is already identified
	if {[set user [identified $nick]]!=0} {
		puthelp "NOTICE $nick :You are already identified as [dict get $user name], you cannot proceed. Logoff first."
		return
	}

	### all good, forming the new user entry
	set userstr "$nick [lindex [split $query] 0] no"

	### adding it to the userdb
	set userdbfl [open $userdb a+]
	puts $userdbfl $userstr
	flush $userdbfl
	close $userdbfl

	### reporting user ev.thing's ok
	puthelp "NOTICE $nick :Registered you, $nick, with password [lindex [split $query] 0]."

	### adding the new user's User dictionary to the global list $users (part of proc 'getusers')
	set user [dict create]
	dict set user name     [lindex [split $userstr] 0]
	dict set user password [lindex [split $userstr] 1]
	dict set user aop      [lindex [split $userstr] 2]
	dict set user idented  0
	lappend users $user
}

#/**
# * Identifies the user by checking if the specified username and password
# * contains in any of the User dicitionaries in the global $user list of User
# * dictionaries. If so, sets the User dictionary's IDENTED field to the $nick
# * (first argument) of the logging in user.
# *
# * @param nick the nick of the logging in user.
# */
proc identify {nick userhost handle query} {
	global users
	set login    [lindex [split $query] 0]
	set password [lindex [split $query] 1]
	for {set i 0} {$i<[llength $users]} {incr i} {
		set user [lindex $users $i]
		if {$login==[dict get $user name]} {
			if {[dict get $user password]==$password} {
				dict set user idented $nick
				set users [lreplace $users $i $i $user]
				puthelp "NOTICE $nick :Identified you successfully as $login."
				setupmodes
				return
			}
		}
	}
	puthelp "NOTICE $nick :Identification failed. Try checking the password."
}

#/**
# * If the user is currently identified, alters the 'idented'
# * field in his User dictionary to 0 (logoff).
# * If not, private messages the user about the error.
# */
proc forget {nick userhost handle query} {
	global users
	### this code basically MODIFIES the User struct (getting the pointer to it,
	### not a copy (which foreach does), so that's why is it so complicated
	### (for with iterator, set users [lreplace ...] etc...
	for {set i 0} {$i<[llength $users]} {incr i} {
		set user [lindex $users $i]
		if {$nick==[dict get $user idented]} {
			dict set user idented 0
			### this  replaces THE old User struct in $users list with the modified one
			set users [lreplace $users $i $i $user]
			puthelp "NOTICE $nick :Logoff was successfull."
			setupmodes
			return
		}
	}
	puthelp "NOTICE $nick :Logoff was unsuccessfull. Did you change your nick?"
}

#/**
# * Checks if the user is currently identified as someone,
# * and if it is, private messages him with the username.
# */
proc whoami {nick userhost handle query} {
	if {[set user [identified $nick]]!=0} {
		puthelp "NOTICE $nick :[dict get $user name]"
	} else {
		puthelp "NOTICE $nick :You are not identified."
	}
}

#/**
# * Parses the user databse file $userdb (global, should be set) and fills
# * the global list $users with Users dictionary (name, password, aop, idented=0).
# * The contents of file $userdb must conform to the following: each line of the
# * file describes one user and ends with CRLF. Its syntax is as follows:
# *     name password aop
# * where 'name', 'password' and 'aop' are substrings of non-space (0x20) characters
# * specifying the 'name', 'password' and 'aop' fields in the User dictionary.
# */
proc getusers {args} {
	global userdb users botuser botnickname
	set users { }

	### reading users database
	set userdbfl [open $userdb r+]
	foreach userstr [split [read -nonewline $userdbfl] "\n"] {
		set user [dict create]
		dict set user name     [lindex [split $userstr] 0]
		dict set user password [lindex [split $userstr] 1]
		dict set user aop      [lindex [split $userstr] 2]
		dict set user idented  0

		### auto-identifing myself
		if {[dict get $user name]==$botuser} {dict set user idented $botnickname}

		lappend users $user
	}
	close $userdbfl
}

#/**
# * This procedure should be called every time a user mode change
# * on a channel occurs.
# *
# * It ignores any mode change, that is not -o or +o, and just returns.
# * If the bot itself gets opped (+o on $botnickname (global, should be set)),
# * calls setupops.
# *
# * If an udentified, or identified but with AOP flag not set to 'NO' user
# * gets +o, deops the user, and public messages the modechanger that this
# * is not allowed.
# *
# * If an identified user WITH AOP flag set to 'YES' gets an operator mode
# * (+o), does nothing and returns.
# *
# * If an identified user WITH AOP flag set to 'YES' gets DEOPPED (-o),
# * ops the user, and public messages the modechanger that this is not allowed.
# *
# * @param nick     the nick   of the modechanger
# * @param userhost the uhost  of the modechanger
# * @param hangle   the hangle of the modechanger
# * @param mode     the mode that has just been applied (matches to (^[+-].$))
# * @param target   the nick of the user the mode gets applied to
# */
proc modechange { nick userhost handle channel mode target } {
	global users botnickname

	### we ignore non-operator mode changes
	if {$mode!="+o"&&$mode!="-o"} { return }
	putlog "Attention! Operator mode changed!"

	### if the bot gets opped, just regainoperators
	if {$target==$botnickname} { setupmodes; return }

	### now checking the legitimity of this change
	foreach user $users {
		if {$target==[dict get $user idented]} {
			if {[dict get $user aop]=="yes"} {
				set usermustbeopped 1
			}
		}
	}

	### now, if something is illegal, fixing this, and punishing hooligans
	if {[info exist usermustbeopped]} {
		if {$mode=="-o"} {
			pushmode  $channel +o $target
			#punishments are not ready yet#pushmode  $channel -o $nick
			flushmode $channel
			puthelp  "PRIVMSG $channel :$nick, this is not allowed."
		}
	} else {
		if {$mode=="+o"} {
			pushmode  $channel -o $target
			#punishments are not ready yet#pushmode  $channel -o $nick
			flushmode $channel
			puthelp  "PRIVMSG $channel :$nick, this is not allowed."
		}
	}
}

#/**
# * Checks, that everyone, who should be opped (means, who is
# * currently identified, and has the AOP flag set to YES), are
# * opped, and who should NOT be opped, are NOT opped.
# *
# * If this is not true, deops and/or ops users for this to become true.
# */
proc setupmodes {args} {
	global users channel botuser botnickname
	putlog "Regaining ops on channel $channel..."

	### opping everyone who should be opped
	foreach user $users {
		if {[dict get $user name]==$botuser} {dict set user idented $botnickname}
		putlog "User [dict get $user name] is identified as [dict get $user idented]"
		if {[dict get $user idented]!=0 && [dict get $user aop]=="yes"} {
			pushmode $channel +o [dict get $user idented]
		}
	}

	### deopping everyone who's opped but shouldn't be opped
	foreach oper [split [chanlist $channel]] {
		if {![isop $oper $channel]} { continue }
		set deopthisoper 1
		foreach user $users {
			if {$oper==[dict get $user idented] && [dict get $user aop]=="yes"} {
				set deopthisoper 0
			}
		}
		if {$deopthisoper} {pushmode $channel -o $oper}
	}

	flushmode $channel
}

#/**
# * Handles nickchanges, should be called every nick change.
# * Checks if a user that changes the nick is identified, and if he/she is,
# * alters his/her 'name' field in his/her User dictionary to the new nick.
# */
proc nickchange {nick userhost handle channel newnick} {
	global users
	if {[identified $nick]!=0} {
		### Find the User struct and set 'idented' to $newnick
		for {set i 0} {$i<[llength $users]} {incr i} {
			set user [lindex $users $i]
			if {$nick==[dict get $user idented]} {
				dict set user idented $newnick
				set users [lreplace $users $i $i $user]
				puthelp "NOTICE $newnick :Nick change was handled successfully, you are still identified as [dict get $user name]."
				return
			}
		}
	}
}

#/**
# * Returns the User dictionary if there is a user identified
# * for the specified nick, returns 0 otherwise.
# */
proc identified {nick} {
	global users
	foreach user $users {
		if {[dict get $user idented]==$nick} {
			return $user
		}
	}
	return 0
}

#/**
# * Handles parts and sign offs, should be called every such event.
# * Checks if an exitted (parted or signed off) user was identified, and if
# * he/she was, sets his/her 'idented' field in his/her User dictionary to 0.
# */
proc userexit {nick userhost handle channel reason} {
	global users
	if {[identified $nick]!=0} {
		### Find the User struct and set 'idented' to 0
		for {set i 0} {$i<[llength $users]} {incr i} {
			set user [lindex $users $i]
			if {$nick==[dict get $user idented]} {
				dict set user idented 0
				set users [lreplace $users $i $i $user]
				return
			}
		}
	}
}

####################
### END OF PROCS ###
####################

getusers