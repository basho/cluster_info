The cluster_info application
============================

[![Build Status](https://secure.travis-ci.org/basho/cluster_info.png?branch=master)](http://travis-ci.org/basho/cluster_info)

The `cluster_info` application provides a flexible and easily-extendible
way to dump the state of a cluster of Erlang nodes.

Some of the information that the application can gather includes:

* Date & time
* Statistics on all Erlang processes on the node
* Network connection details to all other Erlang nodes
* Top CPU- and memory-hogging processes
* Processes with large mailboxes
* Internal memory allocator statistics
* ETS table information
* The names & versions of each code module loaded into the node

The app can also automatically gather all of this data from all nodes
and write it into a single file. It's about as easy as can be to take
a snapshot of all nodes in a cluster. It is a valuable tool for
support and development teams to diagnose problems in a cluster, as a
tool to aid capacity planning, and merely to answer a curious question
like, "What's really going on in there?"

Example usage
-------------

* `cluster_info:dump_all_connected("/tmp/report.all-nodes.txt").`
* `cluster_info:dump_local_node("/tmp/report.local-node.txt").`
* `cluster_info:dump_nodes([riak@boxA, riak@boxB], "/tmp/report.some-nodes.txt").`

See the file `example-output.Riak.txt` (in the top of the repository) for
sample output from a single-node Riak system.  Use the regular
expression `^==* ` to find major & minor sections within the file.
(*NOTE* The regular expression has a space character at the end of it.)

Configuring maximum string length formatting limits
---------------------------------------------------

It's a well-known feature of Erlang that the default string
representation is a list of byte values.  Strings can consume much
more RAM than if the equivalent data were stored in the Erlang binary
data type instead.  If a prerequisite OTP application, `lager`, is
available, then this application can use the
`lager_format:format/4` function to attempt to limit the
amount of memory used while generating reports.

To limit the amount of RAM used to format strings in a report, this
application will attempt to fetch the following OTP application
environment variable from the `cluster_info` app's variables:

* `fmt_max_bytes` When formatting a log-related term that might
be "big", limit the term's formatted output to a maximum of
`fmt_max_bytes` bytes.

The default value is 256KB.

You have several options for configuring these OTP application
environment variables:

* Add the following to your packaging's system configuration file
  (which is specified by the `-config /path/to/file` flag to the
  runtime system ... see the
  [online docs for configuration OTP applications, "7.8  Configuring an Application"](http://www.erlang.org/doc/design_principles/applications.html#id71589)
  for more details:

    `{cluster_info, [{term_max_size, 65536}, {fmt_max_bytes, 65536}]}`

* Add the following the `env` section of your copy of the
  package's `ebin/cluster_info.app` file

    `{env, [{term_max_size, 65536}, {fmt_max_bytes, 65536}]}`

* Execute the following code to set the environment variables at
  runtime.  Please note that setting these parameters will only affect
  processes that are created after the values are set:

    `application:set_env(cluster_info, term_max_size, 65536),
    application:set_env(cluster_info, fmt_max_bytes, 65536)`

If the `fmt_max_bytes` environment variable is not defined, then
the length of formatted strings will not be restricted.

Licensing
---------

The `cluster_info` application was written by
[Gemini Mobile Technologies, Inc.](http://www.geminimobile.com/)
and is licensed under the
[Apache Public License version 2.0](http://www.apache.org/licenses/LICENSE-2.0).
This fork of the code has been subsequently modified by
[Basho Technologies, Inc.](http://www.basho.com/) and is distributed
under the same license.

