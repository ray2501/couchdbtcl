package require base64
package require sha1

package provide myoauth 1.0

#
# source code is from http://wiki.tcl.tk/27608
#
namespace eval oauth {
    variable secret "" tagstr
    set tagstr 0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ

    namespace ensemble create -subcommands {secret auth}
}

proc oauth::secret {str} {
    variable secret $str
}

proc oauth::random {max} {
    return [expr {entier(rand() * $max)}]
}

proc oauth::tag {len {pfx ""} {str ""}} {
    variable tagstr
    if {$str eq ""} {set str $tagstr}
    for {set max [string length $str]} {$len > 0} {incr len -1} {
        append pfx [string index $str [random $max]]
    }
    return $pfx
}

proc oauth::escape {str} {
    set map {}
    foreach c [lsort -unique [regexp -all -inline {[^a-zA-Z0-9._~-]} $str]] {
        lappend map $c [format %%%02X [scan $c %c]]
    }
    return [string map $map $str]
}

proc oauth::encode {args} {
    if {[llength $args] == 1} {
        set args [lindex $args 0]
    }
    set pairs {}
    foreach {n v} $args {
        lappend pairs [escape $n]=[escape $v]
    }
    return [join $pairs &]
}

proc oauth::sign {method req provider {tokensecret {}}} {
    variable secret
    # normalize request parameters
    dict unset req oauth_signature
    foreach key [lsort [dict keys $req]] {
        lappend sorted $key [dict get $req $key]
    }
    set query [escape [encode $sorted]]

    lappend secrets [escape $secret]
    lappend secrets [escape $tokensecret]
    set secrets [join $secrets &]

    set url [escape $provider]
    set hmac [::sha1::hmac -bin $secrets "$method&$url&$query"]
    return [base64::encode $hmac]
}

proc oauth::auth {method url req {secret ""}} {
    dict set req oauth_signature_method HMAC-SHA1
    dict set req oauth_version 1.0
    dict set req oauth_nonce [tag 40]
    dict set req oauth_timestamp [clock seconds]
    dict set req oauth_signature [sign $method $req $url $secret]
    dict for {key val} $req {
        if {[regexp {^oauth_} $key]} {
            lappend list [escape $key]="[escape $val]"
        }
    }

    return "OAuth [join $list {, }]"
}