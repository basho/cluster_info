The cluster_info application
============================

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
data type instead.  If a prerequisite OTP application, `riak_err`, is
available, then this application can use the
`riak_err_handler:limited_fmt/4` function to attempt to limit the
amount of memory used while generating reports.

To limit the amount of RAM used to format strings in a report, this
application will attempt to fetch the following OTP application
environment variables from either the `riak_err` app's variables or
the `cluster_info` app's variables:

* `term_max_size` Report output is formatted via
`cluster_info:format(FormatString, ArgList)` calls.
If the total size of ArgList is more than `term_max_size`,
then we'll ignore `FormatString` and log the message with a well-known
(and therefore safe) formatting string instead.
* `fmt_max_bytes` When formatting a log-related term that might
be "big", limit the term's formatted output to a maximum of
`fmt_max_bytes` bytes.  

The default for both values is 256KB.

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

If the `term_max_size` environment variable is not defined (by neither
the `riak_err` application nor the `cluster_info` application), then
the length of formatted strings will not be restricted.

If the `term_max_size` environment variable is defined but the BEAM
object file `riak_err_handler` is not available, then attempts to
generate a report will throw undefined function exceptions.  As noted
at the top of this section, the `riak_err` application must be
compiled and packaged together with the `cluster_info` application.

Requesting dumps over HTTP
--------------------------

`cluster_info` includes a Webmachine resource that allows you to fetch
dumps over HTTP, which could be useful as part of an automated
monitoring system. The resource is disabled by default, but can be
enabled by setting the `cluster_info` environment variable
`web_enabled` to `true`. That will cause the resource to be added to
the Webmachine routes at the default URI of "/cluster_info". The path
to the resource can also be configured via the `web_path` variable,
which should be a valid Webmachine path specification. Finally, the
resource makes use of the local filesystem for storing `cluster_info`
dumps while they are being generated. The path it uses defaults to the
operating system's temporary directory but can be configured via the
`temp_dir` variable.

Configuration example:

    {cluster_info, [{web_enabled, true},
                    {web_path, ["ci"]},
                    {temp_dir, "/tmp/ci/dumps"}]}.

By default, the resource performs only a local `cluster_info` dump,
but can also dump all connected nodes or specific nodes using the
`node` query parameter. The following request will dump all nodes:

    GET /cluster_info?node=all

The request below will dump nodes `ci@a` and `ci@b`:

    GET /cluster_info?node=ci@a&node=ci@b

Licensing
---------

The `cluster_info` application was written by
[Gemini Mobile Technologies, Inc.](http://www.geminimobile.com/)
and is licensed under the
[Apache Public License version 2.0](http://www.apache.org/licenses/LICENSE-2.0).
This fork of the code has been subsequently modified by
[Basho Technologies, Inc.](http://www.basho.com/) and is distributed
under the same license.

