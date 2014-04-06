set userdb  "./scripts/usersystem/user.db"
set channel "#habrahabr"

### the bot's account (in userdb)
set botuser "bot1"

bind msg  - -hidden-register register
bind msg  - -hidden-identify identify
bind mode - * modechange
bind pub  - reinterpretuserdb getusers
bind pub  - regainoperators setupmodes
bind time - "* * * * *" setupmodes

set users { }

### bot's nick
global username
set botnickname $username

proc register {nick userhost handle query} {
	global userdb

	### new user entry
	set userstr "$nick [lindex [split $query] 0] no"

	### adding it to userdb
	set userdbfl [open $userdb a+]
	puts $userdbfl $userstr
	flush $userdbfl
	close $userdbfl

	### reporting user ev.thing's ok
	set reply "Registered you, $nick, with password [lindex [split $query] 0]."
	puthelp "PRIVMSG $nick :$reply"

	### rereading the userdb
	getusers
}

proc identify {nick userhost handle query} {
	global users
	set login    [lindex [split $query] 0]
	set password [lindex [split $query] 1]
	for {set i 0} {$i<[llength $users]} {incr i} {
		set user [lindex $users $i]
		if {$login==[dict get $user name]} {
			if {[dict get $user password]==$password} {
				dict set user idented $login
				set users [lreplace $users $i $i $user]
				puthelp "PRIVMSG $nick :Identified you successfully as $login."
				setupmodes
				return
			}
		}
	}
	puthelp "PRIVMSG $nick :Identification failed. Try checking the your password."
}

proc getusers {args} {
	global userdb users botuser botnickname
	set users { }

	### reading users database
	set userdbfl [open $userdb r+]
	foreach userstr [split [read -nonewline $userdbfl] "\n"] {
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

proc setupmodes {args} {
	global users channel
	putlog "Regaining ops on channel $channel..."

	### opping everyone who should be opped
	foreach user $users {
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

getusers