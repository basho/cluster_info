%%%----------------------------------------------------------------------
%%% Copyright: (c) 2009-2010 Gemini Mobile Technologies, Inc.  All rights reserved.
%%%
%%% Licensed under the Apache License, Version 2.0 (the "License");
%%% you may not use this file except in compliance with the License.
%%% You may obtain a copy of the License at
%%%
%%%     http://www.apache.org/licenses/LICENSE-2.0
%%%
%%% Unless required by applicable law or agreed to in writing, software
%%% distributed under the License is distributed on an "AS IS" BASIS,
%%% WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
%%% See the License for the specific language governing permissions and
%%% limitations under the License.
%%%
%%% File     : cluster_info.erl
%%% Purpose  : Cluster info/postmortem data gathering app
%%%----------------------------------------------------------------------

-module(cluster_info).

-behaviour(application).

-define(DICT_KEY, '^_^--cluster_info').

%% application callbacks
%% Note: It is *not* necessary to start this application as a real/true OTP
%%       application before you can use it.  The application behavior here
%%       is only to help integrate this code nicely into OTP-style packaging.
-export([start/0, start/2, stop/1]).
-export([start_phase/3, prep_stop/1, config_change/3]).

-export([register_app/1,
         dump_node/2, dump_local_node/1, dump_all_connected/1, dump_nodes/2,
         send/2, format/2, format/3]).
-export([get_limits/0, reset_limits/0]).

%% Really useful but ugly hack.
-export([capture_io/2]).

-type dump_return() :: 'ok' | 'error'.
-type filename()  :: string().
-spec start() -> {ok, pid()}.
-spec start(_,_) -> {ok, pid()}.
-spec start_phase(_,_,_) -> 'ok'.
-spec prep_stop(_) -> any().
-spec config_change(_,_,_) -> 'ok'.
-spec register_app(atom()) -> 'ok' | 'undef'.
-spec dump_node(atom(), filename()) -> dump_return().
-spec dump_local_node(filename()) -> [dump_return()].
-spec dump_all_connected(filename()) -> [dump_return()].
-spec dump_nodes([atom()], filename()) -> [dump_return()].
-spec stop(_) -> 'ok'.
-spec capture_io(integer(), function()) -> [term()].

%%%----------------------------------------------------------------------
%%% Callback functions from application
%%%----------------------------------------------------------------------

%%----------------------------------------------------------------------
%% Func: start/2
%% Returns: {ok, Pid}
%%----------------------------------------------------------------------
start() ->
    start(start, []).

start(_Type, _StartArgs) ->
    case application:get_env(?MODULE, skip_basic_registration) of
        undefined ->
            register_app(cluster_info_basic);
        _ ->
            ok
    end,
    {ok, spawn(fun() -> receive pro_forma -> ok end end)}.

%% Lesser-used callbacks....

start_phase(_Phase, _StartType, _PhaseArgs) ->
    ok.

prep_stop(State) ->
    State.

config_change(_Changed, _New, _Removed) ->
    ok.

%% @spec (atom()) -> ok | undef
%% @doc "Register" an application with the cluster_info app.
%%
%% "Registration" is a misnomer: we're really interested only in
%% having the code server load the callback module, and it's that
%% side-effect with the code server that we rely on later.

register_app(CallbackMod) ->
    try
        CallbackMod:cluster_info_init()
    catch
        error:undef ->
            undef
    end.

%% @spec (atom(), path()) -> term()
%% @doc Dump the cluster_info on Node to the specified local File.

dump_node(Node, Path) when is_atom(Node), is_list(Path) ->
    io:format("dump_node ~p, file ~p:~p\n", [Node, node(), Path]),
    Collector = self(),
    {ok, FH} = file:open(Path, [append]),
    Remote = spawn(Node, fun() ->
                                 dump_local_info(Collector),
                                 collector_done(Collector)
                         end),
    {ok, MRef} = gmt_util_make_monitor(Remote),
    Res = try
              ok = collect_remote_info(Remote, FH)
          catch X:Y ->
                  io:format("Error: ~P ~P at ~p\n",
                            [X, 20, Y, 20, erlang:get_stacktrace()]),
                  error
          after
              catch file:close(FH),
              gmt_util_unmake_monitor(MRef)
          end,
    Res.

%% @spec (path()) -> term()
%% @doc Dump the cluster_info on local node to the specified File.

dump_local_node(Path) ->
    dump_nodes([node()], Path).

%% @spec (path()) -> term()
%% @doc Dump the cluster_info on all connected nodes to the specified
%%      File.

dump_all_connected(Path) ->
    dump_nodes([node()|nodes()], Path).

%% @spec (list(atom()), path()) -> term()
%% @doc Dump the cluster_info on all specified nodes to the specified
%%      File.

dump_nodes(Nodes, Path) ->
    [dump_node(Node, Path) || Node <- lists:sort(Nodes)].

send(Pid, IoList) ->
    Pid ! {collect_data, self(), IoList}.

format(Pid, Fmt) ->
    format(Pid, Fmt, []).

format(Pid, Fmt, Args) ->
    send(Pid, safe_format(Fmt, Args)).

%%----------------------------------------------------------------------
%% Func: stop/1
%% Returns: any
%%----------------------------------------------------------------------
stop(_State) ->
    ok.

%%%----------------------------------------------------------------------
%%% Internal functions
%%%----------------------------------------------------------------------

collect_remote_info(Remote, FH) ->
    receive
        {'DOWN', _, X, Remote, Z} ->
            io:format("Remote error: ~p ~p (~p)\n    -> ~p\n",
                      [X, Remote, node(Remote), Z]),
            ok;
        {collect_data, Remote, IoList} ->
            file:write(FH, IoList),
            collect_remote_info(Remote, FH);
        {collect_done, Remote} ->
            ok
    after 120*1000 ->
            timeout
    end.

collector_done(Pid) ->
    Pid ! {collect_done, self()}.

dump_local_info(CPid) ->
    dbg("D: node = ~p\n", [node()]),
    format(CPid, "\n"),
    format(CPid, "Local node cluster_info dump\n"),
    format(CPid, "============================\n"),
    format(CPid, "\n"),
    format(CPid, "== Node: ~p\n", [node()]),
    format(CPid, "\n"),
    Mods = lists:sort([Mod || {Mod, _Path} <- code:all_loaded()]),
    [case (catch Mod:cluster_info_generator_funs()) of
         {'EXIT', _} ->
             ok;
         NameFuns when is_list(NameFuns) ->
             [try
                  dbg("D: generator ~p ~s\n", [Fun, Name]),
                  format(CPid, "= Generator name: ~s\n\n", [Name]),
                  Fun(CPid),
                  format(CPid, "\n")
              catch X:Y ->
                      format(CPid, "Error in ~p: ~p ~p at ~p\n",
                             [Name, X, Y, erlang:get_stacktrace()])
              end || {Name, Fun} <- NameFuns]
     end || Mod <- Mods],
    ok.

dbg(_Fmt, _Args) ->
    ok.

%%%%%%%%%

%% @doc This is an untidy hack.

capture_io(Timeout, Fun) ->
    Me = self(),
    spawn(fun() -> capture_io2(Timeout, Fun, Me) end),
    lists:flatten(harvest_reqs(Timeout)).

capture_io2(Timeout, Fun, Parent) ->
    group_leader(self(), self()),
    Fudge = 50,
    Worker = spawn(fun() -> Fun(), timer:sleep(Fudge), Parent ! io_done2 end),
    spawn(fun() -> timer:sleep(Timeout + Fudge + 10), exit(Worker, kill) end),
    get_io_reqs(Parent, Timeout).

get_io_reqs(Parent, Timeout) ->
    receive
        {io_request, From, _, Req} ->
            From ! {io_reply, self(), ok},
            Parent ! {io_data, Req},
            get_io_reqs(Parent, Timeout)
    after Timeout ->
            ok
    end.

harvest_reqs(Timeout) ->
    receive
        {io_data, Req} ->
            case Req of
                {put_chars, _, Mod, Fun, Args} ->
                    [erlang:apply(Mod, Fun, Args)|harvest_reqs(Timeout)];
                {put_chars, _, Chars} ->
                    [Chars|harvest_reqs(Timeout)]
            end;
        io_done ->
            [];
        io_done2 ->
            []
    after Timeout ->
            []
    end.

safe_format(Fmt, Args) ->
    list_to_binary(safe_format2(Fmt, Args)).

safe_format2(Fmt, Args) ->
    case get_limits() of
        {undefined, _} ->
            io_lib:format(Fmt, Args);
        {TermMaxSize, FmtMaxBytes} ->
            riak_err_handler:limited_fmt(Fmt, Args, TermMaxSize, FmtMaxBytes)
    end.

get_limits() ->
    case erlang:get(?DICT_KEY) of
        undefined ->
            case code:which(riak_err_handler) of
                non_existing ->
                    {undefined, undefined};
                _ ->
                    %% Use factor of 4 because riak_err's settings are
                    %% fairly conservative by default, e.g. 64KB.
                    Apps = [{riak_err, 4}, {cluster_info, 1}],
                    Res = {try_app_envs(Apps, term_max_size, default_size()),
                           try_app_envs(Apps, fmt_max_bytes, default_size())},
                    erlang:put(?DICT_KEY, Res),
                    Res
            end;
        T when is_tuple(T) ->
            T
    end.

reset_limits() -> erlang:erase(?DICT_KEY).

default_size() -> 256*1024.

try_app_envs([{App, Factor}|Apps], Key, Default) ->
    case application:get_env(App, Key) of
        undefined ->
            try_app_envs(Apps, Key, Default);
        {ok, N} ->
            N * Factor
    end;
try_app_envs([], _, Default) ->
    Default.

%% From gmt_util.erl, also Apache Public License'd.

%% @spec (server_spec()) -> {ok, monitor_ref()} | error
%% @doc Simplify the arcane art of <tt>erlang:monitor/1</tt>:
%%      create a monitor.
%%
%% The arg may be a PID or a {registered_name, node} tuple.
%% In the case of the tuple, we will use rpc:call/4 to find the
%% server's actual PID before calling erlang:monitor();
%% therefore there is a risk of blocking by the RPC call.
%% To avoid the risk of blocking in this case, use make_monitor/2.

gmt_util_make_monitor(Pid) when is_pid(Pid) ->
    case catch erlang:monitor(process, Pid) of
        MRef when is_reference(MRef) ->
            receive
                {'DOWN', MRef, _, _, _} ->
                    error
            after 0 ->
                    {ok, MRef}
            end;
        _ ->
            error
    end.

%% @spec (pid()) -> {ok, monitor_ref()} | error
%% @doc Simplify the arcane art of <tt>erlang:demonitor/1</tt>:
%%      destroy a monitor.

gmt_util_unmake_monitor(MRef) ->
    erlang:demonitor(MRef),
    receive
        {'DOWN', MRef, _, _, _} ->
            ok
    after 0 ->
            ok
    end.
