
couchdbtcl
=====

A [Tcl] (http://tcl.tk) client interface to Apache CouchDB. The library consists of a single
[Tcl Module] (http://tcl.tk/man/tcl8.6/TclCmd/tm.htm#M9) file.

couchdbtcl is using  Tcl built-in package http to send request
to [Aapache CouchDB] (http://couchdb.apache.org/) and get response.


Interface
=====

The CouchDB API is the primary method of interfacing to a CouchDB instance.
Requests are made using HTTP and requests are used to request information
from the database, store new data, and perform views and formatting of the
information stored within the documents.

The library has 2 TclOO classes, CouchDB_Server and CouchDB_Database.

CouchDB_Server wrapper the CouchDB server interface, which provides
the basic interface to a CouchDB server for obtaining CouchDB
information and getting and setting configuration information.

CouchDB_Database wrapper the Database endpoint interface, which provides
an interface to an entire database with in CouchDB.


### Hello, CouchDB

These examples assume that CouchDB is running on localhost (127.0.0.1)
on port 5984 (in Admin Party mode).

First off, require the couchdbtcl package and create an instance of
the `CouchDB_Server` class, then say hello to CouchDB:

    package require couchdbtcl
    set mycouchdb [CouchDB_Server new localhost 5984 no]
    set response [$mycouchdb hello]
    puts $response

This issues a GET request to your CouchDB instance and gets response
(gets back a JSON string).

Next, we can get a list of databases:

    set response [$mycouchdb all_dbs]
    puts $response

Now, using CouchDB_Database to create a database named wiki:

    set mydatabase [CouchDB_Database new localhost 5984  wiki no]
    set response [$mydatabase create]
    puts $response

Retrieving the list of databases again shows some useful results this time:

    set response [$mycouchdb all_dbs]
    puts $response

Attempting to create a second database named wiki:

    set response [$mydatabase create]
    puts $response

We already have a database with that name, so CouchDB will respond with an error.

Create a document, asking CouchDB to supply a document id:

    set response [$mydatabase db_post {{"text" : "Wikipedia on CouchDB", "rating": 5}}]
    puts $response

Retrieve information about the wiki database

    set response [$mydatabase info]
    puts $response

Now try to delete this database:

    set response [$mydatabase delete]
    puts $response


### Authentication

By default a new instance of CouchDB runs in Admin Party mode – until the
first admin account is created, everyone’s an admin. In Admin Party mode,
connect to CouchDB setup auth type to no:

    set mydatabase [CouchDB_Database new localhost 5984 wiki no]

Basic authentication is a quick and simple way to authenticate with CouchDB.
The main drawback is the need to send user credentials with each request
which may be insecure and could hurt operation performance (since CouchDB
must compute password hash with every request).

Connect to CouchDB setup auth type to basic:

    set mydatabase [CouchDB_Database new localhost 5984 wiki basic $username $password]

For cookie authentication CouchDB generates a token that the client can use
for the next few requests to CouchDB. Tokens are valid until a timeout.
When CouchDB sees a valid token in a subsequent request, it will authenticate
user by this token without requesting the password again. By default, cookies
are valid for 10 minutes

Cookie Authentication, need use method cookie_post to initiate new session
for specified user credentials by providing Cookie value:

    set mydatabase [CouchDB_Database new localhost 5984 wiki cookie $username $password]
    # Initiates new session for specified user
    set response [$mydatabase cookie_post]
    puts $response
    # Closes user’s session.
    set response [$mydatabase cookie_delete]
    puts $response

CouchDB supports OAuth 1.0 authentication. OAuth provides a method for
clients to access server resources without sharing real credentials
(username and password).

OAuth Authentication, need use method oauth_set to setup key and token info:

    set mydatabase [CouchDB_Database new localhost 5984 wiki oauth]
    $mydatabase oauth_set $consumer_key $consumer_secret $token $token_secret


### Example

Below is a simple example (using tcllib json package to parse JSON string, OAUTH authentication):

    package require couchdbtcl
    package require json

    set consumer_key consumer1
    set consumer_secret sekr1t
    set token token1
    set token_secret tokensekr1t

    set mycouchdb [CouchDB_Server new localhost 5984 oauth]
    $mycouchdb oauth_set $consumer_key $consumer_secret $token $token_secret
    set response [$mycouchdb hello]
    set result [::json::json2dict $response]
    if {[dict exists $result error]==1} {
        puts "Connect to CouchDB fail."
        exit
    } else {
        if {[dict exists $result couchdb]==1} {
            puts "couchdb: [dict get $result couchdb]"
        }

        if {[dict exists $result version]==1} {
            puts "version: [dict get $result version]\n"
        }
    }

    set response [$mycouchdb all_dbs]
    set result [::json::json2dict $response]
    puts "Current database list: $result\n"

    set mydatabase [CouchDB_Database new localhost 5984  wiki oauth]
    $mydatabase oauth_set $consumer_key $consumer_secret $token $token_secret
    set response [$mydatabase create]
    set result [::json::json2dict $response]
    if {[dict exists $result error]==1} {
        puts "Create database fail."
        puts "Error: [dict get $result error]\n"
    } else {
        puts "Create database OK.\n"
    }

    set response [$mycouchdb all_dbs]
    set result [::json::json2dict $response]
    puts "Current database list: $result\n"

    set response [$mydatabase create]
    set result [::json::json2dict $response]
    if {[dict exists $result error]==1} {
        puts "Create database fail."
        puts "Error: [dict get $result error]\n"
    } else {
        puts "Create database OK.\n"
    }

    set response [$mydatabase db_post {{"text" : "Wikipedia on CouchDB", "rating": 5}}]
    set result [::json::json2dict $response]
    if {[dict exists $result error]==1} {
        puts "db_post fail."
        puts "Error: [dict get $result error]\n"
    } else {
        puts "db_post OK.\n"
    }

    set response [$mydatabase info]
    set result [::json::json2dict $response]
    puts "Databas info:"
    foreach key [dict keys $result] {
        puts "$key: [dict get $result $key]"
    }

    puts "\n"

    set response [$mydatabase delete]
    set result [::json::json2dict $response]
    if {[dict exists $result error]==1} {
        puts "Delete Database fail."
        puts "Error: [dict get $result error]\n"
    } else {
        puts "Delete Database OK.\n"
    }

Below is a simple documents example (Cookie authentication):

    package require couchdbtcl
    package require json

    #setup username and password
    set user admin
    set passwd admin

    set mydatabase [CouchDB_Database new localhost 5984 recipes cookie $user $passwd]
    set response [$mydatabase cookie_post]
    set result [::json::json2dict $response]
    if {[dict exists $result error]==1} {
        if {[dict exists $result reason]==1} {
            puts "reason: [dict get $result reason]\n"
        }

        puts "Create a new session fail, close."
        exit
    }

    set response [$mydatabase create]
    set result [::json::json2dict $response]
    if {[dict exists $result error]==1} {
        puts "Create database fail.\n"
        set reason [dict get $result error]

        # Except file_exists, close this program
        if {[string equal $reason "file_exists"] != 1} {
            exit
        }
    } else {
        puts "Create database OK.\n"
    }

    # Stores the specified document
    set response [$mydatabase doc_put SpaghettiWithMeatballs {
    {
        "description": "An Italian-American dish that usually consists of spaghetti, tomato sauce and meatballs.",
        "ingredients": [
            "spaghetti",
            "tomato sauce",
            "meatballs"
        ],
        "name": "Spaghetti with meatballs"
    }}]

    set result [::json::json2dict $response]
    if {[dict exists $result ok]==1} {
        puts "Stores the specified document OK.\n"
    } else {
        puts "Stores the specified document fail.\n"
    }

    # Gets the specified document
    set response [$mydatabase doc_get SpaghettiWithMeatballs]
    set result [::json::json2dict $response]

    # Gets current document’s revision
    set revid {}
    if {[dict exists $result _rev]==1} {
        set revid [dict get $result _rev]
    }

    puts "Gets the specified document result:"
    foreach key [dict keys $result] {
        puts "$key: [dict get $result $key]"
    }

    puts "\n"

    # Deletes the specified document
    set response [$mydatabase doc_delete SpaghettiWithMeatballs $revid]
    set result [::json::json2dict $response]
    if {[dict exists $result error]==1} {
        puts "Delete document fail."
        puts "Error: [dict get $result error]\n"
    } else {
        puts "Delete document OK.\n"
    }

    # Now print the database info
    # CouchDB doesn’t actually delete documents. So check current status.
    set response [$mydatabase info]
    set result [::json::json2dict $response]
    puts "Databas info:"
    foreach key [dict keys $result] {
        puts "$key: [dict get $result $key]"
    }

    puts "\n"

    set response [$mydatabase delete]
    set result [::json::json2dict $response]
    if {[dict exists $result error]==1} {
        puts "Delete Database fail."
        puts "Error: [dict get $result error]\n"
    } else {
        puts "Delete Database OK.\n"
    }

    set response [$mydatabase cookie_delete]
    set result [::json::json2dict $response]
    if {[dict exists $result error]==1} {
        if {[dict exists $result reason]==1} {
            puts "reason: [dict get $result reason]\n"
        }

        puts "Delete a session fail."
    } else {
        puts "Done, close this session."
    }

Below is a simple documents and attachment example (Basic authentication):

    package require couchdbtcl
    package require json

    #setup username and password
    set user admin
    set passwd admin

    set mydatabase [CouchDB_Database new localhost 5984 recipes basic $user $passwd]
    set response [$mydatabase create]
    set result [::json::json2dict $response]
    if {[dict exists $result error]==1} {
        puts "Create database fail.\n"
        set reason [dict get $result error]

        # Except file_exists, close this program
        if {[string equal $reason "file_exists"] != 1} {
            exit
        }
    } else {
        puts "Create database OK.\n"
    }

    # Stores the specified document
    set response [$mydatabase doc_put SpaghettiWithMeatballs {
    {
        "description": "An Italian-American dish that usually consists of spaghetti, tomato sauce and meatballs.",
        "ingredients": [
            "spaghetti",
            "tomato sauce",
            "meatballs"
        ],
        "name": "Spaghetti with meatballs"
    }}]

    set result [::json::json2dict $response]
    if {[dict exists $result ok]==1} {
        puts "Stores the specified document OK.\n"
    } else {
        puts "Stores the specified document fail.\n"
    }

    # Gets the specified document
    set response [$mydatabase doc_get SpaghettiWithMeatballs]
    set result [::json::json2dict $response]

    # Gets current document’s revision
    set revid {}
    if {[dict exists $result _rev]==1} {
        set revid [dict get $result _rev]
    }

    # Uploads the supplied content as an attachment to the specified document
    set response [$mydatabase docid_attachment_put SpaghettiWithMeatballs \
                  recipe.txt $revid text/plain {1. Cook spaghetti
    2. Cook meatballs
    3. Mix them
    4. Add tomato sauce
    5. ...
    6. PROFIT!}]
    set result [::json::json2dict $response]
    if {[dict exists $result ok]==1} {
        puts "Add attachment recipe.txt OK.\n"

        #Update revision
        set revid [dict get $result rev]
    } else {
        puts "Add attachment recipe.txt fail.\n"
    }

    # Gets the specified document
    set response [$mydatabase doc_get SpaghettiWithMeatballs]
    set result [::json::json2dict $response]
    if {[dict exists $result _attachments]==1} {
        puts "Gets the specified document and get attachment basic info:"
        set myattachments [dict get $result _attachments]
        set filename [dict keys $myattachments]
        puts "Filename: $filename"
        set content [dict get $myattachments $filename]
        set content_type [dict get $content content_type]
        puts "content_type: $content_type"
    }

    puts "\n"

    # Returns the file attachment associated with the document
    set response [$mydatabase docid_attachment_get \
                  SpaghettiWithMeatballs recipe.txt $revid]
    puts "Returns the file attachment body associated with the document:"
    puts $response
    puts "\n"

    # Deletes the attachment attachment of the specified doc
    set response [$mydatabase docid_attachment_delete \
                  SpaghettiWithMeatballs recipe.txt $revid]
    set result [::json::json2dict $response]
    if {[dict exists $result ok]==1} {
        puts "Delete attachment recipe.txt OK.\n"

        #Update revision
        set revid [dict get $result rev]
    } else {
        puts "Delete attachment recipe.txt fail.\n"
    }

    set response [$mydatabase delete]
    set result [::json::json2dict $response]
    if {[dict exists $result error]==1} {
        puts "Delete Database fail."
        puts "Error: [dict get $result error]\n"
    } else {
        puts "Delete Database OK.\n"
     }

## HTTPS support

If user enables HTTPS support, below is an example:

    package require couchdbtcl
    package require json

    #setup username and password
    set user admin
    set passwd admin

    set mydatabase [CouchDB_Server new localhost 6984 basic $user $passwd 1]
    set response [$mydatabase hello]
    set result [::json::json2dict $response]
    if {[dict exists $result error]==1} {
        puts "Connect to CouchDB fail."
        exit
    } else {
        if {[dict exists $result couchdb]==1} {
            puts "couchdb: [dict get $result couchdb]"
        }

        if {[dict exists $result version]==1} {
            puts "version: [dict get $result version]\n"
        }
    }

Please notice, I use [TLS extension] (http://tls.sourceforge.net/) to add https support. So https support needs TLS extension.

