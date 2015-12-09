
couchdbtcl
=====

A [Tcl] (http://tcl.tk) client interface to Apache CouchDB. The library consists of a single
[Tcl Module] (http://tcl.tk/man/tcl8.6/TclCmd/tm.htm#M9) file.

couchdbtcl is using  Tcl built-in package http to send request
to [Aapache CouchDB] (http://couchdb.apache.org/) and get response.


Interafce
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
