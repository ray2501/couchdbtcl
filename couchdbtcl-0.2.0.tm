# couchdbtcl --
#
#	A TCL client interface to Apache CouchDB
#
# Copyright (C) 2015-2018 Danilo Chang <ray2501@gmail.com>
#
# Retcltribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Retcltributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
# 2. Retcltributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#

package require Tcl 8.6-
package require myoauth
package require TclOO
package require http
package require base64

package provide couchdbtcl 0.2.0


#
# CouchDB_Request class: handle send request to CouchDB
#
oo::class create CouchDB_Request {
    variable authtype
    variable username
    variable password
    variable firstcookie
    variable consumer_secret
    variable consumer_key
    variable token
    variable token_secret
    variable accessToken
    variable authSession

    constructor {AUTHTYPE {USERNAME ""} {PASSWORD ""}} {
        set authtype $AUTHTYPE
        set username $USERNAME
        set password $PASSWORD
        set firstcookie 0
        set consumer_secret ""
        set consumer_key ""
        set token ""
        set token_secret ""
        set accessToken ""
        set authSession ""
    }

    destructor {
    }

    method setFirstCookie {value} {
        set firstcookie $value
    }

    method oauth_set {CONSUMER_KEY CONSUMER_SECRET TOKEN {TOKEN_SECRET ""}} {
        set consumer_key $CONSUMER_KEY
        set consumer_secret $CONSUMER_SECRET
        set token $TOKEN
        set token_secret $TOKEN_SECRET
    }

    method getAuthSession {} {
        return $authSession
    }

    method send_request {url method {headers ""} {data ""}} {
        # Now support authtype: no basic cookie oauth
        if {[string compare -nocase $authtype "basic"]==0} {
            set auth "Basic [base64::encode $username:$password]"
            lappend headers Authorization $auth
        } elseif {[string compare -nocase $authtype "cookie"]==0} {
            if {$firstcookie==1} {
                set data [::http::formatQuery name $username password $password]
            } else {
                set cookiestring "AuthSession=$authSession"
                lappend headers Cookie $cookiestring
            }
        } elseif {[string compare -nocase $authtype "oauth"]==0} {
            oauth::secret $consumer_secret

            dict set req oauth_consumer_key $consumer_key
            dict set req oauth_token $token

            # Using oauth package to get AccessToken and record it
            set accessToken [oauth::auth $method $url $req $token_secret]
            lappend headers Authorization $accessToken
        }

        if { [string length $data] < 1 } {
            if {[catch {set tok [http::geturl $url -method $method \
                -headers $headers]}]} {
                return -code error {{"error": "connect failed"}}
            }
        } else {
            if {[catch {set tok [http::geturl $url -method $method \
                -headers $headers -query $data]}]} {
                return -code error {{"error": "connect failed"}}
            }
        }

        if {[string compare -nocase $authtype "cookie"]==0 && $firstcookie==1} {
            set meta [http::meta $tok]
            foreach {name value} $meta {
                if {[string compare $name Set-Cookie]==0} {
                    set firstlocation [string first "=" $value]
                    incr firstlocation 1
                    set lastlocation  [string first "; " $value]
                    incr lastlocation -1
                    set authSession [string range $value $firstlocation $lastlocation]
                    break
                }
            }
        }

        set res [http::data $tok]
        set ncode [::http::ncode $tok]
        http::cleanup $tok

        if {$ncode >= 400} {
            return -code error {{"error": "status code error"}}
        }

        return $res
    }
}


#
# The CouchDB server interface provides the basic interface to a CouchDB
# server for obtaining CouchDB information and getting and setting
# configuration information.
#
oo::class create CouchDB_Server {
    variable protocol
    variable host
    variable port
    variable server
    variable authtype
    variable myrequest
    variable ssl_enabled

    constructor {HOST PORT AUTHTYPE {USERNAME ""} {PASSWORD ""} {SSL_ENABLED 0}} {
        set host $HOST
        set port $PORT
        set authtype $AUTHTYPE
        set myrequest [CouchDB_Request new $authtype $USERNAME $PASSWORD]
        set ssl_enabled $SSL_ENABLED

        if {$ssl_enabled} {
            set protocol "https"

            if {[catch {package require tls}]==0} {
                http::register https 443 [list ::tls::socket -autoservername 1 \
                                          -require 0 -ssl3 0 -tls1 0 -tls1.1 0 \
                                          -tls1.2 1 -tls1.3 1]
            } else {
                error "SSL_ENABLED needs package tls..."
            }
        } else {
            set protocol "http"
        }

        set server "$protocol://$host:$port"
    }

    destructor {
        $myrequest destroy
    }

    # Use oauth to get access token and check CouchDB accept it
    method oauth_set {CONSUMER_KEY CONSUMER_SECRET TOKEN {TOKEN_SECRET ""}} {
        $myrequest oauth_set $CONSUMER_KEY $CONSUMER_SECRET $TOKEN $TOKEN_SECRET
    }

    # Initiates new session for specified user credentials by providing Cookie value.
    method cookie_post {} {
        $myrequest setFirstCookie 1
        set myurl "$server/_session"
        set headerl [list Accept "application/json" Content-Type "application/x-www-form-urlencoded"]
        try {
            set res [$myrequest send_request $myurl POST $headerl]
        } on error {em} {
            return $em
        }

        $myrequest setFirstCookie 0

        return $res
    }

    # Returns complete information about authenticated user.
    method cookie_get {} {
        set myurl "$server/_session"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Closes user session.
    method cookie_delete {} {
        set myurl "$server/_session"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl DELETE $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Accessing the root of a CouchDB instance returns meta information
    # about the instance.
    method hello {} {
        set myurl "$server/"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # List of running tasks, including the task type, name, status and process ID.
    method active_tasks {} {
        set myurl "$server/_active_tasks"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Returns a list of all the databases in the CouchDB instance.
    method all_dbs {} {
        set myurl "$server/_all_dbs"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Returns a list of all database events in the CouchDB instance.
    method log {} {
        set myurl "$server/_log"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    #
    # CouchDB replication is a mechanism to synchronize databases. Much
    # like rsync synchronizes two directories locally or over a network,
    # replication synchronizes two databases locally or remotely.
    #

    # Request, configure, or stop, a replication operation.
    method replicate {data} {
        set myurl "$server/_replicate"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl POST $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Restarts the CouchDB instance.
    # The node-local endpoint has been removed at 2.3.0
    method restart {} {
        set myurl "$server/_restart"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl POST $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Returns a JSON object containing the statistics for the running server.
    method stats {} {
        set myurl "$server/_stats"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    #Requests one or more Universally Unique Identifiers (UUIDs) from the CouchDB instance
    method uuids {{count 1}} {
        set myurl "$server/_uuids?count=$count"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }
}


#
# The Database endpoint provides an interface to an entire database with
# in CouchDB. These are database-level, rather than document-level requests.
#
oo::class create CouchDB_Database {
    variable protocol
    variable host
    variable port
    variable server
    variable database
    variable authtype
    variable myrequest
    variable ssl_enabled

    constructor {HOST PORT DATABASE AUTHTYPE {USERNAME ""} {PASSWORD ""} {SSL_ENABLED 0}} {
        set host $HOST
        set port $PORT
        set database $DATABASE
        set authtype $AUTHTYPE
        set myrequest [CouchDB_Request new $authtype $USERNAME $PASSWORD]
        set ssl_enabled $SSL_ENABLED

        if {$ssl_enabled} {
            set protocol "https"

            if {[catch {package require tls}]==0} {
                http::register https 443 [list ::tls::socket -autoservername 1 \
                                          -require 0 -ssl3 0 -tls1 0 -tls1.1 0 \
                                          -tls1.2 1 -tls1.3 1]
            } else {
                error "SSL_ENABLED needs package tls..."
            }
        } else {
            set protocol "http"
        }

        set server "$protocol://$host:$port"
    }

    destructor {
        $myrequest destroy
    }

    # Use oauth to get access token and check CouchDB accept it
    method oauth_set {CONSUMER_KEY CONSUMER_SECRET TOKEN {TOKEN_SECRET ""}} {
        $myrequest oauth_set $CONSUMER_KEY $CONSUMER_SECRET $TOKEN $TOKEN_SECRET
    }

    # Initiates new session for specified user credentials by providing Cookie value.
    method cookie_post {} {
        $myrequest setFirstCookie 1
        set myurl "$server/_session"
        set headerl [list Accept "application/json" Content-Type "application/x-www-form-urlencoded"]
        try {
            set res [$myrequest send_request $myurl POST $headerl]
        } on error {em} {
            return $em
        }

        $myrequest setFirstCookie 0

        return $res
    }

    # Returns complete information about authenticated user.
    method cookie_get {} {
        set myurl "$server/_session"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Closes user’s session.
    method cookie_delete {} {
        set myurl "$server/_session"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl DELETE $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Creates a new database.
    method create {} {
        set myurl "$server/$database"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl PUT $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Gets information about the specified database.
    method info {} {
        set myurl "$server/$database"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Delete a database.
    method delete {} {
        set myurl "$server/$database"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl DELETE $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Creates a new document in the specified database,
    # using the supplied JSON document structure.
    method db_post {data} {
        set myurl "$server/$database"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl POST $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Returns a JSON structure of all of the documents in a given database.
    method all_docs_get {{data ""}} {
        set myurl "$server/$database/_all_docs"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET  $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # The POST to _all_docs allows to specify multiple keys to be
    # selected from the database.
    method all_docs_post {data} {
        set myurl "$server/$database/_all_docs"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl POST $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # The bulk document API allows you to create and update multiple
    # documents at the same time within a single request.
    method bulk_docs {data} {
        set myurl "$server/$database/_bulk_docs"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl POST $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # For CouchDB 2.0 Mango Query
    # Find documents using a declarative JSON querying syntax
    method find {{data ""}} {
        set myurl "$server/$database/_find"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl POST $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # For CouchDB 2.0 Mango Query
    # Create a new index on a database
    method index_post {{data ""}} {
        set myurl "$server/$database/_index"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl POST $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # For CouchDB 2.0 Mango Query
    # When you make a GET request to /db/_index, 
    # you get a list of all indexes in the database
    method index_get {} {
        set myurl "$server/$database/_index"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # For CouchDB 2.0 Mango Query
    # Delete an index
    method index_delete {ddocument indexName} {
        set myurl "$server/$database/_index/$ddocument/json/$indexName"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl DELETE $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # For CouchDB 2.0 Mango Query
    # Shows which index is being used by the query
    method explain {{data ""}} {
        set myurl "$server/$database/_explain"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl POST $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Requests the database changes feed
    method changes {{data ""}} {
        set myurl "$server/$database/_changes"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Request compaction of the specified database.
    method compact {} {
        set myurl "$server/$database/_compact"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl POST $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Commits any recent changes to the specified database to disk.
    method ensure_full_commit {} {
        set myurl "$server/$database/_ensure_full_commit"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl POST $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Removes view index files that are no longer required by CouchDB as a
    # result of changed views within design documents.
    method view_cleanup {} {
        set myurl "$server/$database/_view_cleanup"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl POST $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Returns the current security object from the specified database.
    #
    # If the security object for a database has never been set, then the
    # value returned will be empty.
    method security_get {} {
        set myurl "$server/$database/_security"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Sets the security object for the given database.
    method security_put {data} {
        set myurl "$server/$database/_security"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl PUT $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # A database purge permanently removes the references to deleted
    # documents from the database.
    method purge {data} {
        set myurl "$server/$database/_purge"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        set res [$myrequest send_request $myurl POST $headerl $data]

        return $res
    }

    # With given a list of document revisions, returns the document
    # revisions that do not exist in the database.
    method missing_revs {data} {
        set myurl "$server/$database/_missing_revs"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl POST $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Given a set of document/revision IDs, returns the subset of those
    # that do not correspond to revisions stored in the database.
    method revs_diff {data} {
        set myurl "$server/$database/_revs_diff"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl POST $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Gets the current revs_limit (revision limit) setting.
    method revs_limit_get {} {
        set myurl "$server/$database/_revs_limit"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Sets the maximum number of document revisions that will be tracked by
    # CouchDB, even after compaction has occurred.
    method revs_limit_put {data} {
        set myurl "$server/$database/_revs_limit"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl PUT $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    #
    # Method for Apache couchDB Document API
    # Each document in CouchDB has an ID. This ID is unique per database.
    #

    # Gets the specified document.
    method doc_get {id {data ""}} {
        set myurl "$server/$database/$id"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Stores the specified document.
    method doc_put {id data} {
        set myurl "$server/$database/$id"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl PUT $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Deletes the specified document.
    # rev - Actual document’s revision
    method doc_delete {id rev} {
        set myurl "$server/$database/$id"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        lappend headerl If-Match $rev
        try {
            set res [$myrequest send_request $myurl DELETE $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Copies the specified document.
    # destination – Destination document
    method doc_copy {id destination} {
        set myurl "$server/$database/$id"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        lappend headerl Destination $destination
        try {
            set res [$myrequest send_request $myurl COPY $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Returns the file attachment associated with the document.
    # revision is Document revision.
    method docid_attachment_get {id attname revision} {
        set myurl "$server/$database/$id/$attname"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        lappend  headerl If-Match $revision
        try {
            set res [$myrequest send_request $myurl GET $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Uploads the supplied content as an attachment to the specified document.
    # revision is Document revision.
    # ContentType need give it a Attachment MIME type. Required!
    method docid_attachment_put {id attname revision ContentType data} {
        set myurl "$server/$database/$id/$attname"
        set headerl [list Content-Type $ContentType]
        lappend  headerl If-Match $revision
        try {
            set res [$myrequest send_request $myurl PUT $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Deletes the attachment of the specified doc.
    # revision is Document revision.
    method docid_attachment_delete {id attname revision} {
        set myurl "$server/$database/$id/$attname"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        lappend  headerl If-Match $revision
        try {
            set res [$myrequest send_request $myurl DELETE $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    #
    # In CouchDB, design documents provide the main interface for building
    # a CouchDB application. The design document defines the views used to
    # extract information from CouchDB through one or more views.
    #

    # Returns the contents of the design document specified with the name
    # of the design document and from the specified database from the URL.
    method designdoc_get {ddocument} {
        set myurl "$server/$database/_design/$ddocument"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # The PUT method creates a new named design document, or creates a new
    # revision of the existing design document.
    method designdoc_put {ddocument data} {
        set myurl "$server/$database/_design/$ddocument"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl PUT $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Deletes the specified document from the database.
    method designdoc_delete {ddocument revision} {
        set myurl "$server/$database/_design/$ddocument"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        lappend  headerl If-Match $revision
        try {
            set res [$myrequest send_request $myurl DELETE $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # The COPY (which is non-standard HTTP) copies an existing
    # design document to a new or existing one.
    # destination – Destination document
    method designdoc_copy {ddocument destination} {
        set myurl "$server/$database/_design/$ddocument"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        lappend header1 Destination $destination
        try {
            set res [$myrequest send_request $myurl COPY $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Returns the file attachment associated with the design document.
    # The raw data of the associated attachment is returned (just as if
    # you were accessing a static file.
    method designdoc_attachment_get {ddocument attname revision} {
        set myurl "$server/$database/_design/$ddocument/$attname"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        lappend  headerl If-Match $revision
        try {
            set res [$myrequest send_request $myurl GET $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Uploads the supplied content as an attachment to the specified
    # design document. The attachment name provided must be a URL encoded string.
    # revision is Document revision.
    # ContentType need give it a Attachment MIME type. Required!
    method designdoc_attachment_put {ddocument attname revision ContentType data} {
        set myurl "$server/$database/_design/$ddocument/$attname"
        set headerl [list Content-Type $ContentType]
        lappend  headerl If-Match $revision
        try {
            set res [$myrequest send_request $myurl PUT $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Deletes the attachment of the specified design document.
    # revision is Document revision.
    method designdoc_attachment_delete {ddocument attname revision} {
        set myurl "$server/$database/_design/$ddocument/$attname"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        lappend  headerl If-Match $revision
        try {
            set res [$myrequest send_request $myurl DELETE $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Obtains information about the specified design document, including
    # the index, index size and current status of the design document and
    # associated index information.
    method designdoc_info {ddocument} {
        set myurl "$server/$database/_design/$ddocument/_info"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Executes the specified view function from the specified design document.
    method designdoc_view_get {ddocument viewname {data ""}} {
        set myurl "$server/$database/_design/$ddocument/_view/$viewname"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl GET $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Executes the specified view function from the specified design document.
    method designdoc_view_post {ddocument viewname data} {
        set myurl "$server/$database/_design/$ddocument/_view/$viewname"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl POST $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Executes update function on server side for null document.
    method designdoc_update_post {ddocument updatename data} {
        set myurl "$server/$database/_design/$ddocument/_update/$updatename"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl POST $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }

    # Executes update function on server side for null document.
    method designdoc_updatename_post {ddocument updatename docid data} {
        set myurl "$server/$database/_design/$ddocument/_update/$updatename/$docid"
        set headerl [list Accept "application/json" Content-Type "application/json"]
        try {
            set res [$myrequest send_request $myurl PUT $headerl $data]
        } on error {em} {
            return $em
        }

        return $res
    }
}
